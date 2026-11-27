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
