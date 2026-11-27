---
name: run-canfield-deployment-toolkit
description: Run, launch, test, smoke-test or screenshot the Canfield Deployment Toolkit (Install-Toolkit.ps1 / CDT.exe WinForms window). Use to check a change to src\ or a tab actually works, to see a tab, or to verify the response code, validation or build inlining.
---

# Run the Canfield Deployment Toolkit

A WinForms app in Windows PowerShell 5.1. It cannot open on Linux (or on Chris's Linux laptop), so there are
two layers. Paths are relative to the repo root.

- **`smoke.ps1`** runs anywhere `pwsh` exists (this container included) in about 2 seconds. It parses every
  `.ps1`, flags PowerShell 7-only syntax, checks `src\LoadOrder.ps1`, calls the pure helpers and
  `Get-ResponseCode`, and repeats the build's inlining step and parses the result.
- **`driver.ps1`** opens the real window on Windows, runs a steps script against it, saves PNGs, and answers
  message boxes (saving each as `dialog-NN.png`). Agents run it on GitHub's `windows-latest` through
  `.github/workflows/screenshots.yml`, then pull the PNGs back out of the run log.

## Prerequisites

`pwsh` and `gh` are preinstalled in the cloud container. `gh` must have push access to the repo.

## Smoke test (local, every change)

```bash
pwsh -NoProfile -File .claude/skills/run-canfield-deployment-toolkit/smoke.ps1
```

It prints `PASS`/`FAIL` per check, then `All checks passed` (exit 0) or `N check(s) failed` (exit 1).

## Launch the window and screenshot it (agent path)

The workflow runs on every push that touches `Install-Toolkit.ps1`, `src/**`, this skill or the workflow, on
any branch. It runs the smoke test, then `driver.ps1` with `steps-default.ps1`: one shot per tab, the response
code for `00000001` (must be `1000007B`), an invalid computer name that raises one warning box, then every
tab again in the dark theme (`NN-<tab>-dark.png`, plus one real screen capture of Summary, since
`DrawToBitmap` ignores the dark title bar and scroll bars) and a return to light.

```bash
git push -u origin <branch>
sleep 15
id=$(gh run list --branch <branch> --workflow screenshots.yml --limit 1 --json databaseId -q '.[0].databaseId')
gh run watch $id --exit-status >/dev/null; echo rc=$?
gh run view $id --log | grep -E "shot |dialog|DRIVER|response code" | cut -c1-300
.claude/skills/run-canfield-deployment-toolkit/fetch-screenshots.sh $id screenshots
```

Then open the PNGs with the Read tool and look at them. `fetch-screenshots.sh` writes
`01-computer.png` ... `07-scripts.png`, `08-response-code.png` and `dialog-01.png`. From push to PNGs took
about 45 seconds. `screenshots/` is gitignored.

### Driving other flows

Steps scripts are PowerShell dot-sourced after the window is shown. They can use every control variable
from `src\` (`$tabs`, `$nameBox`, `$btnName`, `$txtRequest`, `$txtResponse`, ...) and these helpers:

| Helper | Does |
|---|---|
| `Select-Tab 'Users'` | Selects a tab by its text, which fires the tab's refresh handlers |
| `Set-Text $ctl 'x'` | Sets text (fires `TextChanged`) |
| `Invoke-Click $btn` | `PerformClick()`; any message box it opens is captured and answered |
| `Save-Shot 'name'` | Saves `NN-name.png` of the whole window |
| `Wait-UI 500` | Pumps the message loop for N ms |
| `$script:dialogs` | Count of message boxes answered so far |

Boxes are answered **No** (else OK/Cancel); pass `-DialogAnswer Yes` to say Yes. A throw in the steps
fails the job with `DRIVER ERROR:` in the log. `steps-guide.ps1` retakes the user guide's Computer and Remote Access shots with placeholder data. To run your own steps on a branch, add them to
`steps-default.ps1` on that branch. Once `screenshots.yml` is on `master`, `workflow_dispatch` also takes a
`steps` input (not yet tried, since dispatch only works for workflows on the default branch).

**Clicks run for real on the runner** (it is admin). Renaming the computer, creating users, Windows Update
and so on would really happen there. That is harmless on a throwaway runner but never run this driver on a
real deployment machine.

## Run (human path)

On Windows: `powershell -ExecutionPolicy Bypass -File .\Install-Toolkit.ps1` (self-elevates), or build
`build\CDT.exe` with `Build-Toolkit-Exe.ps1`. Neither works here.

## Gotchas

- `Add-Type -AssemblyName System.Windows.Forms` on Linux pwsh fails with *Cannot find path
  '.../System.Windows.Forms.dll'*, so no tab file can be dot-sourced locally. `smoke.ps1` pulls
  `Get-ResponseCode` out of `tabs\CanfieldCapture.ps1` through the AST instead of loading the file.
- `pwsh` parses `? :`, `??`, `??=` and `&&`/`||`, but the app runs on Windows PowerShell 5.1, which can't.
  A plain parse check on pwsh misses this; `smoke.ps1` has a separate `ps5.1 syntax` check for it.
- `Install-Toolkit.ps1` ends in a blocking `ShowDialog()`. The driver writes everything before that line to
  `Install-Toolkit.driver.ps1` next to the real entry script (gitignored, deleted afterwards) so
  `$scriptDir`, `src\` and `sponsors.csv` resolve as in a normal run, then uses `$form.Show()`.
- `MessageBox::Show` is static and can't be stubbed. The driver uses a WinForms timer instead: timers still
  tick inside a message box's modal loop, so it finds the `#32770` window, saves it with `PrintWindow`,
  logs its text and sends `BM_CLICK` to the button.
- Screenshots use `$form.DrawToBitmap`, so they show only the toolkit window (no desktop) and work without
  focus. The progress popup (`Enter-Busy`) is a separate form and is not in them.
- `gh run download` fails here with *Forbidden (agent proxy: no rule ... allows this host)*: artifacts come
  from `*.blob.core.windows.net`. The workflow therefore also prints each PNG as base64 between
  `PNG-BEGIN`/`PNG-END` lines, and `fetch-screenshots.sh` rebuilds them from `gh run view --log`.
- Runner screenshots show the runner's state (computer name `runner...`, UTC, nothing installed, no USB),
  not a deployment machine.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FAIL ps5.1 syntax <file> line N: $a ? 1 : 2` | Rewrite with `if`/`else`; 5.1 can't parse it |
| `gh run download`: `Forbidden (agent proxy ...)` | Use `fetch-screenshots.sh <run-id>` |
| `ShowDialog line not found in Install-Toolkit.ps1` | The entry script's last lines changed; update the cut in `driver.ps1` |
