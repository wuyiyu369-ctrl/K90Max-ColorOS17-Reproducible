param(
    [switch]$CheckOnly,
    [string]$Serial,
    [switch]$NonInteractive,
    [string]$Mode,
    [string]$DataMode,
    [string]$RootMode,
    [string]$ModuleMode,
    [string]$CleanupMode
)

$ErrorActionPreference = 'Stop'
$Script:ExitCode = 1
$Script:PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:Images = Join-Path $Script:PackageRoot 'images'
$Script:Manifest = Join-Path $Script:PackageRoot 'SHA256SUMS.txt'
$Script:DriverInf = Join-Path $Script:PackageRoot 'drivers\usb_driver\android_winusb.inf'
$Script:LogDir = Join-Path $Script:PackageRoot 'logs'
$Script:LogFile = Join-Path $Script:LogDir ('flash_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.log')
$Script:IsMock = $false

if (-not (Test-Path -LiteralPath $Script:LogDir)) {
    New-Item -ItemType Directory -Path $Script:LogDir | Out-Null
}

function Write-Log([string]$Message) {
    $Line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Message
    [System.IO.File]::AppendAllText($Script:LogFile, $Line + [Environment]::NewLine, [Text.Encoding]::UTF8)
}

function Write-Title {
    Clear-Host
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' Redmi K90 Max / Prague  ColorOS 17 中文一键刷机向导' -ForegroundColor Cyan
    Write-Host ' 作者：哆啦A梦' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Stop-WithError([string]$Message) {
    Write-Log ('ERROR: ' + $Message)
    throw $Message
}

function Quote-Argument([string]$Value) {
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Join-Arguments([string[]]$Values) {
    $Result = ''
    foreach ($Value in $Values) {
        if ($Result.Length -gt 0) { $Result += ' ' }
        $Result += Quote-Argument $Value
    }
    return $Result
}

function Resolve-Tools {
    $MockRoot = [Environment]::GetEnvironmentVariable('K90_MOCK_ROOT')
    if ($MockRoot -and (Test-Path -LiteralPath $MockRoot)) {
        $Script:IsMock = $true
        $Script:Adb = Join-Path $MockRoot 'mock_adb.cmd'
        $Script:Fastboot = Join-Path $MockRoot 'mock_fastboot.cmd'
    } else {
        $Script:Adb = Join-Path $Script:PackageRoot 'platform-tools\adb.exe'
        $Script:Fastboot = Join-Path $Script:PackageRoot 'platform-tools\fastboot.exe'
    }
    if (-not (Test-Path -LiteralPath $Script:Adb)) { Stop-WithError ('缺少 ADB 工具：' + $Script:Adb) }
    if (-not (Test-Path -LiteralPath $Script:Fastboot)) { Stop-WithError ('缺少 Fastboot 工具：' + $Script:Fastboot) }
}

function Run-Tool([string]$Tool, [string[]]$Arguments, [switch]$AllowFailure, [int]$TimeoutSeconds) {
    if ($TimeoutSeconds -le 0) { $TimeoutSeconds = 120 }
    $Info = New-Object System.Diagnostics.ProcessStartInfo
    if ($Tool.ToLowerInvariant().EndsWith('.cmd') -or $Tool.ToLowerInvariant().EndsWith('.bat')) {
        $Info.FileName = $env:ComSpec
        $AllArgs = @('/d', '/s', '/c', $Tool) + $Arguments
        $Info.Arguments = Join-Arguments $AllArgs
    } else {
        $Info.FileName = $Tool
        $Info.Arguments = Join-Arguments $Arguments
    }
    $Info.UseShellExecute = $false
    $Info.CreateNoWindow = $true
    $Info.RedirectStandardOutput = $true
    $Info.RedirectStandardError = $true
    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $Info
    [void]$Process.Start()
    $StdOut = $Process.StandardOutput.ReadToEnd()
    $StdErr = $Process.StandardError.ReadToEnd()
    if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $Process.Kill() } catch {}
        Stop-WithError ('工具运行超过 ' + $TimeoutSeconds + ' 秒：' + $Tool)
    }
    $Text = ($StdOut + [Environment]::NewLine + $StdErr).Trim()
    Write-Log ('RUN: ' + $Info.FileName + ' ' + $Info.Arguments)
    if ($Text) { Write-Log ('OUT: ' + ($Text -replace '[\r\n]+', ' | ')) }
    if ((-not $AllowFailure) -and $Process.ExitCode -ne 0) {
        Stop-WithError ('工具执行失败，退出码 ' + $Process.ExitCode + '：' + $Text)
    }
    return $Text
}

