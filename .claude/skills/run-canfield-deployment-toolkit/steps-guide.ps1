# User-guide screenshots of the Computer and Remote Access tabs, with placeholder data instead of runner details.
Select-Tab 'Computer'
$nameCurrent.Text = 'Current computer name: SITE-PC-01'
Save-Shot 'computer'

Select-Tab 'Remote Access'
if ($lmiNote) { $lmiNote.Visible = $false }
$combo.Enabled = $true
[void]$combo.Items.Add([pscustomobject]@{ Sponsor = 'Example Sponsor'; DeployID = '' })
$combo.SelectedIndex = 0
Save-Shot 'remote-access'
