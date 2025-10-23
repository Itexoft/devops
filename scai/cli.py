import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import time

from .config import BASE_DIR, HOST, PID_PATH, PORT, RUNTIME_DIR


ALIAS_MAP = {
    "opentab": ["tab", "open"],
    "closetab": ["tab", "close"],
    "usetab": ["tab", "focus"],
    "listtabs": ["tab", "list"],
    "tabinfo": ["tab", "info"],
    "navgo": ["nav", "go"],
    "navreload": ["nav", "reload"],
    "navback": ["nav", "back"],
    "navforward": ["nav", "forward"],
    "console": ["logs", "read"],
    "clearconsole": ["logs", "clear"],
    "clearcache": ["cache", "clear"],
    "clearnetwork": ["network", "reset"],
    "offline": ["network", "set", "offline"],
    "online": ["network", "set", "online"],
}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="scai")
    sub = parser.add_subparsers(dest="group", required=True)

    svc = sub.add_parser("service")
    svc_sub = svc.add_subparsers(dest="action", required=True)
    svc_sub.add_parser("start")
    svc_sub.add_parser("stop")
    svc_sub.add_parser("status")

    tab = sub.add_parser("tab")
    tab_sub = tab.add_subparsers(dest="action", required=True)
    tab_sub.add_parser("open")
    tab_sub.add_parser("list")
    focus = tab_sub.add_parser("focus")
    focus.add_argument("tab")
    close = tab_sub.add_parser("close")
    close.add_argument("tab")
    info = tab_sub.add_parser("info")
    info.add_argument("tab", nargs="?")

    nav = sub.add_parser("nav")
    nav_sub = nav.add_subparsers(dest="action", required=True)
    go = nav_sub.add_parser("go")
    go.add_argument("url")
    go.add_argument("--tab")
    reload_cmd = nav_sub.add_parser("reload")
    reload_cmd.add_argument("--tab")
    back_cmd = nav_sub.add_parser("back")
    back_cmd.add_argument("--tab")
    forward_cmd = nav_sub.add_parser("forward")
    forward_cmd.add_argument("--tab")

    page = sub.add_parser("page")
    page_sub = page.add_subparsers(dest="action", required=True)
    title_cmd = page_sub.add_parser("title")
    title_cmd.add_argument("--tab")
    url_cmd = page_sub.add_parser("url")
    url_cmd.add_argument("--tab")

    logs = sub.add_parser("logs")
    logs_sub = logs.add_subparsers(dest="action", required=True)
    logs_sub.add_parser("read")
    logs_sub.add_parser("clear")

    cache = sub.add_parser("cache")
    cache_sub = cache.add_subparsers(dest="action", required=True)
    cache_sub.add_parser("clear")

    storage = sub.add_parser("storage")
    storage_sub = storage.add_subparsers(dest="action", required=True)
    storage_clear = storage_sub.add_parser("clear")
    storage_clear.add_argument("--tab")

    network = sub.add_parser("network")
    net_sub = network.add_subparsers(dest="action", required=True)
    net_set = net_sub.add_parser("set")
    net_set.add_argument("profile")
    net_sub.add_parser("reset")

    script = sub.add_parser("script")
    script_sub = script.add_subparsers(dest="action", required=True)
    script_run = script_sub.add_parser("run")
    script_run.add_argument("code")
    script_run.add_argument("--tab")

    shot = sub.add_parser("snapshot")
    shot_sub = shot.add_subparsers(dest="action", required=True)
    shot_save = shot_sub.add_parser("save")
    shot_save.add_argument("--tab")
    shot_save.add_argument("--path")

    return parser


def apply_aliases(argv: list[str]) -> list[str]:
    if len(argv) < 2:
        return argv
    head = argv[1]
    if head in ALIAS_MAP:
        return [argv[0], *ALIAS_MAP[head], *argv[2:]]
    return argv


def is_service_ready() -> bool:
    try:
        send_command({"command": "ping"}, auto_start=False)
        return True
    except Exception:
        return False


def start_service() -> None:
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    log_path = RUNTIME_DIR / "service.log"
    cmd = [sys.executable, "-m", "scai.service"]
    env = dict(os.environ)
    if env.get("PYTHONPATH"):
        env["PYTHONPATH"] = f"{BASE_DIR.parent}:{env['PYTHONPATH']}"
    else:
        env["PYTHONPATH"] = str(BASE_DIR.parent)
    with log_path.open("ab") as log_file:
        subprocess.Popen(
            cmd,
            stdout=log_file,
            stderr=log_file,
            cwd=str(BASE_DIR.parent),
            env=env,
        )


def wait_for_service(timeout: float = 15.0) -> None:
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            send_command({"command": "ping"}, auto_start=False)
            return
        except Exception:
            time.sleep(0.2)
            continue
        time.sleep(0.2)
    raise RuntimeError("service did not start")


def ensure_service() -> None:
    if is_service_ready():
        return
    start_service()
    wait_for_service()


def wait_for_shutdown(timeout: float = 5.0) -> None:
    start_time = time.time()
    while time.time() - start_time < timeout:
        if not PID_PATH.exists():
            return
        time.sleep(0.2)


def cleanup_runtime() -> None:
    if RUNTIME_DIR.exists():
        shutil.rmtree(RUNTIME_DIR, ignore_errors=True)