function Get-Sha256([string]$Path) {
    $Provider = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
    $Stream = [System.IO.File]::OpenRead($Path)
    try {
        $Bytes = $Provider.ComputeHash($Stream)
        return ([BitConverter]::ToString($Bytes)).Replace('-', '').ToUpperInvariant()
    } finally {
        $Stream.Dispose()
        $Provider.Dispose()
    }
}

function Load-Manifest {
    if (-not (Test-Path -LiteralPath $Script:Manifest)) { Stop-WithError '缺少 SHA256SUMS.txt。' }
    $Map = @{}
    foreach ($Line in [System.IO.File]::ReadAllLines($Script:Manifest, [Text.Encoding]::UTF8)) {
        if ($Line -match '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') {
            $Relative = $Matches[2].Replace('/', '\')
            $Map[$Relative.ToLowerInvariant()] = $Matches[1].ToUpperInvariant()
        }
    }
    return $Map
}

function Test-Package {
    Write-Host '正在校验刷机包文件，第一次校验大镜像需要一些时间……' -ForegroundColor Yellow
    $Required = @(
        'images\super.img',
        'images\boot.img',
        'images\vendor_boot.img',
        'images\dtbo.img',
        'images\vbmeta.img',
        'images\vbmeta_system.img',
        'images\vbmeta_vendor.img',
        'images\init_boot_stock.img',
        'images\init_boot_kernelsu.img'
    )
    $ManifestMap = Load-Manifest
    foreach ($Relative in $Required) {
        $Full = Join-Path $Script:PackageRoot $Relative
        if (-not (Test-Path -LiteralPath $Full)) { Stop-WithError ('刷机包缺少文件：' + $Relative) }
        $Key = $Relative.ToLowerInvariant()
        if (-not $ManifestMap.ContainsKey($Key)) { Stop-WithError ('哈希清单缺少：' + $Relative) }
        $Actual = Get-Sha256 $Full
        if ($Actual -ne $ManifestMap[$Key]) { Stop-WithError ('SHA-256 校验失败：' + $Relative) }
        Write-Host ('  [通过] ' + $Relative)
    }
    Write-Host '全部镜像 SHA-256 校验通过。' -ForegroundColor Green
}

function Assert-SafePartition([string]$Partition) {
    $Blocked = @(
        'modem', 'md1img', 'persist', 'nvdata', 'nvcfg', 'nvram',
        'protect_f', 'protect_s', 'preloader', 'lk', 'md_sec',
        'seccfg', 'proinfo', 'boot_para'
    )
    foreach ($Name in $Blocked) {
        if ($Partition.ToLowerInvariant() -eq $Name) {
            Stop-WithError ('安全保护阻止刷写敏感分区：' + $Partition)
        }
    }
}

function Get-AdbDevices {
    $Text = Run-Tool $Script:Adb @('devices') -AllowFailure
    $Found = @()
    foreach ($Match in [regex]::Matches($Text, '(?m)^(\S+)\s+device\s*$')) {
        $Found += $Match.Groups[1].Value
    }
    return @($Found | Sort-Object -Unique)
}

function Get-FastbootDevices {
    $Text = Run-Tool $Script:Fastboot @('devices') -AllowFailure
    $Found = @()
    foreach ($Match in [regex]::Matches($Text, '(?m)^(\S+)\s+fastboot\s*$')) {
        $Found += $Match.Groups[1].Value
    }
    return @($Found | Sort-Object -Unique)
}

function Get-FastbootVar([string]$Name, [switch]$AllowMissing) {
    $Text = Run-Tool $Script:Fastboot @('-s', $Serial, 'getvar', $Name) -AllowFailure
    $Pattern = '(?m)^\s*(?:\(bootloader\)\s*)?' + [regex]::Escape($Name) + ':\s*(\S+)'
    $Found = [regex]::Match($Text, $Pattern)
    if (-not $Found.Success) {
        if ($AllowMissing) { return '' }
        Stop-WithError ('无法读取 fastboot 变量 ' + $Name + '。原始返回：' + $Text)
    }
    return $Found.Groups[1].Value
}

function Wait-Fastboot([int]$Seconds) {
    $Deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        $Devices = Get-FastbootDevices
        if ($Devices -contains $Serial) { return }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $Deadline)
    Stop-WithError ('在 ' + $Seconds + ' 秒内没有检测到手机的 Fastboot。请检查数据线和驱动。')
}

