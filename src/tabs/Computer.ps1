# Tab: Computer (computer name, Site Photographer password, date/time, Windows Update)

$tabComputer = New-Page 'Computer' 0xE977

# --- Computer name ---
$grpName = New-Section $tabComputer 'Computer name' 14 98

[void](New-Label $grpName 'Current' 0 27 'Dim')
$nameCurrent = New-Label $grpName $env:COMPUTERNAME 110 26
Set-Mono $nameCurrent
$nameRestart = New-Label $grpName 'RESTART PENDING' 0 28 'BadgeWarn'
$nameRestart.Visible = $false

$nameBox = New-TextBox $grpName 0 50 476 -Mono
$nameBox.MaxLength = 15

$btnName = New-Button $grpName 'Rename Computer' 486 48 -Primary
$btnName.Enabled = $false

[void](New-Label $grpName 'Max 15 letters, digits or hyphens.' 0 77 'Dim')

Set-EnterButton $nameBox $btnName
$nameBox.Add_TextChanged({
    $btnName.Enabled = ($nameBox.Text.Trim().Length -gt 0 -and $nameBox.Text.Trim() -ne $env:COMPUTERNAME)
})

$btnName.Add_Click({
    $newName = $nameBox.Text.Trim()
    if (-not (Test-ComputerName $newName)) {
        Show-Message "'$newName' is not a valid computer name.`nUse 1-15 letters, digits or hyphens; no leading/trailing hyphen, and not only digits." 'Warning'
        return
    }

    Write-Log "Renaming computer '$env:COMPUTERNAME' to '$newName'"
    try {
        Rename-Computer -NewName $newName -Force -ErrorAction Stop
    } catch {
        Show-Message "Could not rename the computer:`n$($_.Exception.Message)" 'Error'
        return
    }

    $nameCurrent.Text = "$env:COMPUTERNAME -> $newName"
    $nameRestart.Left = $nameCurrent.Left + $nameCurrent.PreferredWidth + 8
    $nameRestart.Visible = $true
    $hdrComputer.Text = $nameCurrent.Text
    $nameBox.Clear()
    $restart = [System.Windows.Forms.MessageBox]::Show($form,
        "Computer renamed to '$newName'.`nRestart now to finish?",
        $appTitle, 'YesNo', 'Question')
    if ($restart -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log 'Restarting the computer'
        try { Restart-Computer -Force -ErrorAction Stop }
        catch { Show-Message "Could not restart the computer:`n$($_.Exception.Message)" 'Error' }
    }
})

# --- Site Photographer password ---
$grpPhoto = New-Section $tabComputer 'Site Photographer password' 124 98

function Update-PhotoLabel {
    $current = Get-PhotographerPassword
    if (-not $current) { $current = '<not set>' }
    $photoLabel.Text = $current
}

[void](New-Label $grpPhoto 'Current password' 0 27 'Dim')
$photoLabel = New-Label $grpPhoto '' 110 26
Set-Mono $photoLabel
Update-PhotoLabel

$photoBox = New-TextBox $grpPhoto 0 50 476 -Mono

$btnPhoto = New-Button $grpPhoto 'Set Password' 486 48 -Primary
$btnPhoto.Enabled = $false

[void](New-Label $grpPhoto 'Symbols, spaces and numbers are removed and the password is converted to lower case.' 0 77 'Dim')

Set-EnterButton $photoBox $btnPhoto
$photoBox.Add_TextChanged({ $btnPhoto.Enabled = ($photoBox.Text.Trim().Length -gt 0) })

$btnPhoto.Add_Click({
    $pass = ConvertTo-PhotographerPassword $photoBox.Text
    $photoBox.Text = $pass
    if (-not $pass) {
        Show-Message 'The password must contain at least one letter.' 'Warning'
        return
    }
    try {
        $secure = ConvertTo-SecureString $pass -AsPlainText -Force
        Set-LocalUser -Name 'Site Photographer' -Password $secure -PasswordNeverExpires $true `
            -UserMayChangePassword $false -ErrorAction Stop
        try { Save-PhotographerPassword $pass }
        catch { Write-Log "Could not save the Site Photographer password: $($_.Exception.Message)" 'WARN' }
        Update-PhotoLabel
        Show-Message "Site Photographer password updated to '$pass'." 'Information' $pass
    } catch {
        Show-Message "Site Photographer password NOT updated:`n$($_.Exception.Message)" 'Error'
    }
})

# --- Date, time and time zone ---
$grpTime = New-Section $tabComputer 'Date, time and time zone' 234 78

[void](New-Label $grpTime 'Time zone' 0 29 'Dim')
$tzCombo = New-Object System.Windows.Forms.ComboBox
$tzCombo.DropDownStyle = 'DropDownList'
$tzCombo.DisplayMember = 'DisplayName'
$tzCombo.Location      = New-Object System.Drawing.Point(110, 26)
$tzCombo.Size          = New-Object System.Drawing.Size(366, 24)
foreach ($tz in @(Get-TimeZone -ListAvailable)) { [void]$tzCombo.Items.Add($tz) }
$grpTime.Controls.Add($tzCombo)

