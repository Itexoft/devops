#!/usr/bin/env bash
set -euo pipefail

# Convenience CLI for interacting with Model Context Protocol (MCP) servers.
# Supports multiple server definitions and wraps common MCP operations
# (handshake, tool listing, tool invocation, resources, prompts).

SCRIPT_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG_FILE="${SCRIPT_DIR}/mcp_servers.conf"
CONFIG_FILE="${MCP_SERVERS_CONFIG:-$DEFAULT_CONFIG_FILE}"
PYTHON_BIN="${MCP_PYTHON_BIN:-python3}"
DEFAULT_TIMEOUT="15"
DEFAULT_READ_TIMEOUT="300"
TIMEOUT="${MCP_TIMEOUT:-$DEFAULT_TIMEOUT}"
READ_TIMEOUT="${MCP_READ_TIMEOUT:-$DEFAULT_READ_TIMEOUT}"
OUTPUT_FORMAT="pretty"

declare -Ag MCP_SERVER_URL MCP_SERVER_TRANSPORT MCP_SERVER_DESC

err() {
  printf 'mcp-client: %s\n' "$*" >&2
}

usage() {
  cat <<'EOF'
Usage:
  mcp-client.sh [GLOBAL_OPTS] <command> [ARGS...]

Global options:
  --config <path>        Use an alternate mcp_servers.conf (default: ./mcp_servers.conf)
  --python <path>        Python interpreter to use (default: python3 or MCP_PYTHON_BIN)
  --timeout <seconds>    Request timeout (default: 15)
  --read-timeout <sec>   SSE/stream timeout (default: 300)
  --format <mode>        Output mode: pretty | json (default: pretty)
  -h, --help             Show this help message

Commands:
  servers                          List configured MCP servers
  handshake <server>               Perform MCP initialize and display server info
  tools <server>                   List tools exposed by a server
  call <server> <tool> [opts]      Run a tool (use --args JSON or --file path or --stdin)
  resources <server>               List resources
  resource <server> <uri>          Read a specific resource
  resource-templates <server>      List resource templates
  prompts <server>                 List prompts
  prompt <server> <name> [opts]    Fetch a prompt (use --args JSON/--file/--stdin)
  ping <server>                    Send ping request
  set-log-level <server> <level>   Adjust server logging (debug/info/warning/...)

Output defaults to a human-readable JSON dump. Add --format json for raw JSON.
Server names come from ./mcp_servers.conf (or override via --config / MCP_SERVERS_CONFIG).
Docs: see devops/mcp/Agents.md for detailed examples.
EOF
}

trim() {
  local input="$1"
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"
  printf '%s' "$input"
}

ensure_default_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    return
  fi

  if [[ "$CONFIG_FILE" == "$DEFAULT_CONFIG_FILE" ]]; then
    cat >"$CONFIG_FILE" <<'EOF'
# name|transport|url|description (description optional)
dash_docs|streamable-http|http://192.168.0.1:10333/mcp|Kapeli Dash documentation MCP server
EOF
  else
    err "Config file not found: $CONFIG_FILE"
    exit 1
  fi
}

