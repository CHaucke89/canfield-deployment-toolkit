<#
.SYNOPSIS
    Packages Install-Toolkit.ps1 plus the src\ files (inlined) into a single CDT.exe using PS2EXE (run on Windows).
    Run from the folder containing Install-Toolkit.ps1 and src\. Asks for sponsors.csv to embed as a fallback.
    If blocked by execution policy: powershell -ExecutionPolicy Bypass -File .\Build-Toolkit-Exe.ps1

.PARAMETER Version
    Version stamped into the exe (file and product version). Accepts a release tag such as 'v1.2.0';
    a leading 'v' is dropped and missing parts are filled with 0 (v1.2.0 -> 1.2.0.0). Defaults to 1.0.0.0.

.PARAMETER SponsorsPath
    sponsors.csv to embed. When omitted, an interactive build asks for it (cancel or blank skips it).

.PARAMETER NoPrompt
    Never ask for sponsors.csv. Implied when CI is set or PowerShell runs with -NonInteractive.
#>
[CmdletBinding()]
param(
    [string]$Version = '1.0.0.0',
    [string]$SponsorsPath,
    [switch]$NoPrompt
)
$ErrorActionPreference = 'Stop'
$src = Join-Path $PSScriptRoot 'Install-Toolkit.ps1'
$tmp = Join-Path $PSScriptRoot 'Install-Toolkit.build.ps1'
$out = Join-Path $PSScriptRoot 'build\CDT.exe'
$icon = Join-Path $PSScriptRoot 'assets\toolkit.ico'

# PS2EXE needs a 4-part numeric version (major.minor.build.revision).
$parsed = $null
if (-not [version]::TryParse(($Version -replace '^[vV]', ''), [ref]$parsed)) {
    throw "Version '$Version' is not a valid version (expected e.g. v1.2.0 or 1.2.0.0)."
}
$exeVersion = '{0}.{1}.{2}.{3}' -f $parsed.Major, $parsed.Minor, [math]::Max($parsed.Build, 0), [math]::Max($parsed.Revision, 0)

# Returns the chosen CSV path, or $null to build without one. Uses a file dialog, or the console when no dialog can be shown.
function Select-SponsorsCsv {
    $default = Join-Path $PSScriptRoot 'sponsors.csv'
    # OpenFileDialog needs an STA thread (Windows PowerShell 5.1 is STA; pwsh 7 is not).
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA') {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            $dlg = New-Object System.Windows.Forms.OpenFileDialog
            $dlg.Title            = 'Select sponsors.csv to embed (Cancel to build without it)'
            $dlg.Filter           = 'CSV files (*.csv)|*.csv|All files (*.*)|*.*'
            $dlg.InitialDirectory = $PSScriptRoot
            if (Test-Path -LiteralPath $default) { $dlg.FileName = 'sponsors.csv' }
            # A hidden topmost owner keeps the dialog from opening behind the console.
            $owner = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
            try {
                if ($dlg.ShowDialog($owner) -eq 'OK') { return $dlg.FileName }
                return $null
            } finally { $owner.Dispose(); $dlg.Dispose() }
        } catch {
            Write-Warning "File dialog unavailable ($($_.Exception.Message)); asking in the console."
        }
    }
    while ($true) {
        $answer = (Read-Host 'Path to sponsors.csv to embed (blank to build without it)').Trim().Trim('"')
        if (-not $answer) { return $null }
        if (Test-Path -LiteralPath $answer -PathType Leaf) { return $answer }
        Write-Warning "File not found: $answer"
    }
}

$nonInteractive = $NoPrompt -or $env:CI -or
    ([Environment]::GetCommandLineArgs() | Where-Object { $_ -like '-NonI*' })
if ($SponsorsPath) {
    if (-not (Test-Path -LiteralPath $SponsorsPath -PathType Leaf)) { throw "Sponsors CSV not found: $SponsorsPath" }
    $csv = $SponsorsPath
} elseif ($nonInteractive) {
    $csv = $null
} else {
    $csv = Select-SponsorsCsv
}
if ($csv) {
    $cols = @((Import-Csv -LiteralPath $csv | Select-Object -First 1).PSObject.Properties.Name)
    if ('Sponsor' -notin $cols -or 'DeployID' -notin $cols) {
        throw "Sponsors CSV must have Sponsor and DeployID headers: $csv"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'build'))) {
    New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'build') | Out-Null
}

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

# Inline the src\ files (in LoadOrder.ps1 order) in place of the dot-source block, so the exe is self-contained.
$srcDir = Join-Path $PSScriptRoot 'src'
$parts  = foreach ($rel in (& (Join-Path $srcDir 'LoadOrder.ps1'))) {
    "# ---- src\$rel ----`r`n" + (Get-Content -LiteralPath (Join-Path $srcDir $rel) -Raw)
}
$inlined = $parts -join "`r`n"

# Embed a snapshot of the CSV as a fallback (an external CSV beside the exe still takes priority).
$content = Get-Content -LiteralPath $src -Raw
$begin = $content.IndexOf('# __SOURCES_BEGIN__')
$endMarker = '# __SOURCES_END__'
$end = $content.IndexOf($endMarker)
if ($begin -lt 0 -or $end -lt $begin) { throw 'Source markers not found in Install-Toolkit.ps1.' }
$content = $content.Substring(0, $begin) + $inlined + $content.Substring($end + $endMarker.Length)
if ($csv) {
    $csvText = (Get-Content -LiteralPath $csv -Raw).TrimEnd()
    $embed   = "`$EmbeddedCsv = @'`r`n$csvText`r`n'@"
    $content = $content.Replace('$EmbeddedCsv = $null # __EMBEDDED_CSV__', $embed)
    Write-Host "Embedding sponsor list: $csv"
} else {
    Write-Warning 'No sponsors.csv selected; building without an embedded sponsor list.'
}
Set-Content -LiteralPath $tmp -Value $content -Encoding UTF8

try {
    Invoke-ps2exe -inputFile $tmp -outputFile $out `
        -noConsole -requireAdmin -STA -iconFile $icon `
        -title 'Canfield Deployment Toolkit' -product 'Canfield Deployment Toolkit' -version $exeVersion
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
Write-Host "Built: $out (version $exeVersion)"
