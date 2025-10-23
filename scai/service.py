import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time
from contextlib import suppress
from pathlib import Path
from urllib.parse import urlparse
from uuid import uuid4
import shutil

from selenium import webdriver
from selenium.common.exceptions import NoSuchWindowException, WebDriverException
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service as ChromeService

from .config import BASE_DIR, HOST, LOG_PATH, PID_PATH, PORT, RUNTIME_DIR

CERTIFICATE_DIR = BASE_DIR / "certs"


class SeleniumService:
    def __init__(self) -> None:
        RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
        with suppress(Exception):
            RUNTIME_DIR.chmod(0o700)
        self.driver = None
        self.active_handle = None
        self.id_sequence = 0
        self.id_to_handle = {}
        self.handle_to_id = {}
        self.network_profile = "online"
        self.lock = threading.Lock()
        self.profile_dir: Path | None = None
        signal.signal(signal.SIGTERM, self.handle_signal)
        signal.signal(signal.SIGINT, self.handle_signal)

    def handle_signal(self, _sig, _frame) -> None:
        self.shutdown()
        sys.exit(0)

    def start(self) -> None:
        self.ensure_driver()
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((HOST, PORT))
        server.listen()
        PID_PATH.write_text(str(os.getpid()), encoding="utf-8")
        try:
            running = True
            while running:
                conn, _addr = server.accept()
                with conn:
                    payload = self.read_request(conn)
                    if not payload:
                        continue
                    response, running = self.handle_request(payload)
                    conn.sendall(json.dumps(response).encode("utf-8"))
        finally:
            server.close()
            self.shutdown()

    def read_request(self, conn: socket.socket) -> dict:
        data = bytearray()
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break
            data.extend(chunk)
        if not data:
            return {}
        try:
            return json.loads(data.decode("utf-8"))
        except json.JSONDecodeError:
            return {}

    def ensure_driver(self) -> None:
        if self.driver is not None:
            return
        profile_base = BASE_DIR / "profiles"
        profile_base.mkdir(parents=True, exist_ok=True)
        with suppress(Exception):
            profile_base.chmod(0o700)
        profile_dir = profile_base / f"profile-{os.getpid()}-{uuid4().hex}"
        if profile_dir.exists():
            shutil.rmtree(profile_dir, ignore_errors=True)
        profile_dir.mkdir(parents=True, exist_ok=True)
        self.profile_dir = profile_dir
        self.cleanup_profile_locks(profile_dir)
        self.ensure_certificate_trust(profile_dir)
        options = Options()
        options.add_argument(f"--user-data-dir={profile_dir}")
        options.add_argument("--headless=new")
        options.add_argument("--no-sandbox")
        options.add_argument("--disable-dev-shm-usage")
        options.add_argument("--disable-gpu")
        options.add_argument("--disable-software-rasterizer")
        options.add_argument("--disable-background-networking")
        options.add_argument("--disable-default-apps")
        options.add_argument("--disable-extensions")
        options.add_argument("--remote-allow-origins=*")
        options.set_capability("goog:loggingPrefs", {"browser": "ALL"})
        service = ChromeService(log_path=str(LOG_PATH))
        self.driver = webdriver.Chrome(service=service, options=options)
        self.driver.set_page_load_timeout(60)
        with suppress(Exception):
            self.driver.execute_cdp_cmd("Network.enable", {})
        with suppress(Exception):
            self.driver.execute_cdp_cmd("Log.enable", {})
        self.register_existing_tabs()

    def cleanup_profile_locks(self, profile_dir: Path) -> None:
        for name in ("SingletonLock", "SingletonSocket", "SingletonCookie"):
            path = profile_dir / name
            with suppress(Exception):
                if path.exists():
                    if path.is_dir():
                        shutil.rmtree(path)
                    else:
                        path.unlink()

    def ensure_certificate_trust(self, profile_dir: Path) -> None:
        if not CERTIFICATE_DIR.exists():
            return
        with suppress(subprocess.CalledProcessError, FileNotFoundError):
            self.ensure_nss_db(profile_dir)
            aliases = self.list_nss_certs(profile_dir)
            for cert_path in sorted(CERTIFICATE_DIR.glob("*.crt")):
                alias = cert_path.stem
                if alias in aliases:
                    continue
                self.import_nss_cert(profile_dir, alias, cert_path, "TCu,Cu,Tu")
                aliases.add(alias)

    def ensure_nss_db(self, profile_dir: Path) -> None:
        db_path = profile_dir / "cert9.db"
        if db_path.exists():
            return
        subprocess.run(
            ["certutil", "-d", f"sql:{profile_dir}", "-N", "--empty-password"],
            check=True,
            capture_output=True,
            text=True,
        )

    def list_nss_certs(self, profile_dir: Path) -> set[str]:
        result = subprocess.run(
            ["certutil", "-d", f"sql:{profile_dir}", "-L"],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            return set()
        aliases = set()
        for line in result.stdout.splitlines():
            line = line.strip()
            if not line or line.startswith("Certificate Nickname"):
                continue
            parts = line.split()
            if parts:
                aliases.add(parts[0])
        return aliases

    def import_nss_cert(self, profile_dir: Path, alias: str, cert_path: Path, trust: str) -> None:
        subprocess.run(
            [
                "certutil",
                "-d",
                f"sql:{profile_dir}",
                "-A",
                "-t",
                trust,
                "-n",
                alias,
                "-i",
                str(cert_path),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    def register_existing_tabs(self) -> None:
        self.sync_tabs()
        if self.active_handle is None and self.driver is not None:
            try:
                self.active_handle = self.driver.current_window_handle
            except WebDriverException:
                handles = self.driver.window_handles
                self.active_handle = handles[0] if handles else None

    def sync_tabs(self) -> None:
        if self.driver is None:
            return
        handles = []
        with suppress(WebDriverException):
            handles = self.driver.window_handles
        for handle in handles:
            if handle not in self.handle_to_id:
                self.register_handle(handle)
        stale_handles = [handle for handle in self.handle_to_id if handle not in handles]
        for handle in stale_handles:
            tab_id = self.handle_to_id.pop(handle)
            self.id_to_handle.pop(tab_id, None)
            if self.active_handle == handle:
                self.active_handle = None
        if self.active_handle not in handles:
            self.active_handle = handles[0] if handles else None

    def register_handle(self, handle: str) -> str:
        if handle in self.handle_to_id:
            return self.handle_to_id[handle]
        self.id_sequence += 1
        tab_id = f"tab-{self.id_sequence}"
        self.handle_to_id[handle] = tab_id
        self.id_to_handle[tab_id] = handle
        return tab_id

    def handle_request(self, payload: dict) -> tuple[dict, bool]:
        command = payload.get("command")
        try:
            with self.lock:
                result, running = self.dispatch(command, payload)
        except Exception as exc:
            return {"status": "error", "message": str(exc)}, True
        return {"status": "ok", "result": result}, running

    def dispatch(self, command: str, payload: dict) -> tuple[dict, bool]:
        if command == "ping":
            return {"pid": os.getpid()}, True
        if command == "service-stop":
            return self.stop_service()
        if command == "service-status":
            return self.service_status(), True
        if command == "tabs-open":
            return self.tabs_open(), True
        if command == "tabs-list":
            return self.tabs_list(), True
        if command == "tabs-focus":
            return self.tabs_focus(payload), True
        if command == "tabs-close":
            return self.tabs_close(payload), True
        if command == "nav-go":
            return self.nav_go(payload), True
        if command == "nav-reload":
            return self.nav_reload(payload), True
        if command == "nav-back":
            return self.nav_back(payload), True
        if command == "nav-forward":
            return self.nav_forward(payload), True
        if command == "page-title":
            return self.page_title(payload), True
        if command == "page-url":
            return self.page_url(payload), True
        if command == "console-read":
            return self.console_read(), True
        if command == "console-clear":
            return self.console_clear(), True
        if command == "cache-clear":
            return self.cache_clear(), True
        if command == "storage-clear":
            return self.storage_clear(payload), True
        if command == "network-set":
            return self.network_set(payload), True
        if command == "network-reset":
            return self.network_reset(), True
        if command == "script-run":
            return self.script_run(payload), True
        if command == "screenshot":
            return self.screenshot(payload), True
        raise ValueError("unknown command")

    def stop_service(self) -> tuple[dict, bool]:
        self.shutdown()
        return {"stopped": True}, False

    def service_status(self) -> dict:
        self.sync_tabs()
        tabs = []
        for handle, tab_id in self.handle_to_id.items():
            info = {"id": tab_id, "handle": handle, "active": handle == self.active_handle}
            with suppress(WebDriverException):
                self.driver.switch_to.window(handle)
                info["url"] = self.driver.current_url
                info["title"] = self.driver.title
            tabs.append(info)
        return {"pid": os.getpid(), "network": self.network_profile, "tabs": tabs}

    def tabs_open(self) -> dict:
        self.sync_tabs()
        if self.driver is None:
            raise RuntimeError("driver unavailable")
        self.driver.switch_to.new_window("tab")
        handle = self.driver.current_window_handle
        tab_id = self.register_handle(handle)
        self.active_handle = handle
        return {"tab": tab_id, "handle": handle}

    def tabs_list(self) -> dict:
        self.sync_tabs()
        items = []
        for handle, tab_id in self.handle_to_id.items():
            item = {"id": tab_id, "handle": handle, "active": handle == self.active_handle}
            with suppress(WebDriverException):
                self.driver.switch_to.window(handle)
                item["url"] = self.driver.current_url
                item["title"] = self.driver.title
            items.append(item)
        return {"tabs": items}

    def tabs_focus(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        self.driver.switch_to.window(handle)
        self.active_handle = handle
        tab_id = self.handle_to_id.get(handle)
        return {"tab": tab_id, "handle": handle}

    def tabs_close(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        handles = self.driver.window_handles
        if len(handles) <= 1:
            raise RuntimeError("cannot close the last tab")
        tab_id = self.handle_to_id.get(handle)
        self.driver.switch_to.window(handle)
        self.driver.close()
        time.sleep(0.2)
        self.sync_tabs()
        remaining = self.driver.window_handles
        focus_handle = remaining[0] if remaining else None
        if focus_handle:
            with suppress(WebDriverException):
                self.driver.switch_to.window(focus_handle)
        self.active_handle = focus_handle
        return {"closed": tab_id}

    def nav_go(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        url = payload.get("url")
        if not url:
            raise ValueError("url required")
        self.driver.switch_to.window(handle)
        self.driver.get(url)
        return {"tab": self.handle_to_id.get(handle), "url": self.driver.current_url}

    def nav_reload(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        self.driver.switch_to.window(handle)
        self.driver.refresh()
        return {"tab": self.handle_to_id.get(handle), "url": self.driver.current_url}

    def nav_back(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        self.driver.switch_to.window(handle)
        self.driver.back()
        return {"tab": self.handle_to_id.get(handle), "url": self.driver.current_url}

    def nav_forward(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        self.driver.switch_to.window(handle)
        self.driver.forward()
        return {"tab": self.handle_to_id.get(handle), "url": self.driver.current_url}

    def page_title(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        self.driver.switch_to.window(handle)
        return {"tab": self.handle_to_id.get(handle), "title": self.driver.title}

    def page_url(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        self.driver.switch_to.window(handle)
        return {"tab": self.handle_to_id.get(handle), "url": self.driver.current_url}

    def console_read(self) -> dict:
        if self.driver is None:
            raise RuntimeError("driver unavailable")
        entries = []
        for entry in self.driver.get_log("browser"):
            items = {
                "level": entry.get("level"),
                "message": entry.get("message"),
                "timestamp": entry.get("timestamp"),
            }
            entries.append(items)
        return {"entries": entries}

    def console_clear(self) -> dict:
        self.console_read()
        return {"cleared": True}

    def cache_clear(self) -> dict:
        if self.driver is None:
            raise RuntimeError("driver unavailable")
        with suppress(Exception):
            self.driver.execute_cdp_cmd("Network.clearBrowserCache", {})
        with suppress(Exception):
            self.driver.execute_cdp_cmd("Network.clearBrowserCookies", {})
        return {"cleared": True}

    def storage_clear(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        self.driver.switch_to.window(handle)
        url = self.driver.current_url
        parsed = urlparse(url)
        if not parsed.scheme or not parsed.netloc:
            return {"cleared": False, "reason": "no origin"}
        origin = f"{parsed.scheme}://{parsed.netloc}"
        with suppress(Exception):
            self.driver.execute_cdp_cmd(
                "Storage.clearDataForOrigin",
                {"origin": origin, "storageTypes": "all"},
            )
        return {"cleared": True, "origin": origin}

    def network_set(self, payload: dict) -> dict:
        profile = payload.get("profile")
        if profile not in {"online", "offline", "slow", "fast"}:
            raise ValueError("unknown profile")
        params = {"offline": False, "latency": 0, "downloadThroughput": -1, "uploadThroughput": -1}
        if profile == "offline":
            params = {"offline": True, "latency": 0, "downloadThroughput": 0, "uploadThroughput": 0}
        elif profile == "slow":
            params = {"offline": False, "latency": 600, "downloadThroughput": 50 * 1024, "uploadThroughput": 25 * 1024}
        elif profile == "fast":
            params = {"offline": False, "latency": 20, "downloadThroughput": 3 * 1024 * 1024, "uploadThroughput": 1 * 1024 * 1024}
        with suppress(Exception):
            self.driver.execute_cdp_cmd("Network.emulateNetworkConditions", params)
        self.network_profile = profile
        return {"profile": profile}

    def network_reset(self) -> dict:
        with suppress(Exception):
            self.driver.execute_cdp_cmd(
                "Network.emulateNetworkConditions",
                {"offline": False, "latency": 0, "downloadThroughput": -1, "uploadThroughput": -1},
            )
        self.network_profile = "online"
        return {"profile": "online"}

    def script_run(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        script = payload.get("script")
        if script is None:
            raise ValueError("script required")
        self.driver.switch_to.window(handle)
        result = self.driver.execute_script(script)
        return {"result": result}

    def screenshot(self, payload: dict) -> dict:
        handle = self.resolve_handle(payload.get("tab"))
        target = payload.get("path")
        if not target:
            runtime_file = RUNTIME_DIR / f"screenshot-{int(time.time())}.png"
            target = str(runtime_file)
        self.driver.switch_to.window(handle)
        self.driver.save_screenshot(target)
        return {"path": target}

    def resolve_handle(self, token: str | None) -> str:
        self.sync_tabs()
        if token in (None, "", "active"):
            if self.active_handle is None:
                raise RuntimeError("no active tab")
            return self.active_handle
        if token in self.id_to_handle:
            handle = self.id_to_handle[token]
            if handle not in self.handle_to_id:
                raise RuntimeError("tab unavailable")
            return handle
        if token in self.handle_to_id:
            return token
        raise ValueError("unknown tab reference")

    def shutdown(self) -> None:
        with suppress(Exception):
            if self.driver is not None:
                self.driver.quit()
        self.driver = None
        self.active_handle = None
        self.id_to_handle.clear()
        self.handle_to_id.clear()
        if self.profile_dir is not None:
            with suppress(Exception):
                shutil.rmtree(self.profile_dir)
            self.profile_dir = None
        with suppress(FileNotFoundError):
            PID_PATH.unlink()


def run_service() -> None:
    service = SeleniumService()
    service.start()


if __name__ == "__main__":
    run_service()
