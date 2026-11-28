# Tab: Users (SSCT site users and the SharedAdmin account)

$tabUsers = New-Page 'Users' 0xE716

function Add-Field($Parent, [string]$Label, [int]$Y) {
    [void](New-Label $Parent $Label 0 $Y 'Dim')
    return New-TextBox $Parent 0 ($Y + 19) 300
}

# --- Create user (left) ---
$grpCreate = New-Section $tabUsers 'Create site user' 14 420 20 300

$userPrefix = Add-Field $grpCreate 'Prefix (optional, e.g. Dr.)' 26
$userFirst  = Add-Field $grpCreate 'First name' 76
$userLast   = Add-Field $grpCreate 'Last name' 126
$userName   = Add-Field $grpCreate 'Username (filled in automatically)' 176
$userPass   = Add-Field $grpCreate 'Temporary password' 226
$userPass.Text = $script:DefaultUserPassword
Set-Mono $userName
Set-Mono $userPass

$userNote = New-Object System.Windows.Forms.Label
$userNote.Text     = 'The user is added to the SSCT group and must choose a new password at first sign-in.'
$userNote.Location = New-Object System.Drawing.Point(0, 280)
$userNote.Size     = New-Object System.Drawing.Size(300, 34)
Set-Role $userNote 'Dim'
$grpCreate.Controls.Add($userNote)

$btnCreateUser = New-Button $grpCreate 'Create User' 168 320 -Primary

$ssoNote = New-Object System.Windows.Forms.Label
Set-StatusLabel $ssoNote 'Only SSO protocols are installed. Their users sign in with SSO, so local users are usually not needed.' 'Bad'
$ssoNote.Location  = New-Object System.Drawing.Point(0, 362)
$ssoNote.Size      = New-Object System.Drawing.Size(300, 48)
$ssoNote.Visible   = $false
$grpCreate.Controls.Add($ssoNote)

foreach ($box in @($userPrefix, $userFirst, $userLast, $userName, $userPass)) { Set-EnterButton $box $btnCreateUser }

$updateUsername = { $userName.Text = ConvertTo-SiteUsername $userFirst.Text $userLast.Text }
$userFirst.Add_TextChanged($updateUsername)
$userLast.Add_TextChanged($updateUsername)

# --- Existing users (right) ---
$grpList = New-Section $tabUsers 'Site users (SSCT group)' 14 420 338 300

$userList = New-Object System.Windows.Forms.ListBox
$userList.Location      = New-Object System.Drawing.Point(0, 26)
$userList.Size          = New-Object System.Drawing.Size(300, 250)
$userList.IntegralHeight = $false
$userList.DisplayMember = 'Display'
$userList.HorizontalScrollbar = $true
$grpList.Controls.Add($userList)

$btnResetPass   = New-Button $grpList 'Reset Password' 0 286 146
$btnRenameUser  = New-Button $grpList 'Change Name' 154 286 146
$btnDeleteUser  = New-Button $grpList 'Delete User' 0 322 146
$btnUserReload  = New-Button $grpList 'Refresh' 154 322 146
$btnSharedAdmin = New-Button $grpList 'Create SharedAdmin Account' 0 381 300

function Update-UserButtons {
    $sel = $userList.SelectedItem
    $btnResetPass.Enabled  = ($null -ne $sel)
    $btnRenameUser.Enabled = ($null -ne $sel)
    $btnDeleteUser.Enabled = ($null -ne $sel) -and -not (Test-ProtectedUser $sel.Name)
}

function Update-UsersTab {
    $userList.Items.Clear()
    try {
        foreach ($u in (Get-SiteUsers)) { [void]$userList.Items.Add($u) }
    } catch {
        Show-Message "Could not list the SSCT users:`n$($_.Exception.Message)" 'Warning'
    }
    Update-UserButtons
    $btnSharedAdmin.Enabled = -not (Get-LocalUser -Name 'SharedAdmin' -ErrorAction SilentlyContinue)
    $protocols = @(Get-CaptureProtocols)
    $ssoNote.Visible = ($protocols.Count -gt 0 -and @($protocols | Where-Object { -not $_.SSO }).Count -eq 0)
}

