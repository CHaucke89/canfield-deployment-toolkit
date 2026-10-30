# Tab: Canfield Capture

$tabUsb = New-Object System.Windows.Forms.TabPage; $tabUsb.Text = 'Canfield Capture'
[void]$tabs.TabPages.Add($tabUsb)

$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Text     = 'Scan USB'
$btnScan.Location = New-Object System.Drawing.Point(15, 12)
$btnScan.Size     = New-Object System.Drawing.Size(90, 26)
$tabUsb.Controls.Add($btnScan)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text     = 'Browse...'
$btnBrowse.Location = New-Object System.Drawing.Point(110, 12)
$btnBrowse.Size     = New-Object System.Drawing.Size(90, 26)
$tabUsb.Controls.Add($btnBrowse)

$usbInfo = New-Object System.Windows.Forms.Label
$usbInfo.Text     = 'Click Scan USB to look for setup.exe, or Browse... to pick it.'
$usbInfo.Location = New-Object System.Drawing.Point(210, 18)
$usbInfo.Size     = New-Object System.Drawing.Size(385, 18)
$usbInfo.AutoEllipsis = $true
$tabUsb.Controls.Add($usbInfo)

$list = New-Object System.Windows.Forms.ListBox
$list.Location      = New-Object System.Drawing.Point(15, 48)
$list.Size          = New-Object System.Drawing.Size(580, 315)
$list.HorizontalScrollbar = $true
$list.DisplayMember = 'Display'
$list.DrawMode      = 'OwnerDrawFixed'
$tabUsb.Controls.Add($list)

# Legend for the list colors.
$legendInstalled = New-Object System.Windows.Forms.Label
$legendInstalled.Text      = 'Green = already installed on this computer'
$legendInstalled.ForeColor = [System.Drawing.Color]::ForestGreen
$legendInstalled.Location  = New-Object System.Drawing.Point(15, 366)
$legendInstalled.AutoSize  = $true
$tabUsb.Controls.Add($legendInstalled)

$legendNew = New-Object System.Windows.Forms.Label
$legendNew.Text     = 'Black = not installed'
$legendNew.Location = New-Object System.Drawing.Point(300, 366)
$legendNew.AutoSize = $true
$tabUsb.Controls.Add($legendNew)

# Response code generator (replaces ResponseCodeGenerator.exe).
$lblRequest = New-Object System.Windows.Forms.Label
$lblRequest.Text     = 'Request code:'
$lblRequest.Location = New-Object System.Drawing.Point(15, 398)
$lblRequest.AutoSize = $true
$tabUsb.Controls.Add($lblRequest)

$txtRequest = New-Object System.Windows.Forms.TextBox
$txtRequest.Location  = New-Object System.Drawing.Point(95, 395)
$txtRequest.Size      = New-Object System.Drawing.Size(75, 20)
$txtRequest.MaxLength = 8
$txtRequest.CharacterCasing = 'Upper'
$tabUsb.Controls.Add($txtRequest)

$lblResponse = New-Object System.Windows.Forms.Label
$lblResponse.Text     = 'Response code:'
$lblResponse.Location = New-Object System.Drawing.Point(180, 398)
$lblResponse.AutoSize = $true
$tabUsb.Controls.Add($lblResponse)

$txtResponse = New-Object System.Windows.Forms.TextBox
$txtResponse.Location = New-Object System.Drawing.Point(265, 395)
$txtResponse.Size     = New-Object System.Drawing.Size(75, 20)
$txtResponse.ReadOnly = $true
$tabUsb.Controls.Add($txtResponse)

$lblAutoFill = New-Object System.Windows.Forms.Label
$lblAutoFill.Location = New-Object System.Drawing.Point(350, 398)
$lblAutoFill.Size     = New-Object System.Drawing.Size(120, 18)
$lblAutoFill.AutoEllipsis = $true
$tabUsb.Controls.Add($lblAutoFill)
$autoFillTip = New-Object System.Windows.Forms.ToolTip

