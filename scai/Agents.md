SCAI Selenium Control
=====================

Bootstrap
---------
0. Commands below assume you run them from the `scai/` directory (same location as this guide). From the repository root, prefix invocations with `scai/` (for example `./scai/scai.sh ...`).
1. Run `./scai.sh tab open` or `./scai.sh service start` to spawn the headless Chrome controller. The first command auto-starts the daemon if it is not running.
2. A fresh runtime lives under `scai/runtime/` with logs, screenshots, and PID metadata.
3. The service binds to `127.0.0.1:48251`; tests and the shell helper rely on that endpoint.

Tab Management
--------------
- `./scai.sh tab open` creates a tab and prints its identifier (`tab-N`).
- `./scai.sh tab list` enumerates every window and marks the active one with `*`.
- `./scai.sh tab focus <tab-id>` switches focus; aliases: `usetab`.
- `./scai.sh tab info <tab-id>` dumps `{"url": "...", "title": "..."}`.
- `./scai.sh tab close <tab-id>` removes a tab; it refuses to close the last remaining tab.
- Aliases: `opentab`, `closetab`, `listtabs`, `tabinfo`.

Navigation
----------
- `./scai.sh nav go <url> [--tab <tab-id>]` loads a page. Default target is the active tab.
- `./scai.sh nav reload|back|forward [--tab <tab-id>]`.
- `./scai.sh page title|url [--tab <tab-id>]` inspects the active document.

Instrumentation
---------------
- `./scai.sh logs read` streams console messages; `clearconsole` empties the buffer.
- `./scai.sh script run "return document.title" --tab <tab-id>` executes JS and prints the return value.
- `./scai.sh snapshot save [--tab <tab-id>] [--path <file>]` writes a PNG; omitting `--path` stores it under `scai/runtime/`.

Health and Storage
------------------
- `./scai.sh cache clear` wipes browser cache and cookies through CDP.
- `./scai.sh storage clear [--tab <tab-id>]` clears all storage scopes for the tab origin.
- `./scai.sh network set online|offline|slow|fast` toggles emulation; `clearnetwork` or `network reset` restores defaults.

Service Lifecycle
-----------------
- `./scai.sh service status` displays PID, network profile, and tab metadata.
- `./scai.sh service stop` shuts down the daemon and releases Chrome/Chromedriver.
- The wrapper surfaces human-readable errors; check `scai/runtime/service.log` for stack traces.

Testing
-------
- Execute `pytest scai/tests/test_scai_cli.py` to validate Selenium wiring end-to-end in headless mode.
- Tests create and clean up temporary assets within `scai/runtime/`.
