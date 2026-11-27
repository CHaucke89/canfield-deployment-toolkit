# Cross-platform smoke test (pwsh 7 on Linux/macOS/Windows). Needs no WinForms and changes nothing on the machine.
# Usage, from the repo root: pwsh -NoProfile -File .claude/skills/run-canfield-deployment-toolkit/smoke.ps1
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$src  = Join-Path $root 'src'
$fail = 0
function Check([string]$Name, [bool]$Ok, [string]$Detail = '') {
    if ($Ok) { Write-Host "PASS $Name" } else { Write-Host "FAIL $Name $Detail"; $script:fail++ }
}

# 1. Every file parses, and uses nothing Windows PowerShell 5.1 can't parse (the app runs on 5.1).
$files = @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })
foreach ($f in $files) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    $rel = $f.FullName.Substring($root.Length + 1)
    Check "parse $rel" ($errors.Count -eq 0) (($errors | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Message)" }) -join '; ')
    $ps7 = $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.TernaryExpressionAst] -or
        $n -is [System.Management.Automation.Language.PipelineChainAst] -or
        ($n -is [System.Management.Automation.Language.BinaryExpressionAst] -and $n.Operator -eq 'QuestionQuestion') -or
        ($n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Operator -eq 'QuestionQuestionEquals')
    }, $true)
    Check "ps5.1 syntax $rel" ($ps7.Count -eq 0) (($ps7 | ForEach-Object { "line $($_.Extent.StartLineNumber): $($_.Extent.Text)" }) -join '; ')
}

# 2. LoadOrder lists files that exist, and every tab file is listed.
$order = @(& (Join-Path $src 'LoadOrder.ps1'))
foreach ($rel in $order) { Check "load order: $rel exists" (Test-Path -LiteralPath (Join-Path $src ($rel -replace '\\', '/'))) }
foreach ($t in Get-ChildItem (Join-Path $src 'tabs') -Filter *.ps1) { Check "load order lists tabs\$($t.Name)" ($order -contains "tabs\$($t.Name)") }

# 3. Pure helpers (src/lib/Validation.ps1, Sponsors.ps1).
. (Join-Path $src 'lib/Validation.ps1')
. (Join-Path $src 'lib/Sponsors.ps1')
foreach ($n in 'PC-01', 'A', 'abc123') { Check "Test-ComputerName '$n' valid" (Test-ComputerName $n) }
foreach ($n in '', '-PC', 'PC-', '12345', 'ABCDEFGHIJKLMNOP', 'PC_01') { Check "Test-ComputerName '$n' invalid" (-not (Test-ComputerName $n)) }
Check 'ConvertTo-PhotographerPassword' ((ConvertTo-PhotographerPassword 'Sun Flower 42!') -eq 'sunflower')
Check 'ConvertTo-SiteUsername' ((ConvertTo-SiteUsername 'Jane' "O'Neil") -eq 'joneil')
Check 'ConvertTo-SiteUsername blank last' ((ConvertTo-SiteUsername 'Jane' '') -eq '')
$csv = "Sponsor,DeployID`n Zeta ,2`nAlpha,1`nNoId,"
$sp = @(Get-Sponsors -Path (Join-Path $root 'no-such.csv') -EmbeddedCsv $csv)
Check 'Get-Sponsors embedded fallback, sorted, trimmed, skips blanks' ($sp.Count -eq 2 -and $sp[0].Sponsor -eq 'Alpha' -and $sp[1].Sponsor -eq 'Zeta')

# 4. Expected codes were computed independently (Python). Get-ResponseCode lives in a tab file (which needs WinForms), so lift just that function out via the AST.
$capAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $src 'tabs/CanfieldCapture.ps1'), [ref]$null, [ref]$null)
$fn = $capAst.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ResponseCode' }, $true)
Invoke-Expression $fn.Extent.Text
$cases = [ordered]@{ '00000001' = '1000007B'; '00000000' = '00000000'; 'FFFFFFFF' = '400001EC'; 'abcdef12' = 'E1A239F5'; '1234567' = '--------'; 'ZZZZZZZZ' = '--------' }
foreach ($k in $cases.Keys) { $got = Get-ResponseCode $k; Check "Get-ResponseCode '$k' -> $($cases[$k])" ($got -eq $cases[$k]) "got $got" }

# 5. The build's inlining step (Build-Toolkit-Exe.ps1 without PS2EXE): markers found, result parses.
$entry = Get-Content -LiteralPath (Join-Path $root 'Install-Toolkit.ps1') -Raw
$b = $entry.IndexOf('# __SOURCES_BEGIN__'); $e = $entry.IndexOf('# __SOURCES_END__')
Check 'build markers present' ($b -ge 0 -and $e -gt $b)
Check 'embedded CSV marker present' ($entry.Contains('$EmbeddedCsv = $null # __EMBEDDED_CSV__'))
$inlined = ($order | ForEach-Object { Get-Content -LiteralPath (Join-Path $src ($_ -replace '\\', '/')) -Raw }) -join "`r`n"
$single = $entry.Substring(0, $b) + $inlined + $entry.Substring($e + '# __SOURCES_END__'.Length)
$errs = $null; [void][System.Management.Automation.Language.Parser]::ParseInput($single, [ref]$null, [ref]$errs)
Check 'inlined single-file script parses' ($errs.Count -eq 0) (($errs | Select-Object -First 3 | ForEach-Object Message) -join '; ')

Write-Host ''
if ($fail) { Write-Host "$fail check(s) failed"; exit 1 } else { Write-Host 'All checks passed' }
