Agents Handbook
===============

Code Style
----------
- Language-specific conventions live under the `code-style/` directory. Review the matching file (for example `code-style/csharp.md`, `code-style/python.md`, etc.) before writing or editing code to ensure the expected formatting and patterns are followed.

Utility Tooling
---------------
- `scai` (`scai/`): headless Selenium controller with tab management, navigation, logging, and diagnostics. See `scai/Agents.md` for full command reference and testing notes.
- `netai` (`netai/`): .NET assembly inspector for extracting API surface details, inheritance graphs, and JSON dumps. Documentation resides in `netai/Agents.md`. The folder also contains the ready-to-run binaries/scripts.

- Path references that start with `./` inside any Agents guide are relative to the location of that guide. Adjust paths accordingly if you run commands from a different working directory.

Keep these utilities in mind during tasks—when debugging browser flows or inspecting .NET libraries, prefer reusing these tools instead of reimplementing similar functionality.

Repository Etiquette
--------------------
- Do not stage or commit files during a task unless the user explicitly asks for it. Maintain focus on implementing and validating changes; leave version-control actions to the requester.
