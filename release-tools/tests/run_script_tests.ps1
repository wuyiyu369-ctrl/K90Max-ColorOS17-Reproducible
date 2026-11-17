param([string]$PackageRoot)

$ErrorActionPreference = 'Stop'
if (-not $PackageRoot) { throw 'PackageRoot is required.' }
$Wizard = Join-Path $PackageRoot 'K90_FLASH_WIZARD.ps1'
$MockRoot = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'mocks'
$OriginalMockRoot = $env:K90_MOCK_ROOT
$OriginalState = $env:K90_MOCK_STATE
$OriginalFailPart = $env:K90_MOCK_FAIL_PART
$Failures = @()

function Run-Case([string]$Name, [string]$State, [string]$Mode, [string]$DataMode, [string]$RootMode, [string]$ModuleMode, [int]$ExpectedExit, [string]$FailPart) {
    $StateFile = Join-Path $MockRoot 'state.txt'
    if (Test-Path -LiteralPath $StateFile) { Remove-Item -LiteralPath $StateFile -Force }
    $env:K90_MOCK_ROOT = $MockRoot
    $env:K90_MOCK_STATE = $State
    $env:K90_MOCK_FAIL_PART = $FailPart
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $Wizard -NonInteractive -Mode $Mode -DataMode $DataMode -RootMode $RootMode -ModuleMode $ModuleMode
    $Actual = $LASTEXITCODE
    if ($Actual -ne $ExpectedExit) {
        $script:Failures += ($Name + ': expected ' + $ExpectedExit + ', got ' + $Actual)
        Write-Host ('[FAIL] ' + $Name) -ForegroundColor Red
    } else {
        Write-Host ('[PASS] ' + $Name) -ForegroundColor Green
    }
}

try {
    Run-Case 'Win7-like update, ADB, stock, keep data' 'adb' '1' '1' '1' '1' 0 ''
    Run-Case 'Win10-like full, bootloader, root, keep data' 'bootloader' '2' '1' '2' '2' 0 ''
    Run-Case 'Win11-like full, fastbootd, stock, wipe' 'fastbootd' '2' '2' '1' '2' 0 ''
    Run-Case 'No device must stop' 'none' '1' '1' '1' '2' 1 ''
    Run-Case 'Multiple devices must stop' 'multi' '1' '1' '1' '2' 1 ''
    Run-Case 'Partition failure must stop' 'bootloader' '1' '1' '1' '2' 1 'vendor_boot'
} finally {
    $env:K90_MOCK_ROOT = $OriginalMockRoot
    $env:K90_MOCK_STATE = $OriginalState
    $env:K90_MOCK_FAIL_PART = $OriginalFailPart
}

if ($Failures.Count -gt 0) {
    $Failures | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}
Write-Host 'All script branch tests passed.' -ForegroundColor Green
exit 0