def send_command(payload: dict, auto_start: bool = True) -> dict:
    attempts = 2 if auto_start else 1
    last_error = None
    for index in range(attempts):
        try:
            with socket.create_connection((HOST, PORT), timeout=10) as client:
                client.sendall(json.dumps(payload).encode("utf-8"))
                client.shutdown(socket.SHUT_WR)
                data = bytearray()
                while True:
                    chunk = client.recv(4096)
                    if not chunk:
                        break
                    data.extend(chunk)
            if not data:
                raise RuntimeError("empty response")
            response = json.loads(data.decode("utf-8"))
            if response.get("status") != "ok":
                raise RuntimeError(response.get("message") or "command failed")
            return response.get("result") or {}
        except Exception as exc:
            last_error = exc
            if auto_start and index == 0:
                ensure_service()
                continue
            raise last_error
    raise last_error


def handle_service(args: argparse.Namespace) -> None:
    if args.action == "start":
        ensure_service()
        print("service ready")
    elif args.action == "stop":
        try:
            send_command({"command": "service-stop"})
            wait_for_shutdown()
            cleanup_runtime()
            print("service stopped")
        except Exception as exc:
            print(str(exc))
    elif args.action == "status":
        try:
            result = send_command({"command": "service-status"})
            print(json.dumps(result, indent=2))
        except Exception as exc:
            print(str(exc))


def handle_tab(args: argparse.Namespace) -> None:
    if args.action == "open":
        result = send_command({"command": "tabs-open"})
        print(result.get("tab"))
    elif args.action == "list":
        result = send_command({"command": "tabs-list"})
        for entry in result.get("tabs", []):
            prefix = "*" if entry.get("active") else "-"
            print(f"{prefix} {entry.get('id')} {entry.get('title', '')} {entry.get('url', '')}")
    elif args.action == "focus":
        result = send_command({"command": "tabs-focus", "tab": args.tab})
        print(result.get("tab"))
    elif args.action == "close":
        result = send_command({"command": "tabs-close", "tab": args.tab})
        print(result.get("closed"))
    elif args.action == "info":
        result = send_command({"command": "page-url", "tab": args.tab})
        detail = send_command({"command": "page-title", "tab": args.tab})
        print(json.dumps({"url": result.get("url"), "title": detail.get("title")}, indent=2))


def handle_nav(args: argparse.Namespace) -> None:
    if args.action == "go":
        result = send_command({"command": "nav-go", "url": args.url, "tab": args.tab})
        print(result.get("url"))
    elif args.action == "reload":
        result = send_command({"command": "nav-reload", "tab": args.tab})
        print(result.get("url"))
    elif args.action == "back":
        result = send_command({"command": "nav-back", "tab": args.tab})
        print(result.get("url"))
    elif args.action == "forward":
        result = send_command({"command": "nav-forward", "tab": args.tab})
        print(result.get("url"))


def handle_page(args: argparse.Namespace) -> None:
    if args.action == "title":
        result = send_command({"command": "page-title", "tab": args.tab})
        print(result.get("title"))
    elif args.action == "url":
        result = send_command({"command": "page-url", "tab": args.tab})
        print(result.get("url"))


def handle_logs(args: argparse.Namespace) -> None:
    if args.action == "read":
        result = send_command({"command": "console-read"})
        entries = result.get("entries", [])
        for item in entries:
            level = item.get("level")
            ts = item.get("timestamp")
            message = item.get("message")
            print(f"{ts} {level} {message}")
    elif args.action == "clear":
        send_command({"command": "console-clear"})
        print("cleared")


def handle_cache(args: argparse.Namespace) -> None:
    if args.action == "clear":
        send_command({"command": "cache-clear"})
        print("cleared")


def handle_storage(args: argparse.Namespace) -> None:
    if args.action == "clear":
        result = send_command({"command": "storage-clear", "tab": args.tab})
        print(json.dumps(result, indent=2))


def handle_network(args: argparse.Namespace) -> None:
    if args.action == "set":
        result = send_command({"command": "network-set", "profile": args.profile})
        print(result.get("profile"))
    elif args.action == "reset":
        result = send_command({"command": "network-reset"})
        print(result.get("profile"))


def handle_script(args: argparse.Namespace) -> None:
    if args.action == "run":
        result = send_command({"command": "script-run", "script": args.code, "tab": args.tab})
        output = result.get("result")
        if isinstance(output, (dict, list)):
            print(json.dumps(output, indent=2))
        else:
            print(output)


def handle_snapshot(args: argparse.Namespace) -> None:
    if args.action == "save":
        result = send_command({"command": "screenshot", "tab": args.tab, "path": args.path})
        print(result.get("path"))


def main(argv: list[str] | None = None) -> int:
    argv = argv or sys.argv
    argv = apply_aliases(argv)
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    try:
        if args.group == "service":
            handle_service(args)
        elif args.group == "tab":
            handle_tab(args)
        elif args.group == "nav":
            handle_nav(args)
        elif args.group == "page":
            handle_page(args)
        elif args.group == "logs":
            handle_logs(args)
        elif args.group == "cache":
            handle_cache(args)
        elif args.group == "storage":
            handle_storage(args)
        elif args.group == "network":
            handle_network(args)
        elif args.group == "script":
            handle_script(args)
        elif args.group == "snapshot":
            handle_snapshot(args)
        return 0
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