$userList.Add_SelectedIndexChanged({ Update-UserButtons })
$btnUserReload.Add_Click({ Update-UsersTab })
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabUsers) { Update-UsersTab }
})

$btnCreateUser.Add_Click({
    $first = $userFirst.Text.Trim(); $last = $userLast.Text.Trim()
    $newUser = $userName.Text.Trim(); $pass = $userPass.Text
    if (-not $first -or -not $last -or -not $newUser -or -not $pass) {
        Show-Message 'Enter a first name, last name, username and password.' 'Warning'
        return
    }
    if ($ssoNote.Visible) {
        $go = [System.Windows.Forms.MessageBox]::Show($form,
            "Only SSO protocols are installed, so a local user is usually not needed.`nCreate '$newUser' anyway?",
            $appTitle, 'YesNo', 'Question')
        if ($go -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    $fullName = (@($userPrefix.Text.Trim(), $first, $last) | Where-Object { $_ }) -join ' '
    try {
        New-SiteUser $newUser $fullName $pass
        Show-Message "User '$newUser' ($fullName) created.`nTemporary password: $pass" 'Information' $pass
        $userPrefix.Clear(); $userFirst.Clear(); $userLast.Clear()
        $userPass.Text = $script:DefaultUserPassword
        [void]$userFirst.Focus()
    } catch {
        Show-Message "User NOT created:`n$($_.Exception.Message)" 'Error'
    }
    Update-UsersTab
})

$btnResetPass.Add_Click({
    $u = $userList.SelectedItem
    if ($null -eq $u) { return }
    $pass = Read-Text "New temporary password for '$($u.Name)' (they must change it at next sign-in):" $script:DefaultUserPassword
    if (-not $pass) { return }
    try {
        Reset-SiteUserPassword $u.Name $pass
        Show-Message "Password for '$($u.Name)' reset to '$pass'.`nThey must change it at next sign-in." 'Information' $pass
    } catch {
        Show-Message "Password NOT reset:`n$($_.Exception.Message)" 'Error'
    }
})

$btnRenameUser.Add_Click({
    $u = $userList.SelectedItem
    if ($null -eq $u) { return }
    $name = Read-Text "Full name for '$($u.Name)':" $u.FullName
    if (-not $name -or $name -eq $u.FullName) { return }
    try {
        Set-LocalUser -Name $u.Name -FullName $name -ErrorAction Stop
        Write-Log "Full name of '$($u.Name)' changed from '$($u.FullName)' to '$name'"
    } catch {
        Show-Message "Name NOT changed:`n$($_.Exception.Message)" 'Error'
    }
    Update-UsersTab
})

# The only place in the toolkit that deletes a Windows account: one selected user, after a Yes/No naming it.
$btnDeleteUser.Add_Click({
    $u = $userList.SelectedItem
    if ($null -eq $u -or (Test-ProtectedUser $u.Name)) { return }
    $confirm = [System.Windows.Forms.MessageBox]::Show($form,
        "Delete the Windows account '$($u.Display.Trim())'?`n`nThis cannot be undone.",
        $appTitle, 'YesNo', 'Warning', 'Button2')
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    Write-Log "Deleting Windows account '$($u.Name)'"
    try {
        Remove-SiteUser $u.Name
        Show-Message "'$($u.Name)' deleted." 'Information'
    } catch {
        Show-Message "User NOT deleted:`n$($_.Exception.Message)" 'Error'
    }
    Update-UsersTab
})

$btnSharedAdmin.Add_Click({
    $pass = Read-Text "Password for the new SharedAdmin administrator account:" ''
    if (-not $pass) { return }
    try {
        New-SharedAdmin $pass
        Show-Message 'SharedAdmin account created.' 'Information'
    } catch {
        Show-Message "SharedAdmin account NOT created:`n$($_.Exception.Message)" 'Error'
    }
    Update-UsersTab
})