$btnSyncTime = New-Button $grpTime 'Sync Time' 486 24

[void](New-Label $grpTime 'Date and time' 0 57 'Dim')
$timeInfo = New-Label $grpTime '' 110 56
Set-Mono $timeInfo

# Shows the current time zone in the dropdown without triggering a change.
$script:tzLoading = $false
function Update-TimeInfo {
    [System.TimeZoneInfo]::ClearCachedData()
    $current = (Get-TimeZone).Id
    $script:tzLoading = $true
    for ($i = 0; $i -lt $tzCombo.Items.Count; $i++) {
        if ($tzCombo.Items[$i].Id -eq $current) { $tzCombo.SelectedIndex = $i; break }
    }
    $script:tzLoading = $false
    $timeInfo.Text = Get-Date -Format 'dd MMM yyyy HH:mm'
}
Update-TimeInfo

# Picking a time zone sets it right away.
$tzCombo.Add_SelectedIndexChanged({
    if ($script:tzLoading -or $null -eq $tzCombo.SelectedItem) { return }
    try {
        Set-TimeZone -Id $tzCombo.SelectedItem.Id -ErrorAction Stop
        Write-Log "Time zone set to $($tzCombo.SelectedItem.Id)"
    } catch {
        Show-Message "Time zone NOT changed:`n$($_.Exception.Message)" 'Error'
    }
    Update-TimeInfo
})

# Syncs the clock with the Windows time server (starts the Windows Time service if needed).
$btnSyncTime.Add_Click({
    Enter-Busy 'Synchronizing the clock...'
    try {
        $svc = Get-Service -Name W32Time -ErrorAction Stop
        if ($svc.StartType -eq 'Disabled') { Set-Service -Name W32Time -StartupType Manual -ErrorAction Stop }
        if ($svc.Status -ne 'Running') { Start-Service -Name W32Time -ErrorAction Stop }
        $code = Invoke-WithProgress 'w32tm.exe' '/resync /force' $null 'Hidden' 'Synchronizing the clock...'
        Exit-Busy
        if ($code -eq 0) { Show-Message 'Clock synchronized with the time server.' 'Information' }
        else { Show-Message "Clock NOT synchronized (w32tm exit code $code). Check the network connection and try again." 'Error' }
    } catch {
        Exit-Busy
        Show-Message "Clock NOT synchronized:`n$($_.Exception.Message)" 'Error'
    }
    Update-TimeInfo
})

# --- Windows Update ---
$grpUpdate = New-Section $tabComputer 'Windows Update' 324 172

$updateInfo = New-Object System.Windows.Forms.Label
$updateInfo.Text     = 'Click Check for Updates to see if this computer needs updates.'
$updateInfo.Location = New-Object System.Drawing.Point(0, 28)
$updateInfo.Size     = New-Object System.Drawing.Size(476, 18)
$updateInfo.AutoEllipsis = $true
$grpUpdate.Controls.Add($updateInfo)

$updateList = New-Object System.Windows.Forms.ListBox
$updateList.Location         = New-Object System.Drawing.Point(0, 52)
$updateList.Size             = New-Object System.Drawing.Size(476, 118)
$updateList.IntegralHeight   = $false
$updateList.HorizontalScrollbar = $true
$updateList.SelectionMode    = 'None'
Set-Mono $updateList
$grpUpdate.Controls.Add($updateList)

$btnUpdate = New-Button $grpUpdate 'Check for Updates' 486 50
$btnInstallUpdates = New-Button $grpUpdate 'Install' 486 86 -Primary
$btnInstallUpdates.Enabled = $false

# Runs in a background runspace so the window stays responsive; searching and installing can take a long time.
# Install searches again because the COM update objects can't be handed between runspaces.
$updateWorker = {
    param($shared, $install)
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $session.ClientApplicationID = 'Canfield Deployment Toolkit'
        $result = $session.CreateUpdateSearcher().Search('IsInstalled=0 and IsHidden=0')
        if ($result.ResultCode -ge 4) { throw "search failed (result code $($result.ResultCode))" }
        $shared.Titles = @(foreach ($u in $result.Updates) { $u.Title })
        if (-not $install) { return }

        # Updates that need someone to click through their own prompt can't be installed silently.
        $todo = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $result.Updates) {
            if ($u.InstallationBehavior.CanRequestUserInput) { $shared.Skipped += $u.Title; continue }
            if (-not $u.EulaAccepted) { $u.AcceptEula() }
            [void]$todo.Add($u)
        }
        if ($todo.Count -eq 0) { throw 'none of the updates can be installed without user input' }

        $shared.Step = 'Downloading'
        $downloader = $session.CreateUpdateDownloader()
        $downloader.Updates = $todo
        [void]$downloader.Download()

        $shared.Step = 'Installing'
        $installer = $session.CreateUpdateInstaller()
        $installer.Updates = $todo
        $res = $installer.Install()
        $shared.Results = @(for ($i = 0; $i -lt $todo.Count; $i++) {
            [pscustomobject]@{ Title = $todo.Item($i).Title; Ok = ($res.GetUpdateResult($i).ResultCode -eq 2) }
        })
        $shared.RebootRequired = $res.RebootRequired
    } catch {
        $shared.Error = $_.Exception.Message
    } finally {
        $shared.Done = $true
    }
}