function Install-UsbDriver {
    if (-not (Test-Path -LiteralPath $Script:DriverInf)) {
        Stop-WithError ('刷机包内缺少 Google USB 驱动：' + $Script:DriverInf)
    }
    Write-Host '即将请求管理员权限安装 Google Android USB 驱动。' -ForegroundColor Yellow
    $PnP = Join-Path $env:WINDIR 'System32\pnputil.exe'
    if (-not (Test-Path -LiteralPath $PnP)) { Stop-WithError '系统缺少 pnputil.exe，无法自动安装驱动。' }
    $Major = [Environment]::OSVersion.Version.Major
    $Minor = [Environment]::OSVersion.Version.Minor
    if ($Major -eq 6 -and $Minor -le 1) {
        $Args = '-i -a ' + (Quote-Argument $Script:DriverInf)
    } else {
        $Args = '/add-driver ' + (Quote-Argument $Script:DriverInf) + ' /install'
    }
    try {
        $Process = Start-Process -FilePath $PnP -ArgumentList $Args -Verb RunAs -Wait -PassThru
    } catch {
        Stop-WithError ('驱动安装未完成：' + $_.Exception.Message)
    }
    if ($Process.ExitCode -ne 0) {
        Stop-WithError ('驱动安装失败，pnputil 退出码：' + $Process.ExitCode)
    }
    Write-Host '驱动安装命令已完成。请重新插拔数据线，然后输入 2 重试。' -ForegroundColor Green
}

function Select-Device {
    if ($Serial -and $Serial -notmatch '^[a-zA-Z0-9._:-]+$') { Stop-WithError '设备序列号格式异常。' }
    while ($true) {
        $AdbDevices = Get-AdbDevices
        $FastDevices = Get-FastbootDevices
        $All = @($AdbDevices + $FastDevices | Sort-Object -Unique)
        if ($Serial) {
            if ($All -contains $Serial) { return }
            Stop-WithError ('没有找到指定设备：' + $Serial)
        }
        if ($All.Count -eq 1) {
            $Script:Serial = $All[0]
            $global:Serial = $Script:Serial
            return
        }
        if ($All.Count -gt 1) { Stop-WithError '检测到多台手机。请只连接一台手机后重试。' }
        if ($NonInteractive) { Stop-WithError '没有检测到 ADB 或 Fastboot 设备。' }
        Write-Host ''
        Write-Host '没有检测到手机。' -ForegroundColor Red
        Write-Host '  1 = 安装/更新 Google USB 驱动'
        Write-Host '  2 = 已处理好，重新检测'
        Write-Host '  0 = 退出'
        $Choice = Read-Host '请输入'
        if ($Choice -eq '1') { Install-UsbDriver }
        elseif ($Choice -eq '2') { continue }
        elseif ($Choice -eq '0') { exit 0 }
    }
}

function Read-Choice([string]$Prompt, [string[]]$Allowed, [string]$Preset) {
    if ($Preset) {
        if ($Allowed -notcontains $Preset) { Stop-WithError ('参数值无效：' + $Preset) }
        return $Preset
    }
    if ($NonInteractive) { Stop-WithError ('非交互模式缺少选择参数：' + $Prompt) }
    while ($true) {
        $Value = (Read-Host $Prompt).Trim()
        if ($Allowed -contains $Value) { return $Value }
        Write-Host '输入无效，请重新输入。' -ForegroundColor Yellow
    }
}

function Disable-ModulesIfRequested([string]$Choice) {
    if ($Choice -ne '1') { return }
    $AdbDevices = Get-AdbDevices
    if ($AdbDevices -notcontains $Serial) {
        Write-Host '手机当前不在系统内，无法自动禁用模块；继续前请确认模块已关闭。' -ForegroundColor Yellow
        return
    }
    $Command = 'for d in /data/adb/modules/*; do [ -d "$d" ] && touch "$d/disable"; done'
    $Text = Run-Tool $Script:Adb @('-s', $Serial, 'shell', 'su', '-c', $Command) -AllowFailure
    if ($Text -match 'not found|denied|inaccessible') {
        Write-Host '自动禁用模块没有成功，可能手机没有 Root；请手动关闭模块。' -ForegroundColor Yellow
    } else {
        Write-Host '已请求禁用 /data/adb/modules 下的模块。' -ForegroundColor Green
    }
}

