# Light/dark theme. $script:Theme is the active palette; tabs use its Good/Bad/Warn/Text colors for status text.
# The choice is saved in settings.json under the toolkit's ProgramData folder and applied when the window loads.
# Message boxes and file dialogs are drawn by Windows and keep the system look.

$script:SettingsFile = Join-Path $env:ProgramData 'CanfieldDeploymentToolkit\settings.json'

$script:Themes = @{
    Light = @{
        Name = 'Light'; Dark = $false
        Back = [System.Drawing.SystemColors]::Control; Surface = [System.Drawing.SystemColors]::Window
        Text = [System.Drawing.SystemColors]::ControlText; Button = [System.Drawing.SystemColors]::Control
        Border = [System.Drawing.SystemColors]::ControlDark; Tab = [System.Drawing.SystemColors]::Control
        Good = [System.Drawing.Color]::ForestGreen; Bad = [System.Drawing.Color]::Firebrick
        Warn = [System.Drawing.Color]::DarkGoldenrod; Link = [System.Drawing.Color]::Blue
    }
    Dark = @{
        Name = 'Dark'; Dark = $true
        Back = [System.Drawing.Color]::FromArgb(32, 32, 32); Surface = [System.Drawing.Color]::FromArgb(45, 45, 45)
        Text = [System.Drawing.Color]::FromArgb(230, 230, 230); Button = [System.Drawing.Color]::FromArgb(55, 55, 55)
        Border = [System.Drawing.Color]::FromArgb(95, 95, 95); Tab = [System.Drawing.Color]::FromArgb(50, 50, 50)
        Good = [System.Drawing.Color]::FromArgb(110, 205, 110); Bad = [System.Drawing.Color]::FromArgb(245, 120, 110)
        Warn = [System.Drawing.Color]::FromArgb(235, 195, 85); Link = [System.Drawing.Color]::FromArgb(120, 180, 255)
    }
}

function Get-ThemeSetting {
    try {
        if (Test-Path -LiteralPath $script:SettingsFile) {
            $saved = (Get-Content -LiteralPath $script:SettingsFile -Raw | ConvertFrom-Json).Theme
            if ($script:Themes.ContainsKey([string]$saved)) { return [string]$saved }
        }
    } catch { Write-Log "Could not read $($script:SettingsFile): $($_.Exception.Message)" 'WARN' }
    return 'Light'
}

function Save-ThemeSetting([string]$Name) {
    try {
        $dir = Split-Path -Parent $script:SettingsFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -LiteralPath $script:SettingsFile -Value (@{ Theme = $Name } | ConvertTo-Json) -Encoding UTF8
    } catch { Write-Log "Could not save $($script:SettingsFile): $($_.Exception.Message)" 'WARN' }
}

$script:Theme = $script:Themes[(Get-ThemeSetting)]

# Scriptblocks run after every theme change, for anything the generic pass can't know (such as legend text).
$script:ThemeHooks = New-Object System.Collections.Generic.List[scriptblock]
function Add-ThemeHook([scriptblock]$Hook) { $script:ThemeHooks.Add($Hook) }

# Dark scroll bars and title bar (Windows 10 1809+). Compiled on first use; older Windows just keeps the light ones.
function Set-NativeTheme($Control, [bool]$Dark, [bool]$TitleBar = $false) {
    try {
        if (-not ('CdtThemeNative' -as [type])) {
            Add-Type -Namespace '' -Name CdtThemeNative -MemberDefinition @'
[DllImport("uxtheme.dll", CharSet = CharSet.Unicode)] public static extern int SetWindowTheme(IntPtr h, string app, string idList);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int attr, ref int value, int size);
'@
        }
        if ($TitleBar) {
            $on = [int]$Dark
            # 20 is DWMWA_USE_IMMERSIVE_DARK_MODE; builds before 20H1 used 19.
            if ([CdtThemeNative]::DwmSetWindowAttribute($Control.Handle, 20, [ref]$on, 4) -ne 0) {
                [void][CdtThemeNative]::DwmSetWindowAttribute($Control.Handle, 19, [ref]$on, 4)
            }
        } else {
            $name = if ($Dark) { 'DarkMode_Explorer' } else { 'Explorer' }
            [void][CdtThemeNative]::SetWindowTheme($Control.Handle, $name, $null)
        }
    } catch { }
}

# Returns the new palette's color for a status color from the old palette, or $null when it isn't one.
function Convert-AccentColor($Color, $Old) {
    foreach ($key in 'Good', 'Bad', 'Warn') {
        if ($Color.ToArgb() -eq $Old[$key].ToArgb()) { return $script:Theme[$key] }
    }
    return $null
}

$script:ThemedListViews = New-Object 'System.Collections.Generic.HashSet[object]'

# ListViews draw their own column headers in dark mode (Windows draws them light whatever the BackColor).
function Initialize-ListViewTheme($ListView) {
    if (-not $script:ThemedListViews.Add($ListView)) { return }
    $ListView.Add_DrawColumnHeader({
        param($sender, $e)
        $t = $script:Theme
        $back = New-Object System.Drawing.SolidBrush($t.Tab)
        $line = New-Object System.Drawing.Pen($t.Border)
        $e.Graphics.FillRectangle($back, $e.Bounds)
        $e.Graphics.DrawLine($line, $e.Bounds.Right - 1, $e.Bounds.Top, $e.Bounds.Right - 1, $e.Bounds.Bottom)
        $e.Graphics.DrawLine($line, $e.Bounds.Left, $e.Bounds.Bottom - 1, $e.Bounds.Right, $e.Bounds.Bottom - 1)
        $text = New-Object System.Drawing.Rectangle(($e.Bounds.X + 4), $e.Bounds.Y, ($e.Bounds.Width - 6), $e.Bounds.Height)
        $flags = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, EndEllipsis, NoPrefix'
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $sender.Font, $text, $t.Text, $flags)
        $back.Dispose(); $line.Dispose()
    })
    $ListView.Add_DrawItem({ param($sender, $e) $e.DrawDefault = $true })
    $ListView.Add_DrawSubItem({ param($sender, $e) $e.DrawDefault = $true })
}

