# Window frame around the pages: header with the computer name, sidebar navigation, status bar and theme toggle.
# Loaded after the tabs so it can list every page. The sidebar drives $tabs, whose own tab strip is cut off.

$script:SideWidth   = 180
$script:HeaderHeight = 46
$script:StatusHeight = 25
$client = $form.ClientSize
$bodyTop    = $script:HeaderHeight + 1
$bodyHeight = $client.Height - $bodyTop - $script:StatusHeight - 1

function New-Strip($Role, [int]$X, [int]$Y, [int]$Width, [int]$Height) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($X, $Y)
    $p.Size     = New-Object System.Drawing.Size($Width, $Height)
    Set-Role $p $Role
    $form.Controls.Add($p)
    return $p
}

# --- Header ---
$header = New-Strip 'Side' 0 0 $client.Width $script:HeaderHeight
[void](New-Strip 'Line' 0 $script:HeaderHeight $client.Width 1)

$hdrApp = New-Label $header $appTitle 16 13
$hdrApp.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 11)
$hdrSep = New-Label $header '/' ($hdrApp.Left + $hdrApp.PreferredWidth + 4) 14 'Dim'
$hdrSep.Font = $hdrApp.Font
$hdrComputer = New-Label $header $env:COMPUTERNAME ($hdrSep.Left + $hdrSep.PreferredWidth + 4) 16 'AccentText'
$hdrComputer.Font = New-Object System.Drawing.Font('Consolas', 10.5)

# Release builds show the tag (v2.2.1); builds after it add the commit count (v2.2.1+5); untagged builds show dev.
if ($isExe) {
    $v = $null
    [void][version]::TryParse([System.Diagnostics.FileVersionInfo]::GetVersionInfo($procPath).FileVersion, [ref]$v)
    $verText = if (-not $v -or $v -eq [version]'0.0.0.0') { 'dev' }
               elseif ($v.Revision -gt 0) { 'v{0}.{1}.{2}+{3}' -f $v.Major, $v.Minor, $v.Build, $v.Revision }
               else { 'v{0}.{1}.{2}' -f $v.Major, $v.Minor, $v.Build }
    $hdrVer = New-Label $header $verText 0 16 'Dim'
    Set-Mono $hdrVer
    $hdrVer.Left = $client.Width - $hdrVer.PreferredWidth - 16
}

# --- Pages ---
$content = New-Object System.Windows.Forms.Panel
$content.Location = New-Object System.Drawing.Point(($script:SideWidth + 1), $bodyTop)
$content.Size     = New-Object System.Drawing.Size(($client.Width - $script:SideWidth - 1), $bodyHeight)
$form.Controls.Add($content)
$content.Controls.Add($tabs)

# Puts the TabControl's page area exactly over $content; the tab strip and page border fall outside and are clipped.
function Update-PageBounds {
    $tabs.Location = New-Object System.Drawing.Point(0, 0)
    $tabs.Size     = $content.Size
    $d = $tabs.DisplayRectangle
    $tabs.Location = New-Object System.Drawing.Point((-$d.X), (-$d.Y))
    $tabs.Size     = New-Object System.Drawing.Size(($content.Width + $tabs.Width - $d.Width), ($content.Height + $tabs.Height - $d.Height))
}
Update-PageBounds

# --- Sidebar ---
$sidebar = New-Strip 'Side' 0 $bodyTop $script:SideWidth $bodyHeight
[void](New-Strip 'Line' $script:SideWidth $bodyTop 1 $bodyHeight)

# Segoe MDL2 Assets ships with Windows 10 and later; without it the items show text only.
$iconFont = New-Object System.Drawing.Font('Segoe MDL2 Assets', 11)
if ($iconFont.Name -ne 'Segoe MDL2 Assets') { $iconFont = $null }
$navIcons = @{
    'Computer' = 0xE977; 'Remote Access' = 0xE8AF; 'Canfield Capture' = 0xE722; 'Users' = 0xE716
    'Cleanup Tool' = 0xE74D; 'Summary' = 0xE9D9; 'Scripts' = 0xE943
}