function Apply-SystemSettings {
    $AdbDevices = Get-AdbDevices
    if ($AdbDevices -notcontains $Serial) { return }
    $Vendor = Run-Tool $Script:Adb @('-s', $Serial, 'shell', 'getprop', 'ro.product.vendor.device') -AllowFailure
    if ($Mode -eq '1' -and $Vendor.Trim() -ne 'prague') {
        Stop-WithError '系统更新模式只允许当前底层为 prague 的设备。若仍是小米系统，请选择全新刷入。'
    }
    Run-Tool $Script:Adb @('-s', $Serial, 'shell', 'settings', 'put', 'global', 'stay_on_while_plugged_in', '0') -AllowFailure | Out-Null
    Run-Tool $Script:Adb @('-s', $Serial, 'shell', 'settings', 'put', 'global', 'oplus_battery_agent_debug_force_entry', '1') -AllowFailure | Out-Null
    Run-Tool $Script:Adb @('-s', $Serial, 'shell', 'settings', 'delete', 'system', 'brightness_drag_point') -AllowFailure | Out-Null
    Run-Tool $Script:Adb @('-s', $Serial, 'shell', 'settings', 'delete', 'system', 'screen_auto_brightness_adj') -AllowFailure | Out-Null
    Write-Host '已写入自动熄屏、AI 电池入口并清理旧亮度学习点。' -ForegroundColor Green
}

function Enter-Bootloader {
    $AdbDevices = Get-AdbDevices
    if ($AdbDevices -contains $Serial) {
        Write-Host '检测到手机处于系统状态，正在自动重启到 Fastboot……' -ForegroundColor Yellow
        Run-Tool $Script:Adb @('-s', $Serial, 'reboot', 'bootloader') | Out-Null
        Wait-Fastboot 120
    }
    $FastDevices = Get-FastbootDevices
    if ($FastDevices -notcontains $Serial) { Stop-WithError '手机没有进入 Fastboot。' }
    $IsUserspace = Get-FastbootVar 'is-userspace' -AllowMissing
    if ($IsUserspace -eq 'yes') {
        Write-Host '当前处于 fastbootd，正在切回 bootloader fastboot 刷启动链……' -ForegroundColor Yellow
        Run-Tool $Script:Fastboot @('-s', $Serial, 'reboot', 'bootloader') | Out-Null
        Wait-Fastboot 120
    }
    $Unlocked = Get-FastbootVar 'unlocked' -AllowMissing
    if ($Unlocked -and $Unlocked -ne 'yes') { Stop-WithError 'Bootloader 未解锁，停止刷写。' }
    $Product = Get-FastbootVar 'product' -AllowMissing
    if ($Product -and $Product -ne 'prague') { Stop-WithError ('设备代号不是 prague：' + $Product) }
}

function Flash-Partition([string]$Partition, [string]$RelativeImage) {
    Assert-SafePartition $Partition
    $Image = Join-Path $Script:PackageRoot $RelativeImage
    Write-Host ('正在刷写 ' + $Partition + '，请勿拔线……') -ForegroundColor Yellow
    if ($Script:IsMock) {
        $Result = Run-Tool $Script:Fastboot @('-s', $Serial, 'flash', $Partition, $Image) -AllowFailure -TimeoutSeconds 600
        if ($Result -match 'FAILED|MOCK_FAIL') { Stop-WithError ('刷写 ' + $Partition + ' 失败：' + $Result) }
    } else {
        & $Script:Fastboot -s $Serial flash $Partition $Image
        if ($LASTEXITCODE -ne 0) { Stop-WithError ('刷写 ' + $Partition + ' 失败，退出码：' + $LASTEXITCODE) }
    }
}

function Enter-Fastbootd {
    Write-Host '正在进入 fastbootd，手机屏幕会显示 Fastbootd……' -ForegroundColor Yellow
    Run-Tool $Script:Fastboot @('-s', $Serial, 'reboot', 'fastboot') | Out-Null
    Wait-Fastboot 120
    $IsUserspace = Get-FastbootVar 'is-userspace'
    if ($IsUserspace -ne 'yes') { Stop-WithError '未能进入 fastbootd，停止刷写 super。' }
}