# Applies the active palette to a control and all its children. $Old is the palette being replaced.
function Set-ControlTheme($Control, $Old = $script:Theme) {
    $t = $script:Theme
    $dark = $t.Dark

    $accent = Convert-AccentColor $Control.ForeColor $Old
    if ($accent) { $Control.ForeColor = $accent }
    elseif ($dark) { $Control.ForeColor = $t.Text }
    else { $Control.ResetForeColor() }

    if ($Control -is [System.Windows.Forms.ButtonBase]) {
        if ($dark) {
            $Control.FlatStyle = 'Flat'
            $Control.FlatAppearance.BorderColor = $t.Border
            $Control.FlatAppearance.MouseOverBackColor = $t.Border
            $Control.FlatAppearance.CheckedBackColor = $t.Button
            if ($Control -is [System.Windows.Forms.Button]) { $Control.BackColor = $t.Button } else { $Control.BackColor = $t.Back }
        } else {
            $Control.FlatStyle = 'Standard'
            $Control.ResetBackColor()
            $Control.UseVisualStyleBackColor = $true
        }
    } elseif ($Control -is [System.Windows.Forms.TextBoxBase] -or $Control -is [System.Windows.Forms.ListBox] -or
              $Control -is [System.Windows.Forms.ListView] -or $Control -is [System.Windows.Forms.ComboBox]) {
        if ($dark) { $Control.BackColor = $t.Surface } else { $Control.ResetBackColor() }
        if ($Control -is [System.Windows.Forms.ComboBox]) {
            $Control.FlatStyle = if ($dark) { 'Flat' } else { 'Standard' }
        }
        if ($Control -is [System.Windows.Forms.ListView]) {
            Initialize-ListViewTheme $Control
            $Control.OwnerDraw = $dark
            foreach ($item in $Control.Items) {
                $c = Convert-AccentColor $item.ForeColor $Old
                if ($c) { $item.ForeColor = $c } else { $item.ForeColor = $Control.ForeColor }
            }
        }
        if ($Control -isnot [System.Windows.Forms.ComboBox]) { Set-NativeTheme $Control $dark }
    } elseif ($Control -is [System.Windows.Forms.TabPage]) {
        if ($dark) { $Control.BackColor = $t.Back } else { $Control.ResetBackColor(); $Control.UseVisualStyleBackColor = $true }
    } elseif ($Control -is [System.Windows.Forms.TabControl]) {
        $Control.DrawMode = if ($dark) { 'OwnerDrawFixed' } else { 'Normal' }
    } elseif ($Control -is [System.Windows.Forms.Form]) {
        if ($dark) { $Control.BackColor = $t.Back } else { $Control.ResetBackColor() }
        Set-NativeTheme $Control $dark $true
    } else {
        # Labels, group boxes, panels: transparent-ish controls follow their parent.
        $Control.ResetBackColor()
    }

    if ($Control -is [System.Windows.Forms.LinkLabel]) {
        $Control.LinkColor = $t.Link
        $Control.ActiveLinkColor = $t.Link
        $Control.VisitedLinkColor = $t.Link
    }

    foreach ($child in $Control.Controls) { Set-ControlTheme $child $Old }
}

# Switches the whole toolkit (main window and progress window) to the named theme and saves the choice.
function Set-Theme([string]$Name, [bool]$Save = $true) {
    $old = $script:Theme
    $script:Theme = $script:Themes[$Name]
    $form.SuspendLayout()
    try {
        Set-ControlTheme $form $old
        Set-ControlTheme $status $old
        foreach ($hook in $script:ThemeHooks) { & $hook }
    } finally {
        $form.ResumeLayout()
        $form.Refresh()
    }
    if ($Save) {
        Save-ThemeSetting $Name
        Write-Log "Theme set to $Name"
    }
}

# Tab headers in dark mode (the TabControl is owner-drawn only while dark).
$tabs.Add_DrawItem({
    param($sender, $e)
    $t = $script:Theme
    $page = $sender.TabPages[$e.Index]
    $selected = ($e.Index -eq $sender.SelectedIndex)
    $color = if ($selected) { $t.Back } else { $t.Tab }
    $brush = New-Object System.Drawing.SolidBrush($color)
    $e.Graphics.FillRectangle($brush, $e.Bounds)
    $brush.Dispose()
    $flags = [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, NoPrefix'
    [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $page.Text, $sender.Font, $e.Bounds, $t.Text, $flags)
})

# --- Toggle (bottom left of the main window, next to Close) ---
$chkDark = New-Object System.Windows.Forms.CheckBox
$chkDark.Text     = 'Dark theme'
$chkDark.Location = New-Object System.Drawing.Point(12, 474)
$chkDark.AutoSize = $true
$chkDark.Checked  = $script:Theme.Dark
$form.Controls.Add($chkDark)
$chkDark.Add_CheckedChanged({
    $name = if ($chkDark.Checked) { 'Dark' } else { 'Light' }
    if ($name -ne $script:Theme.Name) { Set-Theme $name }
})

# Applied on Load so every tab's controls exist; nothing to do for the default light theme.
$form.Add_Load({ if ($script:Theme.Dark) { Set-Theme 'Dark' $false } })