$navBar = New-Object System.Windows.Forms.Panel
$navBar.Size = New-Object System.Drawing.Size(3, 24)
Set-Role $navBar 'Accent'
$sidebar.Controls.Add($navBar)

$script:NavButtons = @()
for ($i = 0; $i -lt $tabs.TabPages.Count; $i++) {
    $page = $tabs.TabPages[$i]
    $b = New-Object System.Windows.Forms.Button
    $b.Text      = $page.Text
    $b.Tag       = @{ Page = $page; Icon = $navIcons[$page.Text] }
    $b.Location  = New-Object System.Drawing.Point(0, (10 + $i * 38))
    $b.Size      = New-Object System.Drawing.Size($script:SideWidth, 38)
    $b.TextAlign = 'MiddleLeft'
    $b.Padding   = New-Object System.Windows.Forms.Padding(42, 0, 0, 0)
    $b.TabStop   = $false
    Set-Role $b 'Nav'
    $b.Add_Click({ $tabs.SelectedTab = $this.Tag.Page })
    $b.Add_Paint({
        param($sender, $e)
        if (-not $iconFont -or -not $sender.Tag.Icon) { return }
        $r = New-Object System.Drawing.Rectangle(16, 0, 20, $sender.Height)
        $flags = [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, NoPrefix'
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string][char]$sender.Tag.Icon, $iconFont, $r, $sender.ForeColor, $flags)
    })
    $sidebar.Controls.Add($b)
    $script:NavButtons += $b
}
$navBar.BringToFront()

# Colors the selected item and moves the accent bar to it; also runs after a theme change.
function Update-Nav {
    $t = $script:Theme
    foreach ($b in $script:NavButtons) {
        $on = ($b.Tag.Page -eq $tabs.SelectedTab)
        $b.BackColor = if ($on) { $t.Surface } else { $t.Side }
        $b.ForeColor = if ($on) { $t.Text } else { $t.Dim }
        $b.Font      = if ($on) { $script:BoldFont } else { $script:UiFont }
        $b.FlatAppearance.MouseOverBackColor = if ($on) { $t.Surface } else { $t.Hover }
        if ($on) { $navBar.Location = New-Object System.Drawing.Point(0, ($b.Top + 7)) }
    }
}
$tabs.Add_SelectedIndexChanged({ Update-Nav })
Add-ThemeHook { Update-Nav }

$chkDark = New-Object System.Windows.Forms.CheckBox
$chkDark.Text     = 'Dark theme'
$chkDark.Location = New-Object System.Drawing.Point(18, ($bodyHeight - 32))
$chkDark.AutoSize = $true
$chkDark.Checked  = $script:Theme.Dark
$chkDark.TabStop  = $false
Set-Role $chkDark 'Dim'
$sidebar.Controls.Add($chkDark)
$chkDark.Add_CheckedChanged({
    $name = if ($chkDark.Checked) { 'Dark' } else { 'Light' }
    if ($name -ne $script:Theme.Name) { Set-Theme $name }
})

# --- Status bar ---
$statusTop = $client.Height - $script:StatusHeight
[void](New-Strip 'Line' 0 ($statusTop - 1) $client.Width 1)
$statusBar = New-Strip 'Side' 0 $statusTop $client.Width $script:StatusHeight
$statusBarText = New-Label $statusBar 'Ready' 14 5 'Dim'
$statusBarLog = New-Label $statusBar "Log: $script:LogFile" 0 5 'Dim'
$statusBarLog.Left = $client.Width - $statusBarLog.PreferredWidth - 14

# DisplayRectangle is only exact once the TabControl has a handle, so the pages are placed again on Load.
$form.Add_Load({
    Update-PageBounds
    Set-Theme $script:Theme.Name $false
})