function Set-UpdateInfo([string]$Text, [string]$State, [string[]]$Lines) {
    Set-StatusLabel $updateInfo $Text $State
    $updateList.Items.Clear()
    foreach ($l in $Lines) { if ($l) { [void]$updateList.Items.Add($l) } }
}

$updateTimer = New-Object System.Windows.Forms.Timer
$updateTimer.Interval = 500

function Start-UpdateWorker([bool]$Install) {
    $btnUpdate.Enabled = $false
    $btnInstallUpdates.Enabled = $false
    $script:updateShared = [hashtable]::Synchronized(@{
        Install = $Install; Done = $false; Step = 'Checking'; Titles = @(); Results = @(); Skipped = @(); RebootRequired = $false; Error = $null })
    $script:updateWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $script:updatePs    = [PowerShell]::Create()
    [void]$script:updatePs.AddScript($updateWorker).AddArgument($script:updateShared).AddArgument($Install)
    [void]$script:updatePs.BeginInvoke()
    $updateTimer.Start()
}

$btnUpdate.Add_Click({
    Set-UpdateInfo 'Checking for updates...' '' @()
    Write-Log 'Checking for Windows updates'
    Start-UpdateWorker $false
})

$btnInstallUpdates.Add_Click({
    Set-UpdateInfo 'Installing updates...' '' @($updateList.Items)
    Write-Log 'Installing Windows updates'
    Start-UpdateWorker $true
})

$updateTimer.Add_Tick({
    $shared = $script:updateShared
    if (-not $shared.Done) {
        $text = if ($shared.Install) { 'Installing updates...' } else { 'Checking for updates...' }
        $step = if ($shared.Install -and $shared.Step -ne 'Checking') { " ($($shared.Step.ToLower()))" } else { '' }
        $updateInfo.Text = '{0} {1:mm\:ss}{2}' -f $text, $script:updateWatch.Elapsed, $step
        return
    }
    $updateTimer.Stop()
    $script:updatePs.Dispose()
    $btnUpdate.Enabled = $true

    if ($shared.Error) {
        $what = if ($shared.Install) { 'install' } else { 'check for' }
        Set-UpdateInfo "Could not $what updates." 'Bad' @("Error: $($shared.Error)")
        Write-Log "Windows Update ($($shared.Step.ToLower())) failed: $($shared.Error)" 'ERROR'
        $btnInstallUpdates.Enabled = ($shared.Titles.Count -gt 0)
        return
    }

    if ($shared.Install) {
        $failed = @($shared.Results | Where-Object { -not $_.Ok })
        foreach ($r in $shared.Results) { Write-Log ("  {0}: {1}" -f $(if ($r.Ok) { 'Installed' } else { 'FAILED' }), $r.Title) }
        foreach ($t in $shared.Skipped) { Write-Log "  Skipped (needs user input): $t" 'WARN' }
        $installed = $shared.Results.Count - $failed.Count
        $text = "$installed of $($shared.Results.Count) updates installed."
        if ($shared.RebootRequired) { $text += ' Restart required.' }
        $result = if ($failed.Count) { 'Bad' } elseif ($shared.RebootRequired) { 'Warn' } else { 'Good' }
        $lines = @($shared.Results | ForEach-Object { "$(if ($_.Ok) { 'Installed' } else { 'Failed' }): $($_.Title)" }) +
            @($shared.Skipped | ForEach-Object { "Skipped (needs user input): $_" })
        Set-UpdateInfo $text $result $lines
        Write-Log "Windows Update: $text"
        $btnInstallUpdates.Enabled = ($failed.Count -gt 0)
        if ($shared.RebootRequired) {
            $restart = [System.Windows.Forms.MessageBox]::Show($form,
                "Updates installed. Restart now to finish?", $appTitle, 'YesNo', 'Question')
            if ($restart -eq [System.Windows.Forms.DialogResult]::Yes) {
                Write-Log 'Restarting the computer'
                try { Restart-Computer -Force -ErrorAction Stop }
                catch { Show-Message "Could not restart the computer:`n$($_.Exception.Message)" 'Error' }
            }
        }
        return
    }

    $count = $shared.Titles.Count
    if ($count -eq 0) {
        Set-UpdateInfo "Up to date (checked $(Get-Date -Format 'HH:mm'))." 'Good' @()
        Write-Log 'Windows Update: up to date'
        return
    }
    $noun = if ($count -eq 1) { 'update' } else { 'updates' }
    Set-UpdateInfo "$count $noun available." 'Warn' $shared.Titles
    Write-Log "Windows Update: $count $noun available"
    foreach ($t in $shared.Titles) { Write-Log "  $t" }
    $btnInstallUpdates.Enabled = $true
})

$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabComputer) { Update-TimeInfo }
})
