from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
RUNTIME_DIR = BASE_DIR / "runtime"
PID_PATH = RUNTIME_DIR / "scai.pid"
LOG_PATH = RUNTIME_DIR / "driver.log"
STATE_PATH = RUNTIME_DIR / "state.json"
HOST = "127.0.0.1"
PORT = 48251
