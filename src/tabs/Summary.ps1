# Tab: Summary (machine status, installed protocols, QC report)

$tabSummary = New-Page 'Summary' 0xE9D9

function New-ListView($Parent, [int]$Height, [object[]]$Columns) {
    $lv = New-Object System.Windows.Forms.ListView
    $lv.View          = 'Details'
    $lv.FullRowSelect = $true
    $lv.HeaderStyle   = 'Nonclickable'
    $lv.Location      = New-Object System.Drawing.Point(0, 26)
    $lv.Size          = New-Object System.Drawing.Size($script:PageWidth, $Height)
    foreach ($c in $Columns) { [void]$lv.Columns.Add($c[0], $c[1]) }
    $Parent.Controls.Add($lv)
    return $lv
}

$grpChecks = New-Section $tabSummary 'Checks' 14 290
$statusView = New-ListView $grpChecks 264 @(@('Check', 170), @('Result', 340), @('Status', 90))
Set-Role $statusView 'Status'
$grpProtocols = New-Section $tabSummary 'Protocols' 312 90
$protocolView = New-ListView $grpProtocols 64 @(@('Protocol', 220), @('Version', 120), @('Site ID', 150), @('SSO', 75))

$grpReport = New-Section $tabSummary 'Report' 410 72
[void](New-Label $grpReport 'Technician initials' 0 29 'Dim')
$initialsBox = New-TextBox $grpReport 120 26 80 -Mono

[void](New-Label $grpReport 'Comments' 226 29 'Dim')
$commentsBox = New-Object System.Windows.Forms.TextBox
$commentsBox.Multiline  = $true
$commentsBox.ScrollBars = 'Vertical'
$commentsBox.Location   = New-Object System.Drawing.Point(296, 26)
$commentsBox.Size       = New-Object System.Drawing.Size(322, 44)
$grpReport.Controls.Add($commentsBox)

$btnSummaryRefresh = New-Button $tabSummary 'Refresh' 20 488 110
$btnLogFolder      = New-Button $tabSummary 'Open Log Folder' 138 488 130
$btnReport         = New-Button $tabSummary 'Save Report' 506 488 -Primary
Set-EnterButton $initialsBox $btnReport

$script:BadgeText = @{ Good = 'OK'; Warn = 'CHECK'; Bad = 'ACTION' }

function Update-Summary {
    Enter-Busy 'Checking this computer...'
    try {
        $info     = Get-MachineInfo
        $installs = @(Get-CaptureInstalls)
        $users    = @(try { Get-SiteUsers } catch { })
        $rows = [ordered]@{
            'Computer name'    = $env:COMPUTERNAME
            'Service tag'      = $info.ServiceTag
            'Model'            = $info.Model
            'Date and time'    = Get-Date -Format 'dd MMM yyyy HH:mm'
            'Time zone'        = (Get-TimeZone).DisplayName
            'Wi-Fi'            = Get-WifiStatus
            'BitLocker'        = Get-BitLockerSummary
            'LogMeIn'          = if (Test-LogMeInInstalled) { 'Installed' } else { 'Not installed' }
            'Resolve MDM'      = if (Test-ResolveMdmEnrolled) { 'Enrolled' } else { 'Not enrolled' }
            'Canfield Capture' = if ($installs.Count) { ($installs | ForEach-Object { $_.Display }) -join ', ' } else { 'Not installed' }
            'Site users'       = '{0} in the SSCT group' -f $users.Count
        }
        $bitLocker = $rows['BitLocker']
        $states = @{
            'Wi-Fi'            = if ($rows['Wi-Fi'] -like 'Connected*') { 'Good' } else { 'Warn' }
            'BitLocker'        = if ($bitLocker -eq 'Encrypted') { 'Good' } elseif ($bitLocker -match '^(Encrypt|Decrypt)') { 'Warn' } else { 'Bad' }
            'LogMeIn'          = if ($rows['LogMeIn'] -eq 'Installed') { 'Good' } else { 'Bad' }
            'Resolve MDM'      = if ($rows['Resolve MDM'] -eq 'Enrolled') { 'Good' } else { 'Bad' }
            'Canfield Capture' = if ($installs.Count) { 'Good' } else { 'Bad' }
            'Site users'       = if ($users.Count) { 'Good' } else { 'Warn' }
        }
        $statusView.Items.Clear()
        foreach ($k in $rows.Keys) {
            $item = New-Object System.Windows.Forms.ListViewItem($k)
            [void]$item.SubItems.Add([string]$rows[$k])
            [void]$item.SubItems.Add([string]$script:BadgeText[[string]$states[$k]])
            $item.Tag = $states[$k]
            [void]$statusView.Items.Add($item)
        }

        $protocolView.Items.Clear()
        foreach ($p in (Get-CaptureProtocols -WithSiteId)) {
            $item = New-Object System.Windows.Forms.ListViewItem($p.Protocol)
            [void]$item.SubItems.Add($p.Version)
            [void]$item.SubItems.Add($(if ($p.SiteID) { $p.SiteID } else { 'Not set' }))
            [void]$item.SubItems.Add($(if ($p.SSO) { 'Yes' } else { 'No' }))
            [void]$protocolView.Items.Add($item)
        }
    } finally {
        Exit-Busy
    }
}

