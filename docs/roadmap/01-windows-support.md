# 01. Windows support

Status: **planned** (not started) · Analysed 2026-11-16, nothing tested on Windows yet.

## Goal
Make the control actions (`toggle`, `next`, `prev`, `now`, `like`) work in herdr
on Windows, without depending on Git Bash or WSL.

## Why it does not work today
- **Manifest:** `platforms = ["linux", "macos"]`, so herdr does not offer the
  plugin on Windows at all.
- **`bash ytm.sh`:** herdr runs commands as argv, without a shell. On Windows
  `bash` often resolves to WSL's `bash.exe` (System32) rather than Git Bash; the
  script would then run inside Linux and not see the Windows `ytm`. Which bash
  wins depends on the machine's PATH — not something the plugin can rely on.
- **Floating player:** needs tmux, which has no native Windows build (only WSL,
  MSYS2, Cygwin). It also uses `pgrep` / `ps -axo`, missing from Git Bash.

## What already works in our favour
- ytm-player supports Windows: its IPC uses TCP on localhost instead of a Unix
  socket and keeps its config under `%APPDATA%`; the `ytm` CLI is the same.
- `herdr notification show` is part of herdr itself.

## Plan
1. **PowerShell port of the control actions** (`ytm.ps1`): same behaviour and
   toast format as `ytm.sh`; `ConvertFrom-Json` instead of jq, so no extra tools.
   Estimated 100–150 lines, with its own tests (Pester or a plain script) against
   a mocked `ytm`.
2. **No floating player on Windows** for now: `open` stays Linux/macOS-only; the
   README says so. A Windows float needs a different keep-alive mechanism and is
   a separate initiative.
3. **Separate action ids for Windows** (e.g. `toggle-windows`): herdr rejects a
   manifest with duplicate action ids, so platform variants cannot share an id.
   Windows keybindings then use `jloplaya.toggle-windows` etc.
4. **Test on a real Windows machine** with herdr ≥ 0.9.5 and ytm-player set up
   (`ytm setup`, mpv). Ship nothing for Windows that has not run there.

## Open questions
- Is `powershell.exe` (5.1) enough, or should the manifest call `pwsh` (7)?
- Does `herdr notification show` behave identically on Windows?
