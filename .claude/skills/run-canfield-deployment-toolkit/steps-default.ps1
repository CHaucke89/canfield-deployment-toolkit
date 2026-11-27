# Default steps: one screenshot per tab, then a response code typed into the Canfield Capture tab.
foreach ($page in @($tabs.TabPages)) {
    Select-Tab $page.Text
    Save-Shot ($page.Text -replace '\W', '-').ToLower()
}
Select-Tab 'Canfield Capture'
Set-Text $txtRequest '00000001'
Write-Host "response code: $($txtResponse.Text)"
if ($txtResponse.Text -ne '1000007B') { throw "Expected response 1000007B, got '$($txtResponse.Text)'" }
Save-Shot 'response-code'

# An invalid computer name shows a warning box (nothing is renamed); the driver captures and closes it.
Select-Tab 'Computer'
Set-Text $nameBox '-bad-'
Invoke-Click $btnName
if ($script:dialogs -ne 1) { throw "Expected 1 dialog, saw $script:dialogs" }

# Dark theme: one shot per tab, then back to light. The choice is saved to settings.json each time.
$chkDark.Checked = $true
Wait-UI 500
if ((Get-ThemeSetting) -ne 'Dark') { throw "Expected saved theme Dark, got '$(Get-ThemeSetting)'" }
foreach ($page in @($tabs.TabPages)) {
    Select-Tab $page.Text
    Save-Shot ((($page.Text -replace '\W', '-').ToLower()) + '-dark')
}
# What is really on screen (DrawToBitmap ignores the dark title bar and scroll bars); best effort on the runner.
Select-Tab 'Summary'
try {
    $script:shot++
    $bmp = New-Object System.Drawing.Bitmap($form.Width, $form.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($form.Location, [System.Drawing.Point]::Empty, $form.Size)
    $g.Dispose(); $bmp.Save((Join-Path $OutDir ('{0:D2}-summary-dark-screen.png' -f $script:shot))); $bmp.Dispose()
} catch { Write-Host "screen capture failed: $($_.Exception.Message)" }
$chkDark.Checked = $false
Wait-UI 500
if ((Get-ThemeSetting) -ne 'Light') { throw "Expected saved theme Light, got '$(Get-ThemeSetting)'" }
Select-Tab 'Computer'
Save-Shot 'computer-light-again'