$btnUsb = New-Object System.Windows.Forms.Button
$btnUsb.Text     = 'Install Selected'
$btnUsb.Location = New-Object System.Drawing.Point(475, 390)
$btnUsb.Size     = New-Object System.Drawing.Size(120, 30)
$btnUsb.Enabled  = $false
$tabUsb.Controls.Add($btnUsb)

$script:usbScanned = $false

# Marks list entries that are already installed (shown in green) and sizes the horizontal scrollbar.
# Study builds can share a version (such as several 'v6.1.0' installers), so an entry is matched by the folder name the
# install was run from (the registry's InstallSource). Only versions installed without a recorded source
# fall back to matching by version.
function Update-InstalledMarks {
    $entries = @(Get-CaptureUninstallEntries)
    $sources = @($entries | Where-Object { $_.Source } | ForEach-Object { Split-Path -Leaf $_.Source.TrimEnd('\') })
    $withSource = @($entries | Where-Object { $_.Source } | ForEach-Object { $_.Name })
    $versionOnly = @(Get-CaptureInstalls | Where-Object { $withSource -notcontains $_.Name } |
        ForEach-Object { $_.Name -replace '^Canfield Capture ', '' })
    $widest = 0
    foreach ($item in $list.Items) {
        $leaf = Split-Path -Leaf $item.Folder.TrimEnd('\')
        $item.Installed = [bool](($sources -contains $leaf) -or ($item.Version -and ($versionOnly -contains $item.Version)))
        $widest = [math]::Max($widest, [System.Windows.Forms.TextRenderer]::MeasureText($item.Display, $list.Font).Width)
    }
    $list.HorizontalExtent = $widest + 6
    $list.Invalidate()
}

$list.Add_DrawItem({
    param($sender, $e)
    if ($e.Index -lt 0) { return }
    $e.DrawBackground()
    $item = $list.Items[$e.Index]
    $selected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0
    $color = if ($selected) { [System.Drawing.SystemColors]::HighlightText }
        elseif ($item.Installed) { [System.Drawing.Color]::ForestGreen }
        else { $list.ForeColor }
    $flags = [System.Windows.Forms.TextFormatFlags]'Left, VerticalCenter, NoPrefix'
    $bounds = New-Object System.Drawing.Rectangle($e.Bounds.X, $e.Bounds.Y, [math]::Max($e.Bounds.Width, $list.HorizontalExtent), $e.Bounds.Height)
    [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $item.Display, $e.Font, $bounds, $color, $flags)
    $e.DrawFocusRectangle()
})
function Invoke-UsbScan {
    $script:usbScanned = $true
    $list.Items.Clear()
    $btnUsb.Enabled = $false

    Enter-Busy "Looking for USB drives..." $true
    $roots = Get-UsbDriveRoots
    if ($roots.Count -eq 0) {
        Exit-Busy
        $usbInfo.Text = 'No USB drive detected. Insert one and click Scan USB, or click Browse...'
        return
    }

    $skipNames = @('$RECYCLE.BIN', 'System Volume Information')
    $found = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    foreach ($r in $roots) { $stack.Push($r) }

    $scanned = 0
    while ($stack.Count -gt 0 -and -not $script:cancelRequested) {
        $dir = $stack.Pop()
        $scanned++
        if ($scanned % 25 -eq 0) { Set-Status ("Searching USB drive for Canfield Capture installers...`n{0}" -f $dir) }
        else { [System.Windows.Forms.Application]::DoEvents() }
        try {
            if ([System.IO.File]::Exists((Join-Path $dir 'setup.exe'))) { $found.Add($dir) }
            foreach ($sub in [System.IO.Directory]::EnumerateDirectories($dir)) {
                if ($skipNames -contains (Split-Path -Leaf $sub)) { continue }
                # don't follow junctions/symlinks (avoids loops)
                if ([System.IO.File]::GetAttributes($sub) -band [System.IO.FileAttributes]::ReparsePoint) { continue }
                $stack.Push($sub)
            }
        } catch { }   # unreadable folder: skip
    }
    $cancelled = $script:cancelRequested
    Exit-Busy

    if ($cancelled) { $usbInfo.Text = 'Scan cancelled.'; return }
    if ($found.Count -eq 0) { $usbInfo.Text = 'No installer found on the USB drive. Click Browse... to pick one.'; return }

    foreach ($f in ($found | Sort-Object)) { [void](Add-InstallerItem $f) }
    Update-InstalledMarks
    $usbInfo.Text = 'Found installer(s) in {0} folder(s). Select one:' -f $found.Count
}

# Adds an installer folder (one containing setup.exe) to the list unless it is already there; returns its item.
function Add-InstallerItem([string]$Folder) {
    foreach ($item in $list.Items) { if ($item.Folder -eq $Folder) { return $item } }
    $name = Split-Path -Leaf $Folder
    if (-not $name) { $name = $Folder }   # setup.exe in the drive root
    $display = '{0}    ({1})' -f $name, $Folder
    $item = [pscustomobject]@{ Display = $display; Folder = $Folder; Version = (Get-InstallerVersion $Folder); Installed = $false }
    [void]$list.Items.Add($item)
    return $item
}

# Manual fallback: pick a setup.exe anywhere (network share, local folder, unlisted drive) and add it to the list.
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title  = 'Select the Canfield Capture installer (setup.exe)'
    $dlg.Filter = 'Canfield Capture installer (setup.exe)|setup.exe|Programs (*.exe)|*.exe'
    if ($dlg.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    if ((Split-Path -Leaf $dlg.FileName) -ne 'setup.exe') {
        Show-Message "Please select the installer's setup.exe." 'Warning'
        return
    }
    $item = Add-InstallerItem (Split-Path -Parent $dlg.FileName)
    Update-InstalledMarks
    $list.SelectedItem = $item
    $usbInfo.Text = 'Added {0}. Click Install Selected to install it.' -f $item.Folder
})

$btnScan.Add_Click({ Invoke-UsbScan })
$list.Add_SelectedIndexChanged({ $btnUsb.Enabled = ($null -ne $list.SelectedItem) })
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tabUsb -and -not $script:usbScanned) { Invoke-UsbScan }
})

