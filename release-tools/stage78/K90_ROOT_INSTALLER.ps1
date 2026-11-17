param(
    [string]$ImagePath,
    [string]$Serial,
    [switch]$NonInteractive
)

$ErrorActionPreference = 'Stop'
$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:Adb = Join-Path $Script:Root 'platform-tools\adb.exe'
$Script:Fastboot = Join-Path $Script:Root 'platform-tools\fastboot.exe'
$Script:LogDir = Join-Path $Script:Root 'logs'
$Script:LogFile = Join-Path $Script:LogDir ('root_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
$Script:StockHash = 'B230738ED4F459E01E6BF8FC00DC5D5A01B28908698EB2ED89CFE6EF99D8C40E'
$Script:OldPatchedHash = '01726788672FDC57063DD5A3D6A085C0D846538F812B91EFAAE7A898BF3C9FF7'

if (-not (Test-Path -LiteralPath $Script:LogDir)) {
    New-Item -ItemType Directory -Path $Script:LogDir | Out-Null
}

function Write-Log([string]$Text) {
    $Line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text
    [IO.File]::AppendAllText($Script:LogFile, $Line + [Environment]::NewLine, [Text.Encoding]::UTF8)
}

function Get-Sha256([string]$Path) {
    $Provider = New-Object Security.Cryptography.SHA256CryptoServiceProvider
    $Stream = [IO.File]::OpenRead($Path)
    try {
        return ([BitConverter]::ToString($Provider.ComputeHash($Stream))).Replace('-', '').ToUpperInvariant()
    } finally {
        $Stream.Dispose()
        $Provider.Dispose()
    }
}

function Run([string]$Tool, [string[]]$Arguments, [switch]$AllowFailure) {
    Write-Log ('RUN: ' + $Tool + ' ' + ($Arguments -join ' '))
    $Text = & $Tool @Arguments 2>&1 | Out-String
    $Code = $LASTEXITCODE
    if ($Text.Trim()) { Write-Log ('OUT: ' + ($Text.Trim() -replace '[\r\n]+', ' | ')) }
    if ((-not $AllowFailure) -and $Code -ne 0) {
        throw ('命令失败，退出码 ' + $Code + '：' + $Text.Trim())
    }
    return New-Object PSObject -Property @{ Code=$Code; Text=$Text }
}

function Get-AdbDevices {
    $Result = Run $Script:Adb @('devices') -AllowFailure
    return @([regex]::Matches($Result.Text, '(?m)^(\S+)\s+device\s*$') | ForEach-Object { $_.Groups[1].Value })
}

function Get-FastbootDevices {
    $Result = Run $Script:Fastboot @('devices') -AllowFailure
    return @([regex]::Matches($Result.Text, '(?m)^(\S+)\s+fastboot\s*$') | ForEach-Object { $_.Groups[1].Value })
}

function Wait-Fastboot([int]$Seconds) {
    $Deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $Devices = Get-FastbootDevices
        if ($Devices.Count -eq 1) { return $Devices[0] }
        if ($Devices.Count -gt 1) { throw '检测到多台 Fastboot 设备，请只连接一台手机。' }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $Deadline)
    throw '没有检测到 Fastboot 设备，请检查驱动、数据线和 USB 端口。'
}

function Read-ImagePath {
    if ($ImagePath) { return $ImagePath.Trim().Trim('"') }
    Write-Host ''
    Write-Host '请把最新版 KernelSU 修补完成的 init_boot 镜像拖进此窗口，然后按回车。' -ForegroundColor Cyan
    Write-Host '也可以直接粘贴镜像完整路径。不要使用 boot.img、vendor_boot.img 或其他机型镜像。' -ForegroundColor Yellow
    return (Read-Host '镜像路径').Trim().Trim('"')
}

