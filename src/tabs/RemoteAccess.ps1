# Tab: Remote Access (LogMeIn, Resolve MDM, BitLocker)

$tabRemote = New-Object System.Windows.Forms.TabPage; $tabRemote.Text = 'Remote Access'
[void]$tabs.TabPages.Add($tabRemote)

# --- LogMeIn ---
$grpLmi = New-Section $tabRemote 'LogMeIn' 14 124

$sponsors = @(Get-Sponsors $CsvPath $EmbeddedCsv)

$lmiStatus = New-Object System.Windows.Forms.Label
$lmiStatus.Location = New-Object System.Drawing.Point(0, 27)
$lmiStatus.AutoSize = $true
$grpLmi.Controls.Add($lmiStatus)

$lmiLabel = New-Label $grpLmi 'Select the sponsor to install LogMeIn for:' 0 51 'Dim'

$combo = New-Object System.Windows.Forms.ComboBox
$combo.DropDownStyle = 'DropDownList'
$combo.Location      = New-Object System.Drawing.Point(0, 73)
$combo.Size          = New-Object System.Drawing.Size(476, 24)
$combo.DisplayMember = 'Sponsor'
foreach ($s in $sponsors) { [void]$combo.Items.Add($s) }
$grpLmi.Controls.Add($combo)

$btnLmi = New-Button $grpLmi 'Install LogMeIn' 486 71 -Primary
$btnLmi.Enabled = $false

if ($sponsors.Count -eq 0) {
    $combo.Enabled = $false
    $lmiNote = New-Object System.Windows.Forms.Label
    $lmiNote.Text      = "No sponsors available. CSV not found or empty: $CsvPath"
    $lmiNote.ForeColor = $script:Theme.Bad
    $lmiNote.Location  = New-Object System.Drawing.Point(0, 102)
    $lmiNote.Size      = New-Object System.Drawing.Size($script:PageWidth, 18)
    $lmiNote.AutoEllipsis = $true
    $grpLmi.Controls.Add($lmiNote)
}

$combo.Add_SelectedIndexChanged({ $btnLmi.Enabled = ($null -ne $combo.SelectedItem) })

$btnLmi.Add_Click({
    $choice = $combo.SelectedItem
    if ($null -eq $choice) { return }
    if (Test-LogMeInInstalled) {
        $again = [System.Windows.Forms.MessageBox]::Show($form,
            "LogMeIn is already installed. Install it again for $($choice.Sponsor)?",
            $appTitle, 'YesNo', 'Question')
        if ($again -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    $msi = Join-Path $env:TEMP 'LogMeIn.msi'
    Enter-Busy "Downloading latest LogMeIn installer..."
    try {
        $curlArgs = '-sS --fail -L https://secure.logmein.com/logmein.msi -o "{0}"' -f $msi
        $code = Invoke-WithProgress 'curl.exe' $curlArgs $null 'Hidden' 'Downloading latest LogMeIn installer...'
        if ($code -ne 0) {
            Exit-Busy
            Show-Message "Download failed (curl exit code $code). Check the network connection and try again." 'Error'
            return
        }

        $msiArgs = '/i "{0}" /quiet DEPLOYID={1} INSTALLMETHOD=5 FQDNDESC=1' -f $msi, $choice.DeployID
        $code = Invoke-WithProgress 'msiexec.exe' $msiArgs $null 'Hidden' "Installing LogMeIn for $($choice.Sponsor)..."
        Exit-Busy
        switch ($code) {
            0       { Show-Message "All done! LogMeIn installed for $($choice.Sponsor)." 'Information' }
            { $_ -in 1641, 3010 } { Show-Message "LogMeIn installed for $($choice.Sponsor). A reboot is required to finish." 'Information' }
            default { Show-Message "Installation failed (msiexec exit code $code)." 'Error' }
        }
    } catch {
        Exit-Busy
        Show-Message "Unexpected error:`n$($_.Exception.Message)" 'Error'
    } finally {
        Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
        Update-RemoteTab
    }
})

# --- Resolve MDM ---
$grpMdm = New-Section $tabRemote 'Resolve MDM' 148 62

$mdmStatus = New-Object System.Windows.Forms.Label
$mdmStatus.Location = New-Object System.Drawing.Point(0, 33)
$mdmStatus.Size     = New-Object System.Drawing.Size(476, 18)
$mdmStatus.AutoEllipsis = $true
$grpMdm.Controls.Add($mdmStatus)

$btnMdm = New-Button $grpMdm 'Enroll' 486 27 -Primary

$btnMdm.Add_Click({
    $ppkg = Find-ScriptsFile $script:MdmPackage
    if (-not $ppkg) { return }
    Enter-Busy 'Enrolling in Resolve MDM...'
    try {
        Install-ProvisioningPackage -PackagePath $ppkg -QuietInstall -ErrorAction Stop | Out-Null
        Exit-Busy
        Show-Message 'Resolve MDM enrollment started. The status shows Enrolled once Windows finishes (this can take a minute; click the tab again to refresh).' 'Information'
    } catch {
        Exit-Busy
        Show-Message "Resolve MDM enrollment failed:`n$($_.Exception.Message)" 'Error'
    }
    Update-RemoteTab
})

function Update-RemoteTab {
    if (Test-LogMeInInstalled) { Set-StatusLabel $lmiStatus 'LogMeIn is installed.' $true }
    else                       { Set-StatusLabel $lmiStatus 'LogMeIn is not installed.' $false }

    $enrolled = Test-ResolveMdmEnrolled
    $ppkg = Find-ScriptsFile $script:MdmPackage
    if ($enrolled)  { Set-StatusLabel $mdmStatus 'Enrolled in Resolve MDM.' $true }
    elseif ($ppkg)  { Set-StatusLabel $mdmStatus 'Not enrolled.' $false }
    else            { Set-StatusLabel $mdmStatus 'Not enrolled. CanfieldScientific.ppkg not found in the Scripts folder.' $false }
    $btnMdm.Enabled = (-not $enrolled) -and [bool]$ppkg
}

# --- BitLocker ---
$grpBitLocker = New-Section $tabRemote 'BitLocker encryption status' 224 62

$bitLockerInfo = New-Object System.Windows.Forms.Label
$bitLockerInfo.Location = New-Object System.Drawing.Point(0, 33)
$bitLockerInfo.Size     = New-Object System.Drawing.Size(476, 18)
$grpBitLocker.Controls.Add($bitLockerInfo)

$btnBitLocker = New-Button $grpBitLocker 'Refresh' 486 27

# While the drive is encrypting or decrypting, the percentage refreshes every 10 seconds on this tab.
$bitLockerTimer = New-Object System.Windows.Forms.Timer
$bitLockerTimer.Interval = 10000

function Update-BitLockerInfo {
    $status = Get-BitLockerSummary
    $bitLockerInfo.Text = "$script:Dot  Drive ${env:SystemDrive} $status"
    $bitLockerInfo.ForeColor = if ($status -eq 'Encrypted') { $script:Theme.Good }
        elseif ($status -match '^(Encrypting|Decrypting)') { $script:Theme.Warn }
        else { $script:Theme.Bad }
    $bitLockerTimer.Enabled = ($status -match '^(Encrypting|Decrypting)') -and ($tabs.SelectedTab -eq $tabRemote)
}

$btnBitLocker.Add_Click({ Update-BitLockerInfo })
$bitLockerTimer.Add_Tick({ Update-BitLockerInfo })

$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabRemote) { Update-RemoteTab; Update-BitLockerInfo }
    else { $bitLockerTimer.Enabled = $false }
})
