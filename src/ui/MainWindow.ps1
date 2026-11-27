# Main window: form, fonts, layout helpers and the hidden-strip TabControl that holds the pages (see src\Tabs).
# ui\Shell.ps1 adds the header, sidebar and status bar once every tab exists.

$form = New-Object System.Windows.Forms.Form
$form.Text            = $appTitle
$form.ClientSize      = New-Object System.Drawing.Size(840, 600)
$form.StartPosition   = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox     = $false
$form.KeyPreview      = $true
# Use the exe's embedded icon (set by Build-Toolkit-Exe.ps1) for the window and taskbar.
if ($isExe) { $form.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($procPath) }
$form.Add_KeyDown({ param($sender, $e) if ($e.KeyCode -eq 'Escape') { $form.Close() } })

$script:UiFont     = New-Object System.Drawing.Font('Segoe UI', 9)
$script:BoldFont   = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$script:HeaderFont = New-Object System.Drawing.Font('Segoe UI', 7.5, [System.Drawing.FontStyle]::Bold)
$script:MonoFont   = New-Object System.Drawing.Font('Consolas', 9.75)
$form.Font = $script:UiFont

# Page area is 659 x 527; sections span x 20-638.
$script:PageWidth = 618
$script:Dot = [string][char]0x25CF

# The pages live in a TabControl whose tab strip is cut off by Shell.ps1, so tabs keep using $tabs.SelectedTab.
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Appearance = 'FlatButtons'
$tabs.SizeMode   = 'Fixed'
$tabs.ItemSize   = New-Object System.Drawing.Size(0, 1)

# Theme roles for controls that don't take the default colors (see Set-ControlTheme): Primary, Nav, Dim, Header,
# AccentText, Accent, Line, Side, Surface, BadgeGood, BadgeBad, BadgeWarn.
$script:Roles = New-Object 'System.Collections.Generic.Dictionary[object,string]'
function Set-Role($Control, [string]$Role) {
    $script:Roles[$Control] = $Role
    if ($Role -like 'Badge*') { $Control.Font = $script:HeaderFont; $Control.Padding = New-Object System.Windows.Forms.Padding(4, 1, 4, 1) }
}
function Get-Role($Control) {
    $r = $null
    if ($script:Roles.TryGetValue($Control, [ref]$r)) { return $r }
    return ''
}

function New-Label($Parent, [string]$Text, [int]$X, [int]$Y, [string]$Role) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text     = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.AutoSize = $true
    if ($Role) { Set-Role $l $Role }
    $Parent.Controls.Add($l)
    return $l
}

function New-Button($Parent, [string]$Text, [int]$X, [int]$Y, [int]$Width = 132, [switch]$Primary) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text     = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size     = New-Object System.Drawing.Size($Width, 29)
    if ($Primary) { Set-Role $b 'Primary' }
    # Flat buttons don't look disabled on their own, so the theme restyles them when this changes.
    $b.Add_EnabledChanged({ Set-ControlTheme $this })
    $Parent.Controls.Add($b)
    return $b
}

function Set-Mono($Control) { $Control.Font = $script:MonoFont }

# Section on a page: a small uppercase heading with a rule, replacing the old group boxes. Content starts at y 26.
function New-Section($Page, [string]$Text, [int]$Y, [int]$Height, [int]$X = 20, [int]$Width = $script:PageWidth) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($X, $Y)
    $p.Size     = New-Object System.Drawing.Size($Width, $Height)
    $Page.Controls.Add($p)
    $h = New-Label $p $Text.ToUpper() 0 0 'Header'
    $h.Font = $script:HeaderFont
    $line = New-Object System.Windows.Forms.Panel
    $lineX = $h.PreferredWidth + 6
    $line.Location = New-Object System.Drawing.Point($lineX, 8)
    $line.Size     = New-Object System.Drawing.Size(($Width - $lineX), 1)
    Set-Role $line 'Line'
    $p.Controls.Add($line)
    return $p
}

# Pressing Enter in a text box clicks its action button (if enabled), without the error beep.
function Set-EnterButton($TextBox, $Button) {
    $TextBox.Tag = $Button
    $TextBox.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -ne 'Enter') { return }
        $e.SuppressKeyPress = $true
        if ($this.Tag.Enabled) { $this.Tag.PerformClick() }
    })
}

# Green for good, red otherwise, with a status dot.
function Set-StatusLabel($Label, [string]$Text, [bool]$Good) {
    $Label.Text      = "$script:Dot  $Text"
    $Label.ForeColor = if ($Good) { $script:Theme.Good } else { $script:Theme.Bad }
}
