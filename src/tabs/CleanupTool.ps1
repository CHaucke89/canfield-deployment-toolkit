# Tab: Cleanup Tool

$tabClean = New-Page 'Cleanup Tool' 0xE74D

$grpDirty = New-Section $tabClean 'Needs cleanup' 14 330 20 300
$dirtyList = New-Object System.Windows.Forms.ListBox
$dirtyList.Location      = New-Object System.Drawing.Point(0, 26)
$dirtyList.Size          = New-Object System.Drawing.Size(300, 304)
$dirtyList.IntegralHeight = $false
$dirtyList.SelectionMode = 'MultiExtended'
$dirtyList.DisplayMember = 'Display'
$grpDirty.Controls.Add($dirtyList)

$grpClean = New-Section $tabClean 'Already clean' 14 330 338 300
$cleanList = New-Object System.Windows.Forms.ListBox
$cleanList.Location      = New-Object System.Drawing.Point(0, 26)
$cleanList.Size          = New-Object System.Drawing.Size(300, 304)
$cleanList.IntegralHeight = $false
$cleanList.DisplayMember = 'Display'
$cleanList.SelectionMode = 'None'
$grpClean.Controls.Add($cleanList)

$cleanNote = New-Object System.Windows.Forms.Label
$cleanNote.Text     = "Clean Selected deletes the selected versions' site data (registered users are kept) and opens Canfield Capture to set the Site ID. Set Site IDs opens every installed version so you can set its Site ID."
$cleanNote.Location = New-Object System.Drawing.Point(20, 356)
$cleanNote.Size     = New-Object System.Drawing.Size($script:PageWidth, 36)
Set-Role $cleanNote 'Dim'
$tabClean.Controls.Add($cleanNote)

$btnRefresh = New-Button $tabClean 'Refresh' 20 482 110
$btnSiteIds = New-Button $tabClean 'Set Site IDs' 138 482 120
$btnClean   = New-Button $tabClean 'Clean Selected' 506 482 -Primary
$btnClean.Enabled = $false

function Update-CleanupLists {
    $dirtyList.Items.Clear()
    $cleanList.Items.Clear()
    foreach ($v in (Get-CaptureVersions)) {
        if ($v.Dirty) { [void]$dirtyList.Items.Add($v) } else { [void]$cleanList.Items.Add($v) }
    }
    # Preselect everything that needs cleaning.
    for ($i = 0; $i -lt $dirtyList.Items.Count; $i++) { $dirtyList.SetSelected($i, $true) }
    $btnClean.Enabled = ($dirtyList.SelectedItems.Count -gt 0)
}

$btnRefresh.Add_Click({ Update-CleanupLists })
$dirtyList.Add_SelectedIndexChanged({ $btnClean.Enabled = ($dirtyList.SelectedItems.Count -gt 0) })
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabClean) { Update-CleanupLists }
})

$btnClean.Add_Click({
    $selected = @($dirtyList.SelectedItems)
    if ($selected.Count -eq 0) { return }

    $names = ($selected | ForEach-Object { $_.Display }) -join "`n"
    $confirm = [System.Windows.Forms.MessageBox]::Show($form,
        "Clean the database for:`n$names`n`nThis deletes site data and cannot be undone.",
        $appTitle, 'YesNo', 'Warning')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    try {
        foreach ($v in $selected) {
            Write-Log "Cleaning database for $($v.Name)"
            Enter-Busy "Cleaning $($v.Display)..."
            Clear-CaptureDatabase $v.Name
            Rename-CaptureLogFiles $v.Name
            Exit-Busy
            Write-Log "Cleaned database for $($v.Name)"

            $exe = Join-Path $script:CaptureProgramRoot "$($v.Name)\Canfield Capture.exe"
            if (-not (Test-Path -LiteralPath $exe)) {
                Show-Message "Cleaned $($v.Display), but Canfield Capture was not found at:`n$exe`nSet the Site ID manually." 'Warning'
                continue
            }
            Show-Message "Site ID MUST be set. Click OK to open $($v.Display)." 'Warning'
            Enter-Busy "Waiting for $($v.Display) to close..."
            [void](Invoke-WithProgress $exe $null (Split-Path -Parent $exe) 'Normal' "Waiting for $($v.Display) to close...")
            Exit-Busy
        }

        try {
            Set-SsctPasswordExpired
            Show-Message 'Cleanup complete.' 'Information'
        } catch {
            Show-Message "Databases cleaned, but SSCT passwords were NOT expired:`n$($_.Exception.Message)" 'Warning'
        }
    } catch {
        Exit-Busy
        Show-Message "Cleanup failed:`n$($_.Exception.Message)" 'Error'
    }
    Update-CleanupLists
})

# Opens every installed version so the Site ID can be set. First copies Registered_Users.sdf to versions
# that have none (never overwriting one), so all versions know the site's users.
$btnSiteIds.Add_Click({
    $installs = @(Get-CaptureInstalls)
    if ($installs.Count -eq 0) {
        Show-Message "No Canfield Capture installation found under:`n$script:CaptureProgramRoot" 'Warning'
        return
    }
    $names = ($installs | ForEach-Object { $_.Display }) -join "`n"
    $confirm = [System.Windows.Forms.MessageBox]::Show($form,
        "Open each version in turn to set its Site ID?`n$names`n`nVersions without registered users get a copy from another version. Existing registered users are never replaced.",
        $appTitle, 'YesNo', 'Question')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    $copied = @()
    try {
        $copied = @(Copy-RegisteredUsers @($installs | ForEach-Object { $_.Name }))
        if ($copied.Count -gt 0) { Write-Log ('Copied Registered_Users.sdf to: ' + ($copied -join ', ')) }
    } catch {
        Show-Message "Could not copy registered users:`n$($_.Exception.Message)" 'Warning'
    }
    foreach ($v in $installs) {
        Show-Message "Set the Site ID in $($v.Display), then close it.`nClick OK to open it." 'Information'
        Enter-Busy "Waiting for $($v.Display) to close..."
        try {
            [void](Invoke-WithProgress $v.Exe $null (Split-Path -Parent $v.Exe) 'Normal' "Waiting for $($v.Display) to close...")
        } catch {
            Exit-Busy
            Show-Message "Could not open $($v.Display):`n$($_.Exception.Message)" 'Error'
            continue
        }
        Exit-Busy
    }
    Update-CleanupLists
    $done = 'Site IDs done.'
    if ($copied.Count -gt 0) {
        $done += "`nRegistered users were copied to: " + (($copied -replace '^Canfield Capture ', 'CC ') -join ', ')
    }
    Show-Message $done 'Information'
})