try {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' K90 Max / prague  ROOT init_boot 安装工具' -ForegroundColor Cyan
    Write-Host ' 作者：哆啦A梦' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '此工具只刷当前活动槽的 init_boot，不会刷 super、boot、modem 或数据分区。'
    Write-Host '设备必须为 Redmi K90 Max（prague），Bootloader 必须已解锁。' -ForegroundColor Yellow

    if (-not (Test-Path -LiteralPath $Script:Adb)) { throw '缺少 platform-tools\adb.exe。' }
    if (-not (Test-Path -LiteralPath $Script:Fastboot)) { throw '缺少 platform-tools\fastboot.exe。' }

    $ImagePath = Read-ImagePath
    if (-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)) { throw ('找不到镜像：' + $ImagePath) }
    if ([IO.Path]::GetExtension($ImagePath).ToLowerInvariant() -ne '.img') { throw '只接受 .img 镜像。' }
    $Info = Get-Item -LiteralPath $ImagePath
    if ($Info.Length -lt 1048576 -or $Info.Length -gt 67108864) { throw ('镜像大小异常：' + $Info.Length + ' 字节。') }
    $Stream = [IO.File]::OpenRead($ImagePath)
    try {
        $MagicBytes = New-Object byte[] 8
        [void]$Stream.Read($MagicBytes, 0, 8)
        $Magic = [Text.Encoding]::ASCII.GetString($MagicBytes)
    } finally { $Stream.Dispose() }
    if ($Magic -ne 'ANDROID!') { throw '镜像没有 ANDROID! boot magic，禁止刷入。' }

    $Hash = Get-Sha256 $ImagePath
    Write-Host ('SHA-256：' + $Hash)
    Write-Log ('IMAGE: ' + $ImagePath + ' SIZE=' + $Info.Length + ' SHA256=' + $Hash)
    if ($Hash -eq $Script:StockHash) { throw '你拖入的是原厂无 Root init_boot，并不是 KernelSU 修补镜像。' }
    if ($Hash -eq $Script:OldPatchedHash) {
        Write-Host '警告：这是旧的 KernelSU 修补镜像。建议返回并用最新版管理器重新修补桌面的原厂镜像。' -ForegroundColor Yellow
        if ($NonInteractive) { throw '非交互模式拒绝旧修补镜像。' }
        if ((Read-Host '仍要继续请输入 OLD').Trim().ToUpperInvariant() -ne 'OLD') { throw '已取消。' }
    }

    $AdbDevices = Get-AdbDevices
    $FastbootDevices = Get-FastbootDevices
    if ($Serial) {
        if (($AdbDevices -notcontains $Serial) -and ($FastbootDevices -notcontains $Serial)) { throw ('找不到指定设备：' + $Serial) }
    } else {
        $All = @($AdbDevices + $FastbootDevices | Sort-Object -Unique)
        if ($All.Count -eq 0) { throw '没有检测到手机。请开启 USB 调试，或手动进入 Fastboot。' }
        if ($All.Count -gt 1) { throw '检测到多台手机，请只连接一台。' }
        $Serial = $All[0]
    }

    if ($AdbDevices -contains $Serial) {
        $Device = Run $Script:Adb @('-s',$Serial,'shell','getprop','ro.product.vendor.device') -AllowFailure
        if ($Device.Text.Trim() -ne 'prague') { throw ('ADB 设备代号不是 prague：' + $Device.Text.Trim()) }
    }

    if (-not $NonInteractive) {
        Write-Host ''
        Write-Host '即将刷写 init_boot。刷写期间不要拔线。' -ForegroundColor Red
        if ((Read-Host '确认使用这个修补镜像，请输入 ROOT').Trim().ToUpperInvariant() -ne 'ROOT') { throw '已取消。' }
    }

    if ($AdbDevices -contains $Serial) {
        Write-Host '正在从系统重启到 Fastboot……' -ForegroundColor Yellow
        Run $Script:Adb @('-s',$Serial,'reboot','bootloader') | Out-Null
    }
    $Serial = Wait-Fastboot 120

    $Userspace = Run $Script:Fastboot @('-s',$Serial,'getvar','is-userspace') -AllowFailure
    if ($Userspace.Text -match '(?im)is-userspace\s*:\s*yes\b') {
        Write-Host '正在从 fastbootd 返回普通 Fastboot……' -ForegroundColor Yellow
        Run $Script:Fastboot @('-s',$Serial,'reboot','bootloader') | Out-Null
        $Serial = Wait-Fastboot 120
    }

    $Product = Run $Script:Fastboot @('-s',$Serial,'getvar','product') -AllowFailure
    if ($Product.Text -notmatch '(?im)(product|product-name)\s*:\s*prague\b') { throw ('设备代号不是 prague：' + $Product.Text.Trim()) }
    $Unlocked = Run $Script:Fastboot @('-s',$Serial,'getvar','unlocked') -AllowFailure
    if ($Unlocked.Text -notmatch '(?im)unlocked\s*:\s*yes\b') { throw 'Bootloader 未确认解锁，停止刷写。' }

    $SlotResult = Run $Script:Fastboot @('-s',$Serial,'getvar','current-slot') -AllowFailure
    if ($SlotResult.Text -notmatch '(?im)current-slot\s*:\s*([ab])\b') { throw '无法读取当前活动槽，停止刷写。' }
    $Slot = $Matches[1].ToLowerInvariant()
    $Partition = 'init_boot_' + $Slot
    Write-Host ('正在刷入 ' + $Partition + '，请勿拔线……') -ForegroundColor Yellow
    Run $Script:Fastboot @('-s',$Serial,'flash',$Partition,$ImagePath) | Out-Null
    Write-Host 'Root init_boot 刷入成功，正在重启手机。' -ForegroundColor Green
    Run $Script:Fastboot @('-s',$Serial,'reboot') | Out-Null
    Write-Host ('日志：' + $Script:LogFile)
    exit 0
} catch {
    Write-Host ''
    Write-Host ('操作已停止：' + $_.Exception.Message) -ForegroundColor Red
    Write-Log ('ERROR: ' + $_.Exception.Message)
    Write-Host ('日志：' + $Script:LogFile)
    exit 1
}
