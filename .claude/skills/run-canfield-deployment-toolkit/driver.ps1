<#
    Launches the real toolkit window (Windows PowerShell 5.1, elevated), runs a steps script against it,
    saves PNG screenshots and closes it. Message boxes are captured to PNG and answered automatically.
    Usage (repo root): powershell -NoProfile -ExecutionPolicy Bypass -File .claude\skills\run-canfield-deployment-toolkit\driver.ps1 [-Steps file.ps1] [-OutDir dir] [-DialogAnswer No|Yes]
    Steps scripts can use: Select-Tab, Set-Text, Invoke-Click, Wait-UI, Save-Shot, and every control variable
    the src\ files define ($tabs, $txtRequest, $btnScan, ...).
#>
[CmdletBinding()]
param(
    [string]$Steps = (Join-Path $PSScriptRoot 'steps-default.ps1'),
    [string]$OutDir = (Join-Path (Get-Location) 'screenshots'),
    [ValidateSet('No', 'Yes')][string]$DialogAnswer = 'No'
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$Steps = (Resolve-Path $Steps).Path

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class DrvWin {
    public delegate bool EnumProc(IntPtr h, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumThreadWindows(uint tid, EnumProc cb, IntPtr l);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc cb, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr h, int id);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
    public static string Txt(IntPtr h) { var s = new StringBuilder(2048); GetWindowText(h, s, 2048); return s.ToString(); }
    public static IntPtr FindDialog(uint tid) {
        IntPtr found = IntPtr.Zero;
        EnumThreadWindows(tid, (h, l) => { if (IsWindowVisible(h) && Cls(h) == "#32770") { found = h; return false; } return true; }, IntPtr.Zero);
        return found;
    }
    public static string DialogText(IntPtr dlg) {
        var sb = new StringBuilder();
        EnumChildWindows(dlg, (h, l) => { if (Cls(h) == "Static") { var t = Txt(h); if (t.Length > 0) sb.AppendLine(t); } return true; }, IntPtr.Zero);
        return sb.ToString().Trim();
    }
}
'@

# Same startup as Install-Toolkit.ps1 up to (not including) ShowDialog, written next to it so $scriptDir, src\
# and sponsors.csv resolve exactly as in a normal script run. Its elevation check is kept: run this elevated.
$entry = Get-Content -LiteralPath (Join-Path $root 'Install-Toolkit.ps1') -Raw
$cut = $entry.IndexOf('[void]$form.ShowDialog()')
if ($cut -lt 0) { throw 'ShowDialog line not found in Install-Toolkit.ps1; update driver.ps1.' }
$boot = Join-Path $root 'Install-Toolkit.driver.ps1'
Set-Content -LiteralPath $boot -Value $entry.Substring(0, $cut) -Encoding UTF8

$script:shot = 0
function Wait-UI([int]$Ms = 300) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $Ms) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 }
}
function Save-Shot([string]$Name) {
    Wait-UI 200
    $script:shot++
    $path = Join-Path $OutDir ('{0:D2}-{1}.png' -f $script:shot, $Name)
    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "shot $path"
}
function Select-Tab([string]$Text) {
    $page = $tabs.TabPages | Where-Object { $_.Text -eq $Text }
    if (-not $page) { throw "No tab '$Text'. Tabs: $(($tabs.TabPages | ForEach-Object Text) -join ', ')" }
    $tabs.SelectedTab = $page
    Wait-UI 500
}
function Set-Text($Control, [string]$Value) { $Control.Text = $Value; Wait-UI }
function Invoke-Click($Control) { $Control.PerformClick(); Wait-UI }

# Answers message boxes. Timer ticks still run inside a MessageBox's modal loop, so this fires while one is open.
$script:dialogs = 0
$dlgTimer = New-Object System.Windows.Forms.Timer
$dlgTimer.Interval = 300
$dlgTimer.Add_Tick({
    $h = [DrvWin]::FindDialog([DrvWin]::GetCurrentThreadId())
    if ($h -eq [IntPtr]::Zero) { return }
    $script:dialogs++
    Write-Host ("dialog '{0}': {1}" -f [DrvWin]::Txt($h), ([DrvWin]::DialogText($h) -replace '\r?\n', ' | '))
    $r = New-Object DrvWin+RECT; [void][DrvWin]::GetWindowRect($h, [ref]$r)
    $bmp = New-Object System.Drawing.Bitmap([math]::Max(1, $r.R - $r.L), [math]::Max(1, $r.B - $r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc()
    [void][DrvWin]::PrintWindow($h, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose()
    $bmp.Save((Join-Path $OutDir ('dialog-{0:D2}.png' -f $script:dialogs))); $bmp.Dispose()
    $ids = if ($DialogAnswer -eq 'Yes') { 6, 1, 2 } else { 7, 2, 1 }   # IDYES/IDNO, IDOK, IDCANCEL
    foreach ($id in $ids) {
        $btn = [DrvWin]::GetDlgItem($h, $id)
        if ($btn -ne [IntPtr]::Zero) { [void][DrvWin]::SendMessage($btn, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero); break }   # BM_CLICK
    }
})

$exitCode = 0
try {
    . $boot
    $dlgTimer.Start()
    $form.StartPosition = 'Manual'
    $form.Location = New-Object System.Drawing.Point(0, 0)
    $form.Show()
    Wait-UI 1000
    . $Steps
} catch {
    Write-Host "DRIVER ERROR: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    $exitCode = 1
} finally {
    $dlgTimer.Stop()
    if ($form) { $form.Close(); Wait-UI 500 }
    Remove-Item -LiteralPath $boot -Force -ErrorAction SilentlyContinue
}
Write-Host "screenshots: $OutDir"
exit $exitCode
