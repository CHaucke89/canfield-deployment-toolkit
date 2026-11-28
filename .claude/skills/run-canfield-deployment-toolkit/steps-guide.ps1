# User-guide screenshots: every page in the dark theme, filled with placeholder data instead of runner details.
# Shots are real screen captures (DrawToBitmap misses the dark title bar), cropped to the visible window frame.

Add-Type -Namespace GuideShot -Name Dwm -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
[DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT rect, int size);
'@

function Save-ScreenShot([string]$Name) {
    $form.TopMost = $true
    $form.Activate()
    Wait-UI 600
    # DWMWA_EXTENDED_FRAME_BOUNDS: the window without its invisible resize border. The 1px edge is trimmed too,
    # since on the runner it holds the border on the left/top and desktop pixels on the right/bottom.
    $r = New-Object GuideShot.Dwm+RECT
    [void][GuideShot.Dwm]::DwmGetWindowAttribute($form.Handle, 9, [ref]$r, 16)
    $r.Left++; $r.Top++; $r.Right--; $r.Bottom--
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    $script:shot++
    $path = Join-Path $OutDir ('{0:D2}-{1}.png' -f $script:shot, $Name)
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size($w, $h)))
    $g.Dispose(); $bmp.Save($path); $bmp.Dispose()
    Write-Host "shot $path"
}

$chkDark.Checked = $true
Wait-UI 500

# Header: placeholder computer name, and the version label a built exe shows.
$hdrComputer.Text = 'SITE-PC-01'
if (-not (Get-Variable hdrVer -ErrorAction SilentlyContinue)) {
    $hdrVer = New-Label $header 'v2.2.1' 0 16 'Dim'
    Set-Mono $hdrVer
    $hdrVer.Left = $form.ClientSize.Width - $hdrVer.PreferredWidth - 16
    Set-ControlTheme $hdrVer
}

# --- Computer ---
Select-Tab 'Computer'
$nameCurrent.Text = 'SITE-PC-01'
$photoLabel.Text = '<not set>'
$tzId = 'Eastern Standard Time'
for ($i = 0; $i -lt $tzCombo.Items.Count; $i++) {
    if ($tzCombo.Items[$i].Id -eq $tzId) { $script:tzLoading = $true; $tzCombo.SelectedIndex = $i; $script:tzLoading = $false }
}
$timeInfo.Text = '27 Nov 2026 09:30'
Set-UpdateInfo '2 updates available' 'Warn' @(
    'Cumulative Update for Windows (KB0000001)',
    'Update for Microsoft Defender Antivirus (KB0000002)')
$btnInstallUpdates.Enabled = $true
Save-ScreenShot 'computer'

# --- Remote Access ---
Select-Tab 'Remote Access'
if ($lmiNote) { $lmiNote.Visible = $false }
$combo.Enabled = $true
$combo.Items.Clear()
[void]$combo.Items.Add([pscustomobject]@{ Sponsor = 'Example Sponsor'; DeployID = '' })
$combo.SelectedIndex = 0
Set-StatusLabel $lmiStatus 'LogMeIn is not installed.' $false
Set-StatusLabel $mdmStatus 'Enrolled in Resolve MDM.' $true
$btnMdm.Enabled = $false
$bitLockerTimer.Enabled = $false
Set-StatusLabel $bitLockerInfo 'Drive C: Encrypting (42%)' 'Warn'
Save-ScreenShot 'remote-access'

# --- Canfield Capture ---
Select-Tab 'Canfield Capture'
$list.Items.Clear()
foreach ($f in @('E:\CC v6.1.0 Example Study', 'E:\CC v6.0.2 Example Study', 'E:\CC v5.9.1')) { [void](Add-InstallerItem $f) }
$list.Items[1].Installed = $true
$list.SelectedIndex = 0
$usbInfo.Text = 'Found installer(s) in 3 folder(s). Select one:'
Set-Text $txtRequest '2DB727C1'
Save-ScreenShot 'canfield-capture'

# --- Users ---
Select-Tab 'Users'
$userList.Items.Clear()
foreach ($u in @(@('adoe', 'Alex Doe'), @('jsmith', 'Dr. Jamie Smith'), @('tlee', 'Taylor Lee'))) {
    [void]$userList.Items.Add([pscustomobject]@{ Name = $u[0]; FullName = $u[1]; Display = ('{0}    ({1})' -f $u[0], $u[1]) })
}
$userList.SelectedIndex = 0
Set-Text $userFirst 'Sam'
Set-Text $userLast 'Rivera'
Save-ScreenShot 'users'

# --- Cleanup Tool ---
Select-Tab 'Cleanup Tool'
$dirtyList.Items.Clear(); $cleanList.Items.Clear()
[void]$dirtyList.Items.Add([pscustomobject]@{ Name = 'Canfield Capture v6.1.0'; Display = 'CC v6.1.0' })
[void]$cleanList.Items.Add([pscustomobject]@{ Name = 'Canfield Capture v6.0.2'; Display = 'CC v6.0.2' })
$dirtyList.SetSelected(0, $true)
$btnClean.Enabled = $true
Save-ScreenShot 'cleanup'

# --- Summary ---
Select-Tab 'Summary'
$rows = @(
    @('Computer name', 'SITE-PC-01', $null), @('Service tag', 'ABC1234', $null), @('Model', 'Example Laptop 14', $null),
    @('Date and time', '27 Nov 2026 09:30', $null), @('Time zone', '(UTC-05:00) Eastern Time (US & Canada)', $null),
    @('Wi-Fi', 'Connected (Example-WiFi)', 'Good'), @('BitLocker', 'Encrypting (42%)', 'Warn'),
    @('LogMeIn', 'Installed', 'Good'), @('Resolve MDM', 'Enrolled', 'Good'),
    @('Canfield Capture', 'CC v6.0.2, CC v6.1.0', 'Good'), @('Site users', '3 in the SSCT group', 'Good'))
$statusView.Items.Clear()
foreach ($r in $rows) {
    $item = New-Object System.Windows.Forms.ListViewItem($r[0])
    [void]$item.SubItems.Add($r[1])
    [void]$item.SubItems.Add([string]$script:BadgeText[[string]$r[2]])
    $item.Tag = $r[2]
    [void]$statusView.Items.Add($item)
}
$protocolView.Items.Clear()
foreach ($p in @(,@('Example Study', 'CC v6.1.0', '101', 'Yes'))) {
    $item = New-Object System.Windows.Forms.ListViewItem($p[0])
    foreach ($s in $p[1..3]) { [void]$item.SubItems.Add($s) }
    [void]$protocolView.Items.Add($item)
}
Set-Text $initialsBox 'AB'
Save-ScreenShot 'summary'

# --- Scripts ---
Select-Tab 'Scripts'
$states = @('On', 'On', 'Off')
for ($i = 0; $i -lt $scriptRows.Count; $i++) {
    $row = $scriptRows[$i]; $state = $states[$i % 3]
    Set-StatusLabel $row.State $state ($state -eq 'On')
    $row.Install.Enabled = $false
    $row.On.Enabled      = ($state -eq 'Off')
    $row.Off.Enabled     = ($state -eq 'On')
}
$scriptsNote.Visible = $false
Save-ScreenShot 'scripts'

$chkDark.Checked = $false
Wait-UI 300
