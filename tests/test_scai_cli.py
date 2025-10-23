import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def run_cmd(*parts: str) -> str:
    result = subprocess.run(
        ["./scai/scai.sh", *parts],
        cwd=str(ROOT),
        check=True,
        text=True,
        capture_output=True,
    )
    return result.stdout.strip()


def test_end_to_end() -> None:
    subprocess.run(["./scai/scai.sh", "service", "stop"], cwd=str(ROOT), check=False, capture_output=True)
    tab_id = run_cmd("tab", "open")
    assert tab_id.startswith("tab-")
    url = run_cmd("nav", "go", "https://example.com", "--tab", tab_id)
    assert "example.com" in url
    title = run_cmd("page", "title", "--tab", tab_id)
    assert title == "Example Domain"
    info_raw = run_cmd("tab", "info", tab_id)
    info = json.loads(info_raw)
    assert info["url"].startswith("https://example.com")
    run_cmd("network", "set", "slow")
    run_cmd("network", "reset")
    run_cmd("logs", "read")
    run_cmd("cache", "clear")
    result = run_cmd("snapshot", "save", "--tab", tab_id)
    shot_path = Path(result)
    assert shot_path.exists()
    shot_path.unlink()
    run_cmd("tab", "close", tab_id)
    subprocess.run(["./scai/scai.sh", "service", "stop"], cwd=str(ROOT), check=False, capture_output=True)


if __name__ == "__main__":
    test_end_to_end()
