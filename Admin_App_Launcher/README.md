# Admin Application Launcher (PowerShell WinForms)

A simple Windows desktop utility that lets administrators curate and launch multiple tools with elevation, optional launch delays, grouping, and quick filtering.

Version: v2.0 (2025-04-19)

## Contents
- AdminAppLauncher.ps1 — main WinForms GUI
- StartAAL.bat — convenience launcher (hides console, bypasses ExecutionPolicy)
- appconfig.json — persisted application list (read/write)
- AdminAppLauncher.xml — not referenced by the script (likely unused artifact)

## Requirements
- Windows 10/11
- PowerShell 5.0+ (5.1 recommended)
- .NET WinForms available (built into Windows)
- Standard user or Administrator account

## Quick Start
1. Optional: Right-click StartAAL.bat and choose "Run as administrator" to avoid multiple UAC prompts.
2. Or run directly:
   - Right-click AdminAppLauncher.ps1 > Run with PowerShell
   - Or from a PowerShell prompt: `powershell -ExecutionPolicy Bypass -File .\AdminAppLauncher.ps1`
3. Use the UI to add, edit, or remove entries; import/export JSON lists; and start selected apps.

## Core Features
- Add apps via dialog or drag-and-drop `.exe`/`.lnk` onto the grid
- Edit/remove rows via right-click context menu
- Live search box and group filter dropdown
- Delay column and ordered launch (Start Selected runs by ascending Delay)
- Per-row Start button and status feedback (✓ Launched / ✗ Missing / ✗ Failed)
- App icons, alternating row colors, dark-mode aware UI
- 8-hour session countdown with Reset button; auto-closes at expiry
- Import/Export of the configuration (JSON)

## Configuration
- Location: `appconfig.json` (same folder as the script)
- Persisted automatically on remove, import/export, and when closing the app
- JSON schema:
```json
[
  {
    "Nickname": "Friendly name",
    "Group": "Optional group tag",
    "Delay": 0,
    "Path": "C:\\Path\\To\\App.exe"
  }
]
```
- Notes:
  - `.lnk` shortcuts are resolved to their target when possible
  - If a file path is not found, the row shows `✗ Missing`

## Usage Tips
- Run the launcher itself as Administrator to minimize repeated UAC prompts when starting multiple tools
- Use Group and Delay to create ordered launch sets (e.g., open consoles, then MMCs)
- Import/Export lets you maintain multiple app lists for different roles or machines

## Troubleshooting
- Execution policy: StartAAL.bat uses `-ExecutionPolicy Bypass`. If running manually, use a process-scoped bypass or sign the script.
- UAC prompts for each app: Start the launcher as Admin.
- Shortcut resolution fails: The `.lnk` is kept as-is; prefer adding the direct `.exe` path.
- Console apps may not support `WaitForInputIdle`; this is cosmetic (status still updates after launch attempt).
- Dark mode placeholder text: On older .NET builds the search box shows a gray watermark instead of true placeholder text (by design in this script).

## Known Limitations / Ideas
- Edits made directly in cells are only saved on Close (and some actions). Consider adding auto-save on cell edit if you customize the script.
- Column-click sorting for unbound grids is not enabled; the "Start Selected" button sorts by Delay only.
- Config is stored beside the script; you may relocate to `%AppData%` if desired and update the script accordingly.
- Consider code-signing for enterprise environments instead of using ExecutionPolicy Bypass.

## Security Notice
This tool launches arbitrary executables defined in `appconfig.json`. Only include trusted paths and scripts. Running the launcher as Admin elevates all started apps.

## Change Log
- v2.0: Dark-mode awareness, drag-and-drop add, JSON import/export, group filtering, delay-based sequential start, status feedback, in-UI edit/remove, and session timer.