$btnUsb.Add_Click({
    $choice = $list.SelectedItem
    if ($null -eq $choice) { return }
    $setup  = Join-Path $choice.Folder 'setup.exe'

    if (-not (Test-Path -LiteralPath $setup)) {
        Show-Message "Installer is no longer available:`n$setup`nWas the USB drive or network share removed?" 'Error'
        return
    }
    $installed = @(Get-CaptureInstalls)
    if ($installed.Count -gt 0) {
        $names = ($installed | ForEach-Object { $_.Display }) -join ', '
        $again = [System.Windows.Forms.MessageBox]::Show($form,
            "Canfield Capture is already installed ($names).`nInstall '$(Split-Path -Leaf $choice.Folder)' as well?",
            $appTitle, 'YesNo', 'Question')
        if ($again -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }

    Enter-Busy "Starting installer...`n$($choice.Folder)"
    try {
        $label = "Installing from '{0}' silently, please wait." -f (Split-Path -Leaf $choice.Folder)
        # Normal window style: if an installer ignores the switches and shows UI, the user can see it.
        $code = Invoke-WithProgress $setup $SilentArgs $choice.Folder 'Normal' $label
        Exit-Busy
        Update-InstalledMarks
        switch ($code) {
            0       { Show-Message "Installation completed successfully." 'Information' }
            { $_ -in 1641, 3010 } { Show-Message "Installation completed. A reboot is required to finish." 'Information' }
            default { Show-Message "The installer exited with code $code.`nIf nothing was installed, run setup.exe from $($choice.Folder) manually." 'Warning' }
        }
    } catch {
        Exit-Busy
        Show-Message "Could not run the installer:`n$($_.Exception.Message)" 'Error'
    }
})

# Same calculation as ResponseCodeGenerator.exe: the 8-hex-digit request code times 268435579,
# modulo 4294967291 (0xFFFFFFFB). Anything else gives '--------', as the exe did.
function Get-ResponseCode([string]$request) {
    $value = [uint32]0
    if ($request.Length -ne 8 -or
        -not [uint32]::TryParse($request, 'HexNumber', [System.Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
        return '--------'
    }
    $product = [uint64]$value * [uint64]268435579
    return '{0:X8}' -f [uint32]($product % [uint64]4294967291)
}

$txtRequest.Add_TextChanged({ $txtResponse.Text = Get-ResponseCode $txtRequest.Text.Trim() })

# Auto-fill: Canfield Capture connects to the named pipe "CanfieldPipe", writes the request code as one
# line and reads the response code back as one line. Serve that pipe from a background runspace while the
# toolkit is open. The toolkit runs elevated, so the pipe gets an explicit DACL; with the default one the
# non-elevated Capture process can't open it for writing.
$script:rcgShared = [hashtable]::Synchronized(@{ Stop = $false; State = 'Starting'; Request = $null; Seq = 0 })
$rcgListener = {
    param($shared, [string]$computeText)
    $compute = [scriptblock]::Create($computeText)
    while (-not $shared.Stop) {
        $pipe = $null
        try {
            $sec = New-Object System.IO.Pipes.PipeSecurity
            $users = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-11')   # Authenticated Users
            # CreateNewInstance is included because a client opening with GENERIC_WRITE asks for it.
            $sec.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule($users,
                [System.IO.Pipes.PipeAccessRights]'ReadWrite, CreateNewInstance, Synchronize', 'Allow')))
            foreach ($sid in 'S-1-5-32-544', 'S-1-5-18') {   # Administrators, SYSTEM
                $sec.AddAccessRule((New-Object System.IO.Pipes.PipeAccessRule(
                    (New-Object System.Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'Allow')))
            }
            $pipe = New-Object System.IO.Pipes.NamedPipeServerStream('CanfieldPipe', 'InOut', 1, 'Byte',
                'Asynchronous', 0, 0, $sec)
            $shared.State = 'Listening'
            $wait = $pipe.BeginWaitForConnection($null, $null)
            while (-not $wait.AsyncWaitHandle.WaitOne(500)) { if ($shared.Stop) { return } }
            $pipe.EndWaitForConnection($wait)

            $reader = New-Object System.IO.StreamReader($pipe)
            $writer = New-Object System.IO.StreamWriter($pipe)
            $writer.AutoFlush = $true
            $request = $reader.ReadLine()
            $writer.WriteLine((& $compute $request))
            $pipe.WaitForPipeDrain()
            $shared.Request = $request
            $shared.Seq++
        } catch {
            # Most likely ResponseCodeGenerator.exe (or a second toolkit) already owns the pipe.
            $shared.State = 'Off: ' + $_.Exception.Message
            Start-Sleep -Seconds 3
        } finally {
            if ($pipe) { $pipe.Dispose() }
        }
    }
}
$rcgPs = [PowerShell]::Create()
[void]$rcgPs.AddScript($rcgListener).AddArgument($script:rcgShared).AddArgument(${function:Get-ResponseCode}.ToString())
[void]$rcgPs.BeginInvoke()

# Show listener state and copy a request Capture sent into the boxes (UI thread).
$script:rcgSeenSeq = 0
$rcgTimer = New-Object System.Windows.Forms.Timer
$rcgTimer.Interval = 500
$rcgTimer.Add_Tick({
    $state = $script:rcgShared.State
    $lblAutoFill.Text = if ($state -eq 'Listening') { 'Auto-fill ready' } else { $state }
    $autoFillTip.SetToolTip($lblAutoFill, $state)
    if ($script:rcgShared.Seq -ne $script:rcgSeenSeq) {
        $script:rcgSeenSeq = $script:rcgShared.Seq
        $txtRequest.Text = $script:rcgShared.Request
    }
})
$rcgTimer.Start()
$form.Add_FormClosed({ $script:rcgShared.Stop = $true; $rcgTimer.Stop() })