load_servers() {
  ensure_default_config
  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    local line
    line="$(trim "${raw_line%%#*}")"
    [[ -z "$line" ]] && continue
    IFS='|' read -r name transport url desc <<<"$line"
    name="$(trim "${name:-}")"
    transport="$(trim "${transport:-}")"
    url="$(trim "${url:-}")"
    desc="$(trim "${desc:-}")"
    if [[ -z "$name" || -z "$transport" || -z "$url" ]]; then
      err "Invalid entry in $CONFIG_FILE: $raw_line"
      exit 1
    fi
    MCP_SERVER_URL["$name"]="$url"
    MCP_SERVER_TRANSPORT["$name"]="$transport"
    MCP_SERVER_DESC["$name"]="$desc"
  done <"$CONFIG_FILE"

  if [[ "${#MCP_SERVER_URL[@]}" -eq 0 ]]; then
    err "No MCP servers configured (file: $CONFIG_FILE)"
    exit 1
  fi
}

list_servers() {
  printf 'Configured MCP servers (%s):\n' "$CONFIG_FILE"
  local name
  while IFS= read -r name; do
    local url="${MCP_SERVER_URL[$name]}"
    local transport="${MCP_SERVER_TRANSPORT[$name]}"
    local desc="${MCP_SERVER_DESC[$name]}"
    printf '  - %s\n' "$name"
    printf '      transport : %s\n' "$transport"
    printf '      url       : %s\n' "$url"
    if [[ -n "$desc" ]]; then
      printf '      notes     : %s\n' "$desc"
    fi
  done < <(printf '%s\n' "${!MCP_SERVER_URL[@]}" | sort)
}

require_python_deps() {
  if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    err "Python interpreter not found: $PYTHON_BIN"
    exit 1
  fi
  if ! "$PYTHON_BIN" - <<'PY' >/dev/null 2>&1
import anyio  # noqa: F401
import mcp    # noqa: F401
PY
  then
    err "Python packages 'mcp' and 'anyio' are required."
    err "Install via: $PYTHON_BIN -m pip install --user mcp"
    exit 1
  fi
}

serialize_flag_env() {
  export MCP_TIMEOUT_SECONDS="$TIMEOUT"
  export MCP_READ_TIMEOUT_SECONDS="$READ_TIMEOUT"
  export MCP_OUTPUT_FORMAT="$OUTPUT_FORMAT"
}

append_no_proxy_entry() {
  local entry="$1"
  local current="${NO_PROXY:-${no_proxy:-}}"
  if [[ -z "$current" ]]; then
    current="$entry"
  else
    IFS=',' read -r -a parts <<<"$current"
    local part found=0 normalized=()
    for part in "${parts[@]}"; do
      local trimmed="${part## }"
      trimmed="${trimmed%% }"
      if [[ -n "$trimmed" ]]; then
        normalized+=("$trimmed")
        if [[ "$trimmed" == "$entry" ]]; then
          found=1
        fi
      fi
    done
    if [[ $found -eq 0 ]]; then
      normalized+=("$entry")
    fi
    current=$(IFS=','; printf '%s' "${normalized[*]}")
  fi
  export NO_PROXY="$current"
  export no_proxy="$current"
}

ensure_local_no_proxy() {
  if [[ -n "${MCP_ALLOW_PROXY:-}" ]]; then
    return
  fi
  append_no_proxy_entry "127.0.0.1"
  append_no_proxy_entry "localhost"
}

run_mcp_python() {
  local server_name="$1"
  local command="$2"
  shift 2
  local server_url="${MCP_SERVER_URL[$server_name]}"
  local transport="${MCP_SERVER_TRANSPORT[$server_name]}"

  export MCP_SERVER_NAME="$server_name"
  export MCP_URL="$server_url"
  export MCP_TRANSPORT="$transport"
  export MCP_COMMAND="$command"
  serialize_flag_env

  env "$@" "$PYTHON_BIN" - <<'PY'
import json
import os
import sys
from typing import Any

import anyio
from mcp.client import sse, streamable_http
from mcp.client.session import ClientSession


def serialize(obj: Any) -> Any:
    if hasattr(obj, "model_dump"):
        return obj.model_dump(mode="json")
    if isinstance(obj, dict):
        return {k: serialize(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return [serialize(v) for v in obj]
    return obj


async def open_transport(url: str, transport: str, timeout: float, read_timeout: float):
    if transport == "sse":
        return sse.sse_client(url, timeout=timeout, sse_read_timeout=read_timeout)
    if transport in {"streamable-http", "streamable_http"}:
        return streamable_http.streamablehttp_client(url, timeout=timeout, sse_read_timeout=read_timeout)
    raise SystemExit(f"Unsupported transport: {transport}")


async def main():
    command = os.environ["MCP_COMMAND"]
    transport = os.environ["MCP_TRANSPORT"]
    url = os.environ["MCP_URL"]
    timeout = float(os.environ.get("MCP_TIMEOUT_SECONDS", "15"))
    read_timeout = float(os.environ.get("MCP_READ_TIMEOUT_SECONDS", "300"))
    output_mode = os.environ.get("MCP_OUTPUT_FORMAT", "pretty")

    tool_name = os.environ.get("MCP_TOOL_NAME")
    tool_arguments = os.environ.get("MCP_TOOL_ARGS") or "{}"
    resource_uri = os.environ.get("MCP_RESOURCE_URI")
    prompt_name = os.environ.get("MCP_PROMPT_NAME")
    prompt_arguments = os.environ.get("MCP_PROMPT_ARGS") or "{}"
    log_level = os.environ.get("MCP_LOG_LEVEL")

    try:
        tool_args = json.loads(tool_arguments)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON for tool arguments: {exc}") from exc

    try:
        prompt_args = json.loads(prompt_arguments)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON for prompt arguments: {exc}") from exc

    cm = await open_transport(url, transport, timeout, read_timeout)
    async with cm as manager:
        if transport in {"streamable-http", "streamable_http"}:
            read_stream, write_stream, get_session_id = manager
        else:
            read_stream, write_stream = manager
            get_session_id = None

        async with ClientSession(read_stream, write_stream) as client:
            init_result = await client.initialize()

            def emit(payload: Any):
                serialized = serialize(payload)
                text = json.dumps(serialized, indent=None if output_mode == "json" else 2, ensure_ascii=False)
                sys.stdout.write(text + ("\n" if not text.endswith("\n") else ""))

            if command == "handshake":
                body = serialize(init_result)
                if get_session_id is not None:
                    try:
                        session_id = get_session_id()
                    except Exception:  # noqa: BLE001
                        session_id = None
                    body = {"initialize": body, "sessionId": session_id}
                emit(body)
                return

            match command:
                case "tools":
                    emit(await client.list_tools())
                case "call":
                    if not tool_name:
                        raise SystemExit("Tool name is required for call")
                    emit(await client.call_tool(tool_name, tool_args))
                case "resources":
                    emit(await client.list_resources())
                case "resource":
                    if not resource_uri:
                        raise SystemExit("Resource URI is required")
                    emit(await client.read_resource(resource_uri))
                case "resource-templates":
                    emit(await client.list_resource_templates())
                case "prompts":
                    emit(await client.list_prompts())
                case "prompt":
                    if not prompt_name:
                        raise SystemExit("Prompt name is required")
                    emit(await client.get_prompt(prompt_name, prompt_args))
                case "ping":
                    emit(await client.send_ping())
                case "set-log-level":
                    if not log_level:
                        raise SystemExit("Logging level is required")
                    emit(await client.set_logging_level(log_level))
                case _:
                    raise SystemExit(f"Unsupported command: {command}")

asyncio_run = anyio.run
if __name__ == "__main__":
    asyncio_run(main)
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { err "--config expects a file path"; exit 2; }
      CONFIG_FILE="$2"
      shift 2
      ;;
    --python)
      [[ $# -ge 2 ]] || { err "--python expects a path"; exit 2; }
      PYTHON_BIN="$2"
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || { err "--timeout expects a value"; exit 2; }
      TIMEOUT="$2"
      shift 2
      ;;
    --read-timeout)
      [[ $# -ge 2 ]] || { err "--read-timeout expects a value"; exit 2; }
      READ_TIMEOUT="$2"
      shift 2
      ;;
    --format)
      [[ $# -ge 2 ]] || { err "--format expects 'pretty' or 'json'"; exit 2; }
      case "$2" in
        pretty|json) OUTPUT_FORMAT="$2" ;;
        *) err "Unknown format: $2"; exit 2 ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      err "Unknown option: $1"
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

load_servers
require_python_deps

COMMAND="${1:-}"
if [[ -z "$COMMAND" ]]; then
  usage
  printf '\nDocumentation: %s/Agents.md\n' "$SCRIPT_DIR"
  exit 1
fi
shift

case "$COMMAND" in
  servers)
    list_servers
    exit 0
    ;;
  handshake|tools|call|resources|resource|resource-templates|prompts|prompt|ping|set-log-level)
    ;;
  *)
    err "Unknown command: $COMMAND"
    usage
    exit 2
    ;;
esac

if [[ "$COMMAND" == "servers" ]]; then
  list_servers
  exit 0
fi

if [[ $# -lt 1 ]]; then
  err "Command '$COMMAND' requires a server name"
  exit 2
fi

SERVER_NAME="$1"
shift
if [[ -z "${MCP_SERVER_URL[$SERVER_NAME]:-}" ]]; then
  err "Server not configured: $SERVER_NAME"
  err "Use 'mcp-client.sh servers' to list available names."
  exit 1
fi

env_extra=()

case "$COMMAND" in
  handshake|tools|resources|resource-templates|prompts|ping)
    ;;
  call)
    if [[ $# -lt 1 ]]; then
      err "Usage: mcp-client.sh call <server> <tool> [--args JSON|--file PATH|--stdin]"
      exit 2
    fi
    TOOL_NAME="$1"
    shift
    TOOL_ARGS="{}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --args)
          [[ $# -ge 2 ]] || { err "--args requires JSON"; exit 2; }
          TOOL_ARGS="$2"
          shift 2
          ;;
        --file)
          [[ $# -ge 2 ]] || { err "--file requires a path"; exit 2; }
          TOOL_ARGS="$(<"$2")"
          shift 2
          ;;
        --stdin)
          TOOL_ARGS="$(cat)"
          shift
          ;;
        --format|--timeout|--read-timeout)
          err "$1 must be specified before the command."
          exit 2
          ;;
        *)
          err "Unknown option for call: $1"
          exit 2
          ;;
      esac
    done
    env_extra+=(MCP_TOOL_NAME="$TOOL_NAME" MCP_TOOL_ARGS="$TOOL_ARGS")
    ;;
  resource)
    if [[ $# -lt 1 ]]; then
      err "Usage: mcp-client.sh resource <server> <uri>"
      exit 2
    fi
    env_extra+=(MCP_RESOURCE_URI="$1")
    shift
    ;;
  prompt)
    if [[ $# -lt 1 ]]; then
      err "Usage: mcp-client.sh prompt <server> <name> [--args JSON|--file PATH|--stdin]"
      exit 2
    fi
    PROMPT_NAME="$1"
    shift
    PROMPT_ARGS="{}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --args)
          [[ $# -ge 2 ]] || { err "--args requires JSON"; exit 2; }
          PROMPT_ARGS="$2"
          shift 2
          ;;
        --file)
          [[ $# -ge 2 ]] || { err "--file requires a path"; exit 2; }
          PROMPT_ARGS="$(<"$2")"
          shift 2
          ;;
        --stdin)
          PROMPT_ARGS="$(cat)"
          shift
          ;;
        *)
          err "Unknown option for prompt: $1"
          exit 2
          ;;
      esac
    done
    env_extra+=(MCP_PROMPT_NAME="$PROMPT_NAME" MCP_PROMPT_ARGS="$PROMPT_ARGS")
    ;;
  set-log-level)
    if [[ $# -lt 1 ]]; then
      err "Usage: mcp-client.sh set-log-level <server> <level>"
      exit 2
    fi
    env_extra+=(MCP_LOG_LEVEL="$1")
    shift
    ;;
esac

ensure_local_no_proxy
run_mcp_python "$SERVER_NAME" "$COMMAND" "${env_extra[@]}"