# Text version of everything on this tab.
function Get-SummaryText {
    $lines = @("QC report - $env:COMPUTERNAME", '')
    foreach ($item in $statusView.Items) { $lines += '{0}: {1}' -f $item.Text, $item.SubItems[1].Text }
    $lines += '', 'Protocols:'
    if ($protocolView.Items.Count -eq 0) { $lines += '  None installed' }
    foreach ($item in $protocolView.Items) {
        $lines += '  {0} ({1}) - Site ID: {2}, SSO: {3}' -f $item.Text, $item.SubItems[1].Text, $item.SubItems[2].Text, $item.SubItems[3].Text
    }
    $lines += '', "Technician: $($initialsBox.Text.Trim())", "Comments: $($commentsBox.Text.Trim())"
    return ($lines -join "`r`n")
}

$btnSummaryRefresh.Add_Click({ Update-Summary })
# Opens the toolkit's log folder (CDT.log, plus CDT.1.log once the log has rolled over) in Explorer.
$btnLogFolder.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $script:LogDir)) { New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null }
        Start-Process -FilePath explorer.exe -ArgumentList ('"{0}"' -f $script:LogDir)
    } catch {
        Show-Message "Could not open the log folder:`n$script:LogDir`n$($_.Exception.Message)" 'Error'
    }
})
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabSummary) { Update-Summary }
})

# Saves a JPG picture of the window, plus a .txt and a copy of the toolkit log with the same name.
$btnReport.Add_Click({
    if (-not $initialsBox.Text.Trim()) {
        Show-Message 'Enter your initials before saving the report.' 'Warning'
        [void]$initialsBox.Focus()
        return
    }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter   = 'JPEG image (*.jpg)|*.jpg'
    $dlg.FileName = 'QC_{0}_{1}' -f $env:COMPUTERNAME, (Get-Date -Format 'ddMMMyyyyHHmmss')
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($dlg.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }

    try {
        $form.Refresh()
        $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save($dlg.FileName, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $bmp.Dispose()
        $txt = [System.IO.Path]::ChangeExtension($dlg.FileName, '.txt')
        Set-Content -LiteralPath $txt -Value (Get-SummaryText) -Encoding UTF8
        $saved = "$($dlg.FileName)`n$txt"
        if (Test-Path -LiteralPath $script:LogFile) {
            $log = [System.IO.Path]::ChangeExtension($dlg.FileName, '.log')
            Copy-Item -LiteralPath $script:LogFile -Destination $log -Force
            $saved += "`n$log"
        }
        Show-Message "Report saved:`n$saved" 'Information'
    } catch {
        Show-Message "Report NOT saved:`n$($_.Exception.Message)" 'Error'
    }
})