function Flash-Super {
    Flash-Partition 'super' 'images\super.img'
}

function Schedule-PackageCleanup {
    $ExpectedLeaf = 'K90Max_ColorOS17_Prague_Stage48_OneClick_20261106'
    $ResolvedRoot = [System.IO.Path]::GetFullPath($Script:PackageRoot).TrimEnd('\')
    if ((Split-Path -Leaf $ResolvedRoot) -ne $ExpectedLeaf) {
        Stop-WithError ('为防止误删，目录名称不符合预期，未安排自动清理：' + $ResolvedRoot)
    }
    if ($ResolvedRoot.Length -lt 20 -or -not (Test-Path -LiteralPath (Join-Path $ResolvedRoot 'images\super.img')) -or
        -not (Test-Path -LiteralPath (Join-Path $ResolvedRoot 'START_FLASH.cmd'))) {
        Stop-WithError '为防止误删，刷机包目录安全校验未通过。'
    }

    $Flag = Join-Path $ResolvedRoot 'DELETE_AFTER_FLASH.flag'
    [System.IO.File]::WriteAllText($Flag, 'delete after successful flash', [Text.Encoding]::ASCII)
    $CleanupScript = Join-Path $env:TEMP ('K90_cleanup_' + [Guid]::NewGuid().ToString('N') + '.ps1')
    $EscapedRoot = $ResolvedRoot.Replace("'", "''")
    $Lines = @(
        "`$target = '$EscapedRoot'",
        "`$deadline = [DateTime]::UtcNow.AddMinutes(5)",
        "do {",
        "  Start-Sleep -Seconds 2",
        "  try { Remove-Item -LiteralPath `$target -Recurse -Force -ErrorAction Stop; break } catch {}",
        "} while ([DateTime]::UtcNow -lt `$deadline)",
        "Remove-Item -LiteralPath `$MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue"
    )
    [System.IO.File]::WriteAllLines($CleanupScript, $Lines, (New-Object Text.UTF8Encoding($true)))
    Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $CleanupScript) -WindowStyle Hidden | Out-Null
    Write-Host '已安排在本窗口关闭后删除解压出的刷机目录；原始 EXE 和数据分卷会保留。' -ForegroundColor Green
}

