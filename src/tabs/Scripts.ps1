# Tab: Scripts (Canfield helper scripts installed as scheduled tasks)

$tabScripts = New-Page 'Scripts' 0xE943

$rowsHeight = $script:CanfieldScripts.Count * 38
$grpScripts = New-Section $tabScripts 'Canfield scripts' 14 ($rowsHeight + 52)

$scriptRows = foreach ($i in 0..($script:CanfieldScripts.Count - 1)) {
    $def = $script:CanfieldScripts[$i]
    $y = 26 + $i * 38
    $name = New-Object System.Windows.Forms.Label
    $name.Text     = $def.Name
    $name.Location = New-Object System.Drawing.Point(0, ($y + 6))
    $name.Size     = New-Object System.Drawing.Size(180, 18)
    $grpScripts.Controls.Add($name)

    $state = New-Object System.Windows.Forms.Label
    $state.Location = New-Object System.Drawing.Point(190, ($y + 6))
    $state.Size     = New-Object System.Drawing.Size(130, 18)
    $grpScripts.Controls.Add($state)

    $buttons = foreach ($b in @(@('Install', 330), @('Turn On', 429), @('Turn Off', 528))) {
        $btn = New-Button $grpScripts $b[0] $b[1] $y 90
        $btn.Tag = $def
        $btn
    }
    [pscustomobject]@{ Def = $def; State = $state; Install = $buttons[0]; On = $buttons[1]; Off = $buttons[2] }
}

$scriptsNote = New-Object System.Windows.Forms.Label
Set-StatusLabel $scriptsNote 'Script files not found. Put the Scripts folder next to CDT.exe to install them.' 'Bad'
$scriptsNote.Location  = New-Object System.Drawing.Point(0, ($rowsHeight + 32))
$scriptsNote.Size      = New-Object System.Drawing.Size($script:PageWidth, 18)
$grpScripts.Controls.Add($scriptsNote)

foreach ($row in $scriptRows) {
    $row.Install.Add_Click({
        $def = $this.Tag
        $bat = Find-ScriptsFile $def.Installer
        if (-not $bat) { return }
        Enter-Busy "Installing $($def.Name)..."
        try {
            [void](Invoke-WithProgress $bat $null (Split-Path -Parent $bat) 'Normal' "Installing $($def.Name)...")
            Exit-Busy
        } catch {
            Exit-Busy
            Show-Message "Could not install $($def.Name):`n$($_.Exception.Message)" 'Error'
        }
        Update-ScriptsTab
    })
    $row.On.Add_Click({
        try { Set-CanfieldTaskEnabled $this.Tag.Task $true; Write-Log "Turned on $($this.Tag.Name)" }
        catch { Show-Message "Could not turn on $($this.Tag.Name):`n$($_.Exception.Message)" 'Error' }
        Update-ScriptsTab
    })
    $row.Off.Add_Click({
        try { Set-CanfieldTaskEnabled $this.Tag.Task $false; Write-Log "Turned off $($this.Tag.Name)" }
        catch { Show-Message "Could not turn off $($this.Tag.Name):`n$($_.Exception.Message)" 'Error' }
        Update-ScriptsTab
    })
}

function Update-ScriptsTab {
    $missing = $false
    foreach ($row in $scriptRows) {
        $state = Get-CanfieldTaskState $row.Def.Task
        $hasBat = [bool](Find-ScriptsFile $row.Def.Installer)
        if ($state -eq 'Not installed' -and -not $hasBat) { $missing = $true }
        Set-StatusLabel $row.State $state $(if ($state -eq 'On') { 'Good' } else { 'Bad' })
        $row.Install.Enabled = ($state -eq 'Not installed') -and $hasBat
        $row.On.Enabled      = ($state -eq 'Off')
        $row.Off.Enabled     = ($state -eq 'On')
    }
    $scriptsNote.Visible = $missing
}

$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabScripts) { Update-ScriptsTab }
})
