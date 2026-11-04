# Rolling log of what the toolkit did on this computer. Every run appends to the same file; once it
# passes $LogMaxBytes it is renamed to CDT.1.log (replacing the older one) and a fresh file starts.
# Kept outside ProgramData\Canfield so the Cleanup Tool never touches it. Logging never throws.

$script:LogDir      = Join-Path $env:ProgramData 'CanfieldDeploymentToolkit\Logs'
$script:LogFile     = Join-Path $script:LogDir 'CDT.log'
$script:LogMaxBytes = 5MB

# Writes one timestamped line. Newlines in $Message become ' | '. Every string in $Secret is replaced
# with '****' so passwords shown on screen never reach the file.
function Write-Log([string]$Message, [string]$Level = 'INFO', [string[]]$Secret) {
    try {
        foreach ($s in $Secret) { if ($s) { $Message = $Message.Replace($s, '****') } }
        $Message = ($Message -replace '\r?\n', ' | ').Trim()
        if (-not (Test-Path -LiteralPath $script:LogDir)) {
            New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
        }
        $file = Get-Item -LiteralPath $script:LogFile -ErrorAction SilentlyContinue
        if ($file -and $file.Length -gt $script:LogMaxBytes) {
            Move-Item -LiteralPath $script:LogFile -Destination (Join-Path $script:LogDir 'CDT.1.log') -Force
        }
        $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level.ToUpper(), $Message
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
    } catch { }
}

# Maps a MessageBox icon name to a log level.
function Get-LogLevel([string]$Icon) {
    switch ($Icon) {
        'Error'   { 'ERROR' }
        'Warning' { 'WARN' }
        default   { 'INFO' }
    }
}

# --- Run header ---
$toolkitVersion = if ($isExe) { [System.Diagnostics.FileVersionInfo]::GetVersionInfo($procPath).FileVersion } else { 'script' }
$runAs = if ($isExe) { "exe $procPath" } else { "script $scriptPath" }
Write-Log ('==== Toolkit started: version {0}, {1}, computer {2}, user {3}\{4}' -f
    $toolkitVersion, $runAs, $env:COMPUTERNAME, $env:USERDOMAIN, $env:USERNAME)