try {
    Write-Title
    Write-Host '刷机前必须确认：' -ForegroundColor Yellow
    Write-Host '  1. 使用原厂或质量可靠、没有损坏的数据线。'
    Write-Host '  2. 手机电量高于 30%，电脑供电稳定。'
    Write-Host '  3. 刷写关键分区期间绝对不要拔线。'
    Write-Host '  4. 已备份重要资料；任何刷机都有风险。'
    Write-Host ''
    Write-Host '本刷机包明确禁止刷写 modem、persist、nvdata、nvcfg、protect*、preloader。' -ForegroundColor Red
    Write-Host '脚本也不会刷写或擦除这些敏感分区。' -ForegroundColor Red
    Write-Host ''

    if (-not $NonInteractive) {
        $Confirm = (Read-Host '理解以上内容并继续，请输入 OK').Trim().ToUpperInvariant()
        if ($Confirm -ne 'OK') { exit 0 }
    }

    Resolve-Tools
    Test-Package
    if ($CheckOnly) {
        Write-Host '仅校验模式完成，没有连接或改动手机。' -ForegroundColor Green
        $Script:ExitCode = 0
        exit 0
    }

    Write-Host ''
    Write-Host '请选择刷机方式：' -ForegroundColor Cyan
    Write-Host '  1 = 系统更新/修复（保留应用和数据）'
    Write-Host '  2 = 全新刷入（适合从小米系统或其他系统转入）'
    $Mode = Read-Choice '请输入 1 或 2' @('1', '2') $Mode

    if ($Mode -eq '1') {
        $DataMode = '1'
    } else {
        Write-Host ''
        Write-Host '全新刷入的数据选项：'
        Write-Host '  1 = 尝试保留数据（跨系统可能存在兼容问题）'
        Write-Host '  2 = 格式化数据（最干净，会删除手机全部用户数据）'
        $DataMode = Read-Choice '请输入 1 或 2' @('1', '2') $DataMode
        if ($DataMode -eq '2' -and (-not $NonInteractive)) {
            $DeleteConfirm = (Read-Host '此操作会删除全部用户数据，确认请输入 DELETE').Trim()
            if ($DeleteConfirm -cne 'DELETE') { exit 0 }
        }
    }

    Write-Host ''
    Write-Host '是否保留 Root：'
    Write-Host '  1 = 不要 Root，刷原厂 init_boot'
    Write-Host '  2 = 需要 Root，刷 KernelSU init_boot'
    $RootMode = Read-Choice '请输入 1 或 2' @('1', '2') $RootMode

    Write-Host ''
    Write-Host '更新前模块处理：'
    Write-Host '  1 = 尝试自动禁用 KSU/LSPosed 模块（推荐）'
    Write-Host '  2 = 不处理，我已手动关闭'
    $ModuleMode = Read-Choice '请输入 1 或 2' @('1', '2') $ModuleMode

    Select-Device
    Write-Host ('已识别设备：' + $Serial) -ForegroundColor Green
    Disable-ModulesIfRequested $ModuleMode
    Apply-SystemSettings
    Enter-Bootloader

    Write-Host ''
    Write-Host '开始刷写启动链。刷写期间不要拔线。' -ForegroundColor Yellow
    Flash-Partition 'boot' 'images\boot.img'
    Flash-Partition 'vendor_boot' 'images\vendor_boot.img'
    Flash-Partition 'dtbo' 'images\dtbo.img'
    Flash-Partition 'vbmeta' 'images\vbmeta.img'
    Flash-Partition 'vbmeta_system' 'images\vbmeta_system.img'
    Flash-Partition 'vbmeta_vendor' 'images\vbmeta_vendor.img'
    if ($RootMode -eq '2') {
        Flash-Partition 'init_boot' 'images\init_boot_kernelsu.img'
    } else {
        Flash-Partition 'init_boot' 'images\init_boot_stock.img'
    }

    Enter-Fastbootd
    Write-Host ''
    Write-Host '正在刷写最大的系统镜像。Fastboot 会显示 sparse 分块进度，例如 1/46 到 46/46。' -ForegroundColor Cyan
    Flash-Super

    if ($DataMode -eq '2') {
        Write-Host '正在按你的选择格式化 userdata/metadata……' -ForegroundColor Red
        if ($Script:IsMock) {
            $WipeText = Run-Tool $Script:Fastboot @('-s', $Serial, '-w') -AllowFailure -TimeoutSeconds 600
            if ($WipeText -match 'FAILED|MOCK_FAIL') { Stop-WithError ('格式化失败：' + $WipeText) }
        } else {
            & $Script:Fastboot -s $Serial -w
            if ($LASTEXITCODE -ne 0) { Stop-WithError ('格式化失败，退出码：' + $LASTEXITCODE) }
        }
    }

    Run-Tool $Script:Fastboot @('-s', $Serial, 'reboot') | Out-Null
    Write-Host ''
    Write-Host '刷写完成，手机正在重启。第一次开机时间可能较长。' -ForegroundColor Green
    if ($DataMode -eq '1') { Write-Host '本次没有执行格式化数据。' -ForegroundColor Green }
    if ($RootMode -eq '2') { Write-Host '已选择 KernelSU Root init_boot。' }
    else { Write-Host '已选择原厂无 Root init_boot。' }
    Write-Host ''
    Write-Host '刷机已成功，是否保留本次解压出的约 13GB 刷机文件？'
    Write-Host '  1 = 保留，方便以后重刷'
    Write-Host '  2 = 自动删除解压文件，只保留原始 EXE 和数据分卷'
    if ($NonInteractive -and -not $CleanupMode) { $CleanupMode = '1' }
    $CleanupMode = Read-Choice '请输入 1 或 2' @('1', '2') $CleanupMode
    if ($CleanupMode -eq '2') { Schedule-PackageCleanup }
    else { Write-Host '已保留解压后的刷机文件。' -ForegroundColor Green }
    Write-Host ('日志已保存到：' + $Script:LogFile)
    $Script:ExitCode = 0
} catch {
    Write-Host ''
    Write-Host ('刷机向导已停止：' + $_.Exception.Message) -ForegroundColor Red
    Write-Host '不要反复拔线或盲目格式化。请保留本窗口和 logs 文件夹。' -ForegroundColor Yellow
    Write-Host ('日志位置：' + $Script:LogFile)
    $Script:ExitCode = 1
}

exit $Script:ExitCode
