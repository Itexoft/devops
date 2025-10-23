netai Toolkit
=============

Purpose
-------
- `netai` is a .NET reflection assistant that inspects assemblies, enumerates public and internal APIs, and exports metadata for downstream use.
- The source lives in `netai/src/netai`. Ready-to-run assets sit directly under `netai/`: `netai.dll`, `netai.runtimeconfig.json`, `netai.deps.json`, `netai.sh`, and `netai.exe`.

All commands below assume your working directory is `netai/` (the same location as this document). Adjust paths if you execute them elsewhere.

Running on macOS/Linux
----------------------
- Preferred entry point: `./netai.sh <assembly> <command> [options]`.
- The wrapper sets `DOTNET_ROLL_FORWARD=LatestMajor`, uses the bundled runtimeconfig/deps files, and calls `dotnet exec` with `netai.dll`.
- Manual launch, if needed: `DOTNET_ROLL_FORWARD=LatestMajor dotnet exec --runtimeconfig ./netai.runtimeconfig.json --depsfile ./netai.deps.json ./netai.dll ...`.

Running on Windows
------------------
- Use the framework-dependent host: `netai.exe <assembly> <command> [options]`.
- The executable loads the adjacent `netai.dll`, `netai.runtimeconfig.json`, and `netai.deps.json`; ensure they stay together.

Key Commands
------------
- `summary` — high-level assembly info (name, version, module list, namespaces).
- `types [--namespace <prefix>] [--filter <text>] [--public] [--nonpublic] [--base <type>]` — list types with filtering.
- `type --type <full_name>` — detailed type report (inheritance, interfaces, attributes, nested types).
- `members --type <type> [--kind methods|properties|fields|events|constructors] [--include-nonpublic]` — inspect members by category.
- `method --type <type> --method <name> [--parameters T1,T2] [--include-nonpublic]` — deep dive into specific overloads (signature, attributes, IL size).
- `inheritance --type <type>` — print the inheritance chain.
- `implements --type <base_or_interface> [--include-nonpublic]` — find all derived/implementing types.
- `search --pattern <text> [--include-nonpublic] [--case-sensitive]` — search across types and members.
- `attributes --type <type> [--member <name>] [--include-nonpublic]` — list custom attributes.
- `resources` — display embedded resources with sizes.
- `entrypoint` — show the assembly entry point if present.
- `dump-json [--type <type>] [--with-members] [--include-nonpublic]` — emit JSON for integration workflows.

Quick Checks
------------
- Smoke test the toolkit itself: `./netai.sh ./netai.dll summary`.
- Examine a platform assembly (example): `./netai.sh "$(dirname "$(command -v dotnet)")/../shared/Microsoft.NETCore.App/10.0.0-preview.7.25380.108/System.Private.CoreLib.dll" types --filter String`.

When to Use
-----------
- Use `netai` whenever a task requires reverse engineering an unfamiliar .NET library, mapping internal APIs, or generating machine-readable metadata for automation.
