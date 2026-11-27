# Light/dark theme. $script:Theme is the active palette; tabs use its Good/Bad/Warn/Text colors for status text
# and Set-Role (MainWindow.ps1) for anything else that isn't a default color.
# The choice is saved in settings.json under the toolkit's ProgramData folder and applied when the window loads.
# Message boxes and file dialogs are drawn by Windows and keep the system look.

$script:SettingsFile = Join-Path $env:ProgramData 'CanfieldDeploymentToolkit\settings.json'

# Shorthand for an RGB color in the palettes below.
function C([int]$R, [int]$G, [int]$B) { [System.Drawing.Color]::FromArgb($R, $G, $B) }

$script:Themes = @{
    Light = @{
        Name = 'Light'; Dark = $false
        Back = C 243 244 246; Side = C 232 234 238; Surface = C 255 255 255
        Input = C 255 255 255; Text = C 31 35 41; Dim = C 95 104 120
        Border = C 196 201 209; Line = C 214 217 223; Button = C 255 255 255
        Hover = C 223 227 233; Accent = C 10 123 212; AccentHover = C 8 104 180
        AccentText = C 255 255 255; Good = C 21 128 61; Bad = C 198 40 40
        Warn = C 180 83 9; GoodBack = C 220 252 231; BadBack = C 254 226 226
        WarnBack = C 254 243 199; Link = C 10 108 189
    }
    Dark = @{
        Name = 'Dark'; Dark = $true
        Back = C 27 29 33; Side = C 20 21 24; Surface = C 38 41 47
        Input = C 22 24 27; Text = C 230 232 235; Dim = C 139 147 161
        Border = C 58 63 71; Line = C 51 55 62; Button = C 43 47 53
        Hover = C 53 58 66; Accent = C 59 158 255; AccentHover = C 90 174 255
        AccentText = C 11 18 32; Good = C 74 222 128; Bad = C 248 113 113
        Warn = C 251 191 36; GoodBack = C 23 58 38; BadBack = C 63 29 29
        WarnBack = C 61 47 16; Link = C 120 180 255
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
# ListViews whose rows carry a status ('Good', 'Bad', 'Warn' or $null) in Tag, drawn with a dot and a badge column.
$script:StatusListViews = New-Object 'System.Collections.Generic.HashSet[object]'
$script:BadgeText = @{ Good = 'OK'; Warn = 'CHECK'; Bad = 'ACTION' }

function New-Brush($Color) { New-Object System.Drawing.SolidBrush($Color) }

# ListViews are owner-drawn so the column headers match the palette (Windows always draws them light).
function Initialize-ListViewTheme($ListView) {
    if (-not $script:ThemedListViews.Add($ListView)) { return }
    # A blank image list sets the row height.
    $rows = New-Object System.Windows.Forms.ImageList
    $rows.ImageSize = New-Object System.Drawing.Size(1, 20)
    $ListView.SmallImageList = $rows
    $ListView.OwnerDraw = $true
    # The header past the last column can't be owner-drawn, so the last column fills it.
    $ListView.Columns[$ListView.Columns.Count - 1].Width = -2

    $ListView.Add_DrawColumnHeader({
        param($sender, $e)
        $t = $script:Theme
        $back = New-Brush $t.Side
        $line = New-Object System.Drawing.Pen($t.Line)
        $e.Graphics.FillRectangle($back, $e.Bounds)
        $e.Graphics.DrawLine($line, $e.Bounds.Left, $e.Bounds.Bottom - 1, $e.Bounds.Right, $e.Bounds.Bottom - 1)
        $text = New-Object System.Drawing.Rectangle(($e.Bounds.X + 8), $e.Bounds.Y, ($e.Bounds.Width - 10), $e.Bounds.Height)
        $flags = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, EndEllipsis, NoPrefix'
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text.ToUpper(), $script:HeaderFont, $text, $t.Dim, $flags)
        $back.Dispose(); $line.Dispose()
    })
    $ListView.Add_DrawItem({ param($sender, $e) $e.DrawDefault = $false })
    $ListView.Add_DrawSubItem({
        param($sender, $e)
        $t = $script:Theme
        $g = $e.Graphics
        $b = $e.Bounds
        $back = New-Brush $(if ($e.Item.Selected) { $t.Hover } else { $t.Input })
        $g.FillRectangle($back, $b)
        $back.Dispose()
        $state = [string]$e.Item.Tag
        $statusList = $script:StatusListViews.Contains($sender)
        $flags = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, EndEllipsis, NoPrefix'
        $font = if ($e.ColumnIndex -eq 1 -and $statusList) { $script:MonoFont } else { $sender.Font }
        $textX = $b.X + 8
        if ($statusList -and $e.ColumnIndex -eq 0) {
            $textX = $b.X + 22
            if ($state) {
                $g.SmoothingMode = 'AntiAlias'
                $dot = New-Brush $t[$state]
                $g.FillEllipse($dot, ($b.X + 8), ($b.Y + [int](($b.Height - 8) / 2)), 8, 8)
                $dot.Dispose()
                $g.SmoothingMode = 'Default'
            }
        }
        if ($statusList -and $e.ColumnIndex -eq 2) {
            if ($state) {
                $label = $script:BadgeText[$state]
                $size = [System.Windows.Forms.TextRenderer]::MeasureText($label, $script:HeaderFont)
                $badge = New-Object System.Drawing.Rectangle(($b.X + 8), ($b.Y + [int](($b.Height - 16) / 2)), ($size.Width + 4), 16)
                $fill = New-Brush $t["${state}Back"]
                $g.FillRectangle($fill, $badge)
                $fill.Dispose()
                [System.Windows.Forms.TextRenderer]::DrawText($g, $label, $script:HeaderFont, $badge, $t[$state],
                    [System.Windows.Forms.TextFormatFlags]'HorizontalCenter, VerticalCenter, NoPrefix')
            }
        } else {
            $rect = New-Object System.Drawing.Rectangle($textX, $b.Y, ($b.Right - $textX - 2), $b.Height)
            [System.Windows.Forms.TextRenderer]::DrawText($g, $e.SubItem.Text, $font, $rect, $t.Text, $flags)
        }
        $line = New-Object System.Drawing.Pen($t.Line)
        $g.DrawLine($line, $b.Left, $b.Bottom - 1, $b.Right, $b.Bottom - 1)
        $line.Dispose()
    })
}

# Applies the active palette to a control and all its children. $Old is the palette being replaced.
function Set-ControlTheme($Control, $Old = $script:Theme) {
    $t = $script:Theme
    $dark = $t.Dark
    $role = Get-Role $Control

    if ($Control -is [System.Windows.Forms.Button]) {
        $Control.FlatStyle = 'Flat'
        $Control.FlatAppearance.BorderSize = 1
        if ($role -eq 'Nav') {
            # Shell.ps1 colors the selected item; the rest blend into the sidebar.
            $Control.FlatAppearance.BorderSize = 0
            $Control.BackColor = $t.Side
            $Control.ForeColor = $t.Dim
            $Control.FlatAppearance.MouseOverBackColor = $t.Hover
            $Control.FlatAppearance.MouseDownBackColor = $t.Hover
        } elseif ($role -eq 'Primary' -and $Control.Enabled) {
            $Control.BackColor = $t.Accent
            $Control.ForeColor = $t.AccentText
            $Control.FlatAppearance.BorderColor = $t.Accent
            $Control.FlatAppearance.MouseOverBackColor = $t.AccentHover
            $Control.FlatAppearance.MouseDownBackColor = $t.AccentHover
        } else {
            $Control.BackColor = $t.Button
            $Control.ForeColor = $t.Text
            $Control.FlatAppearance.BorderColor = $t.Border
            $Control.FlatAppearance.MouseOverBackColor = $t.Hover
            $Control.FlatAppearance.MouseDownBackColor = $t.Border
        }
    } elseif ($Control -is [System.Windows.Forms.ButtonBase]) {
        $Control.FlatStyle = 'Flat'
        $Control.FlatAppearance.BorderColor = $t.Border
        $Control.FlatAppearance.CheckedBackColor = $t.Input
        $Control.ResetBackColor()
        $Control.ForeColor = if ($role -eq 'Dim') { $t.Dim } else { $t.Text }
    } elseif ($Control -is [System.Windows.Forms.TextBoxBase] -or $Control -is [System.Windows.Forms.ListBox] -or
              $Control -is [System.Windows.Forms.ListView] -or $Control -is [System.Windows.Forms.ComboBox]) {
        $Control.BackColor = $t.Input
        $Control.ForeColor = $t.Text
        if ($Control -is [System.Windows.Forms.ComboBox]) { $Control.FlatStyle = 'Flat' }
        else {
            $Control.BorderStyle = 'FixedSingle'
            Set-NativeTheme $Control $dark
        }
        if ($Control -is [System.Windows.Forms.ListView]) {
            Initialize-ListViewTheme $Control
            foreach ($item in $Control.Items) { $item.ForeColor = $t.Text }
        }
    } elseif ($Control -is [System.Windows.Forms.TabPage]) {
        $Control.UseVisualStyleBackColor = $false
        $Control.BackColor = $t.Back
    } elseif ($Control -is [System.Windows.Forms.Form]) {
        $Control.BackColor = $t.Back
        $Control.ForeColor = $t.Text
        Set-NativeTheme $Control $dark $true
    } else {
        switch -Wildcard ($role) {
            'Side'    { $Control.BackColor = $t.Side }
            'Surface' { $Control.BackColor = $t.Surface }
            'Line'    { $Control.BackColor = $t.Line }
            'Accent'  { $Control.BackColor = $t.Accent }
            'Badge*'  { $Control.BackColor = $t[$role.Substring(5) + 'Back']; $Control.ForeColor = $t[$role.Substring(5)] }
            default   { $Control.ResetBackColor() }
        }
        if ($role -in 'Dim', 'Header') { $Control.ForeColor = $t.Dim }
        elseif ($role -eq 'AccentText') { $Control.ForeColor = $t.Accent }
        elseif ($role -notlike 'Badge*') {
            $accent = Convert-AccentColor $Control.ForeColor $Old
            if ($accent) { $Control.ForeColor = $accent } else { $Control.ForeColor = $t.Text }
        }
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
