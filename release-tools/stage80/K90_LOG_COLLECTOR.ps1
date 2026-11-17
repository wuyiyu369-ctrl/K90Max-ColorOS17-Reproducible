param(
    [ValidateSet('Menu','Live','History')]
    [string]$Mode = 'Menu',
    [string]$Serial,
    [int]$LiveSeconds = 0,
    [switch]$SkipBugreport
)

$ErrorActionPreference = 'Continue'
$Script:Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Script:Adb = Join-Path $Script:Root 'platform-tools\adb.exe'
$Script:SevenZip = Join-Path $Script:Root 'tools\7z.exe'
$Script:Session = $null
$Script:RunLog = $null
$Script:DeviceSerial = $null
$Script:AdbIsMock = $false

function Write-Title {
    try { Clear-Host } catch {}
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ' Redmi K90 Max 中文一键抓日志工具' -ForegroundColor Cyan
    Write-Host ' 作者：哆啦A梦' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Write-RunLog([string]$Text) {
    if (-not $Script:RunLog) { return }
    $Line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $Text
    [IO.File]::AppendAllText($Script:RunLog, $Line + [Environment]::NewLine, (New-Object Text.UTF8Encoding($true)))
}

function Quote-Arg([string]$Value) {
    if ($null -eq $Value) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Join-Args([string[]]$Values) {
    $Result = ''
    foreach ($Value in $Values) {
        if ($Result.Length -gt 0) { $Result += ' ' }
        $Result += Quote-Arg $Value
    }
    return $Result
}

function Resolve-Tools {
    $Mock = [Environment]::GetEnvironmentVariable('K90_LOG_MOCK_ADB')
    if ($Mock) {
        $Script:Adb = $Mock
        $Script:AdbIsMock = $true
    }
    if (-not (Test-Path -LiteralPath $Script:Adb)) {
        throw ('缺少 ADB：' + $Script:Adb)
    }
    if (-not (Test-Path -LiteralPath $Script:SevenZip)) {
        throw ('缺少压缩工具：' + $Script:SevenZip)
    }
}

function Invoke-AdbText([string[]]$Arguments) {
    $Output = & $Script:Adb @Arguments 2>&1 | Out-String
    Write-RunLog ('ADB ' + (Join-Args $Arguments) + ' => ' + $LASTEXITCODE)
    return $Output.TrimEnd()
}

function Invoke-AdbFile([string]$Name, [string[]]$Arguments) {
    $Path = Join-Path $Script:Session $Name
    $Header = @(
        '# K90 Max log collector',
        ('# Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')),
        ('# Command: adb ' + (Join-Args $Arguments)),
        ''
    ) -join [Environment]::NewLine
    [IO.File]::WriteAllText($Path, $Header, (New-Object Text.UTF8Encoding($true)))
    try {
        & $Script:Adb @Arguments 2>&1 | Out-File -LiteralPath $Path -Encoding utf8 -Append -Width 4096
        $Code = $LASTEXITCODE
    } catch {
        $_ | Out-String | Out-File -LiteralPath $Path -Encoding utf8 -Append
        $Code = 999
    }
    Write-RunLog ('SAVE ' + $Name + ' <= adb ' + (Join-Args $Arguments) + ' => ' + $Code)
    return $Code
}

function Get-Device {
    & $Script:Adb start-server 2>&1 | Out-Null
    $Text = Invoke-AdbText @('devices','-l')
    $Lines = @($Text -split "`r?`n" | Where-Object { $_ -match '^([^\s]+)\s+device(?:\s|$)' })
    if ($Serial) {
        foreach ($Line in $Lines) {
            if ($Line -match '^([^\s]+)\s+') {
                if ($Matches[1] -eq $Serial) { return $Serial }
            }
        }
        throw ('没有找到指定设备：' + $Serial)
    }
    if ($Lines.Count -eq 0) {
        Write-Host '没有检测到已授权的 ADB 设备。' -ForegroundColor Yellow
        Write-Host '请连接手机、打开 USB 调试，并在手机上允许这台电脑调试。'
        Write-Host '完成后按回车重新检测，输入 Q 退出。'
        $Answer = Read-Host
        if ($Answer -match '^[Qq]$') { throw '用户取消。' }
        $Text = Invoke-AdbText @('devices','-l')
        $Lines = @($Text -split "`r?`n" | Where-Object { $_ -match '^([^\s]+)\s+device(?:\s|$)' })
    }
    if ($Lines.Count -eq 0) { throw '仍未检测到已授权设备。' }
    if ($Lines.Count -gt 1) {
        Write-Host '检测到多台设备，请输入要抓取的序号：' -ForegroundColor Yellow
        for ($i = 0; $i -lt $Lines.Count; $i++) { Write-Host (('{0}. ' -f ($i + 1)) + $Lines[$i]) }
        $Choice = Read-Host
        $Index = 0
        if (-not [int]::TryParse($Choice, [ref]$Index) -or $Index -lt 1 -or $Index -gt $Lines.Count) {
            throw '设备序号无效。'
        }
        $Line = $Lines[$Index - 1]
    } else {
        $Line = $Lines[0]
    }
    if ($Line -notmatch '^([^\s]+)\s+') { throw '无法解析设备序列号。' }
    return $Matches[1]
}

function New-Session([string]$Kind) {
    $LogRoot = Join-Path $Script:Root 'logs'
    if (-not (Test-Path -LiteralPath $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot | Out-Null }
    $Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Script:Session = Join-Path $LogRoot ('K90_' + $Kind + '_' + $Stamp)
    New-Item -ItemType Directory -Path $Script:Session | Out-Null
    $Script:RunLog = Join-Path $Script:Session 'collector_run.log'
    Write-RunLog ('SESSION START: ' + $Script:Session)
}

function Get-BaseInfo([string]$Prefix) {
    Write-Host ('正在保存' + $Prefix + '设备状态……') -ForegroundColor DarkCyan
    Invoke-AdbFile ($Prefix + '_getprop.txt') @('-s',$Script:DeviceSerial,'shell','getprop') | Out-Null
    Invoke-AdbFile ($Prefix + '_battery.txt') @('-s',$Script:DeviceSerial,'shell','dumpsys','battery') | Out-Null
    Invoke-AdbFile ($Prefix + '_thermalservice.txt') @('-s',$Script:DeviceSerial,'shell','dumpsys','thermalservice') | Out-Null
    Invoke-AdbFile ($Prefix + '_cpuinfo.txt') @('-s',$Script:DeviceSerial,'shell','dumpsys','cpuinfo') | Out-Null
    Invoke-AdbFile ($Prefix + '_meminfo.txt') @('-s',$Script:DeviceSerial,'shell','cat','/proc/meminfo') | Out-Null
    Invoke-AdbFile ($Prefix + '_top.txt') @('-s',$Script:DeviceSerial,'shell','top','-b','-n','1','-o','PID,USER,PR,NI,VIRT,RES,SHR,S,%CPU,%MEM,TIME+,ARGS') | Out-Null
    Invoke-AdbFile ($Prefix + '_activity.txt') @('-s',$Script:DeviceSerial,'shell','dumpsys','activity','activities') | Out-Null
    Invoke-AdbFile ($Prefix + '_window.txt') @('-s',$Script:DeviceSerial,'shell','dumpsys','window','windows') | Out-Null
    Invoke-AdbFile ($Prefix + '_services.txt') @('-s',$Script:DeviceSerial,'shell','service','list') | Out-Null
    Invoke-AdbFile ($Prefix + '_processes.txt') @('-s',$Script:DeviceSerial,'shell','ps','-A','-T','-Z') | Out-Null
    Invoke-AdbFile ($Prefix + '_mounts.txt') @('-s',$Script:DeviceSerial,'shell','mount') | Out-Null
    Invoke-AdbFile ($Prefix + '_disk_usage.txt') @('-s',$Script:DeviceSerial,'shell','df','-h') | Out-Null
    Invoke-AdbFile ($Prefix + '_pressure.txt') @('-s',$Script:DeviceSerial,'shell','sh','-c','for f in /proc/pressure/*; do echo "===== $f ====="; cat "$f" 2>&1; done') | Out-Null
    Invoke-AdbFile ($Prefix + '_k90_state.txt') @('-s',$Script:DeviceSerial,'shell','sh','-c',@'
echo "=== date / uptime ==="
date; uptime
echo "=== foreground ==="
dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" | head -20
echo "=== CPU policies ==="
for p in /sys/devices/system/cpu/cpufreq/policy*; do echo "[$p]"; cat "$p/scaling_cur_freq" "$p/scaling_min_freq" "$p/scaling_max_freq" "$p/cpuinfo_max_freq" 2>/dev/null; done
echo "=== thermal ==="
for z in /sys/class/thermal/thermal_zone*; do n=$(cat "$z/type" 2>/dev/null); t=$(cat "$z/temp" 2>/dev/null); echo "$z $n $t"; done
echo "=== fan candidates ==="
for f in /sys/class/thermal/cooling_device* /sys/devices/platform/*fan* /proc/*fan*; do [ -e "$f" ] && ls -ld "$f"; done
echo "=== performance nodes ==="
cat /proc/powerhal_cpu_ctrl/perfserv_freq 2>/dev/null
cat /sys/class/devfreq/*/cur_freq 2>/dev/null
getprop | grep -iE "sconfig|perf|thermal|fan|charge|battery"
'@) | Out-Null
}

function Get-ComprehensiveSystemLogs([string]$Prefix) {
    Write-Host '正在抓取全功能系统状态（显示、相机、音频、生物识别、网络、存储和性能等）……' -ForegroundColor DarkCyan
    $Items = @(
        @('activity_processes','dumpsys','activity','processes'),
        @('activity_services','dumpsys','activity','services'),
        @('activity_broadcasts','dumpsys','activity','broadcasts'),
        @('activity_provider','dumpsys','activity','providers'),
        @('package_manager','dumpsys','package'),
        @('package_features','pm','list','features'),
        @('package_libraries','pm','list','libraries'),
        @('display','dumpsys','display'),
        @('surfaceflinger','dumpsys','SurfaceFlinger'),
        @('window_policy','dumpsys','window','policy'),
        @('input','dumpsys','input'),
        @('sensorservice','dumpsys','sensorservice'),
        @('audio','dumpsys','audio'),
        @('media_audio_flinger','dumpsys','media.audio_flinger'),
        @('media_camera','dumpsys','media.camera'),
        @('media_camera_proxy','dumpsys','media.camera.proxy'),
        @('fingerprint','dumpsys','fingerprint'),
        @('face','dumpsys','face'),
        @('biometric','dumpsys','biometric'),
        @('nfc','dumpsys','nfc'),
        @('phone','dumpsys','phone'),
        @('telephony_registry','dumpsys','telephony.registry'),
        @('telecom','dumpsys','telecom'),
        @('ims','dumpsys','ims'),
        @('wifi','dumpsys','wifi'),
        @('connectivity','dumpsys','connectivity'),
        @('netd','dumpsys','netd'),
        @('network_management','dumpsys','network_management'),
        @('bluetooth_manager','dumpsys','bluetooth_manager'),
        @('usb','dumpsys','usb'),
        @('power','dumpsys','power'),
        @('batteryproperties','dumpsys','batteryproperties'),
        @('battery_stats','dumpsys','batterystats'),
        @('deviceidle','dumpsys','deviceidle'),
        @('alarm','dumpsys','alarm'),
        @('jobscheduler','dumpsys','jobscheduler'),
        @('thermal','dumpsys','thermalservice'),
        @('meminfo_all','dumpsys','meminfo','-a'),
        @('procstats','dumpsys','procstats','--full-details'),
        @('gfxinfo','dumpsys','gfxinfo'),
        @('stats','dumpsys','stats'),
        @('storaged','dumpsys','storaged'),
        @('diskstats','dumpsys','diskstats'),
        @('vold','dumpsys','vold'),
        @('mount','dumpsys','mount'),
        @('update_engine','dumpsys','android.os.UpdateEngineService'),
        @('rollback','dumpsys','rollback'),
        @('dropbox','dumpsys','dropbox','--print')
    )
    foreach ($Item in $Items) {
        $Name = $Item[0]
        $Args = @('-s',$Script:DeviceSerial,'shell') + @($Item[1..($Item.Count - 1)])
        Invoke-AdbFile ($Prefix + '_' + $Name + '.txt') $Args | Out-Null
    }
    Invoke-AdbFile ($Prefix + '_settings_global.txt') @('-s',$Script:DeviceSerial,'shell','settings','list','global') | Out-Null
    Invoke-AdbFile ($Prefix + '_settings_system.txt') @('-s',$Script:DeviceSerial,'shell','settings','list','system') | Out-Null
    Invoke-AdbFile ($Prefix + '_settings_secure.txt') @('-s',$Script:DeviceSerial,'shell','settings','list','secure') | Out-Null
    Invoke-AdbFile ($Prefix + '_device_config.txt') @('-s',$Script:DeviceSerial,'shell','device_config','list') | Out-Null
    Invoke-AdbFile ($Prefix + '_cmd_services.txt') @('-s',$Script:DeviceSerial,'shell','cmd','-l') | Out-Null
    Invoke-AdbFile ($Prefix + '_lshal.txt') @('-s',$Script:DeviceSerial,'shell','lshal') | Out-Null
    Invoke-AdbFile ($Prefix + '_vintf.txt') @('-s',$Script:DeviceSerial,'shell','sh','-c','for f in /vendor/etc/vintf/* /odm/etc/vintf/* /system/etc/vintf/*; do [ -f "$f" ] && { echo "===== $f ====="; cat "$f"; }; done') | Out-Null
    Invoke-AdbFile ($Prefix + '_kernel_proc.txt') @('-s',$Script:DeviceSerial,'shell','sh','-c',@'
for f in \
 /proc/version /proc/cmdline /proc/bootconfig /proc/cpuinfo /proc/meminfo \
 /proc/interrupts /proc/vmstat /proc/zoneinfo /proc/slabinfo /proc/diskstats \
 /proc/filesystems /proc/partitions /proc/mounts /proc/modules; do
  echo "===== $f ====="; cat "$f" 2>&1
done
'@) | Out-Null
    Invoke-AdbFile ($Prefix + '_hardware_nodes.txt') @('-s',$Script:DeviceSerial,'shell','sh','-c',@'
echo "=== CPU ==="
find /sys/devices/system/cpu/cpufreq -maxdepth 3 -type f 2>/dev/null | sort
echo "=== DEVFREQ GPU DDR UFS ==="
find /sys/class/devfreq /sys/devices/platform -maxdepth 5 -type f 2>/dev/null | grep -iE "(freq|gpu|mali|ged|ddr|dram|ufs)" | sort
echo "=== POWER SUPPLY ==="
for f in /sys/class/power_supply/*/*; do [ -f "$f" ] && { echo -n "$f="; cat "$f" 2>/dev/null; }; done
echo "=== THERMAL AND COOLING ==="
find /sys/class/thermal -maxdepth 3 -type f 2>/dev/null | sort
echo "=== INPUT AND TOUCH ==="
cat /proc/bus/input/devices 2>/dev/null
find /sys -maxdepth 6 -type f 2>/dev/null | grep -iE "(touch|fod|finger|vibrator|haptic|fan)" | head -5000
'@) | Out-Null
}

function Start-AdbCapture([string]$Name, [string[]]$Arguments) {
    $Out = Join-Path $Script:Session ($Name + '.txt')
    $Err = Join-Path $Script:Session ($Name + '_stderr.txt')
    if ($Script:Adb.ToLowerInvariant().EndsWith('.cmd') -or $Script:Adb.ToLowerInvariant().EndsWith('.bat')) {
        $Tool = $env:ComSpec
        $ToolArgs = Join-Args (@('/d','/s','/c',$Script:Adb) + $Arguments)
    } else {
        $Tool = $Script:Adb
        $ToolArgs = Join-Args $Arguments
    }
    $Process = Start-Process -FilePath $Tool -ArgumentList $ToolArgs -WindowStyle Hidden -RedirectStandardOutput $Out -RedirectStandardError $Err -PassThru
    Write-RunLog ('LIVE START: ' + $Tool + ' ' + $ToolArgs + ' PID=' + $Process.Id)
    return New-Object PSObject -Property @{ Process=$Process; Name=$Name; OutPath=$Out; ErrPath=$Err }
}

function Stop-Captures([object[]]$Captures) {
    foreach ($Capture in $Captures) {
        try { if (-not $Capture.Process.HasExited) { $Capture.Process.Kill() } } catch {}
        try { $Capture.Process.WaitForExit(3000) | Out-Null } catch {}
        Write-RunLog ('LIVE STOP: ' + $Capture.Name + ' PID=' + $Capture.Process.Id)
        try { $Capture.Process.Dispose() } catch {}
    }
}

function Get-History([switch]$IncludeFullDumpsys) {
    Write-Host '正在读取当前缓存和此前残留日志，部分目录无权限属于正常情况……' -ForegroundColor DarkCyan
    Invoke-AdbFile 'logcat_current_all.txt' @('-s',$Script:DeviceSerial,'logcat','-b','all','-d','-v','threadtime') | Out-Null
    Invoke-AdbFile 'logcat_previous_boot.txt' @('-s',$Script:DeviceSerial,'logcat','-L','-b','all','-d','-v','threadtime') | Out-Null
    Invoke-AdbFile 'kernel_dmesg.txt' @('-s',$Script:DeviceSerial,'shell','dmesg','-T') | Out-Null
    Invoke-AdbFile 'kernel_last_kmsg.txt' @('-s',$Script:DeviceSerial,'shell','cat','/proc/last_kmsg') | Out-Null
    Invoke-AdbFile 'dropbox_all.txt' @('-s',$Script:DeviceSerial,'shell','dumpsys','dropbox','--print') | Out-Null
    Invoke-AdbFile 'activity_exit_info.txt' @('-s',$Script:DeviceSerial,'shell','dumpsys','activity','exit-info') | Out-Null
    Invoke-AdbFile 'batterystats.txt' @('-s',$Script:DeviceSerial,'shell','dumpsys','batterystats') | Out-Null
    Invoke-AdbFile 'package_list.txt' @('-s',$Script:DeviceSerial,'shell','pm','list','packages','-f','-U') | Out-Null
    Invoke-AdbFile 'pstore_listing.txt' @('-s',$Script:DeviceSerial,'shell','ls','-la','/sys/fs/pstore') | Out-Null
    Invoke-AdbFile 'anr_listing.txt' @('-s',$Script:DeviceSerial,'shell','ls','-la','/data/anr') | Out-Null
    Invoke-AdbFile 'tombstones_listing.txt' @('-s',$Script:DeviceSerial,'shell','ls','-la','/data/tombstones') | Out-Null
    Invoke-AdbFile 'recovery_update_logs.txt' @('-s',$Script:DeviceSerial,'shell','sh','-c',@'
for f in \
 /cache/recovery/last_log /cache/recovery/log /cache/recovery/last_install \
 /metadata/ota/* /data/misc/update_engine_log/* /data/ota_package/*; do
  [ -e "$f" ] || continue
  echo "===== $f ====="
  if [ -f "$f" ]; then cat "$f" 2>&1; else ls -la "$f" 2>&1; fi
done
'@) | Out-Null
    Invoke-AdbFile 'phone_local_log_directories.txt' @('-s',$Script:DeviceSerial,'shell','sh','-c',@'
for p in \
  /data/system/dropbox \
  /data/anr \
  /data/tombstones \
  /data/vendor/mtklog \
  /data/debuglogger \
  /sdcard/mtklog \
  /sdcard/debuglogger \
  /sdcard/MIUI/debug_log \
  /sdcard/oplus_log \
  /sdcard/ColorOS/Log; do
  echo "===== $p ====="
  ls -la "$p" 2>&1
done
'@) | Out-Null
    $Pstore = Join-Path $Script:Session 'pstore'
    New-Item -ItemType Directory -Force -Path $Pstore | Out-Null
    & $Script:Adb -s $Script:DeviceSerial pull /sys/fs/pstore $Pstore 2>&1 | Out-File -LiteralPath (Join-Path $Script:Session 'pstore_pull.txt') -Encoding utf8
    $PhoneLogs = Join-Path $Script:Session 'phone_local_logs'
    New-Item -ItemType Directory -Force -Path $PhoneLogs | Out-Null
    $ReadableLogDirs = @('/sdcard/mtklog','/sdcard/debuglogger','/sdcard/MIUI/debug_log','/sdcard/oplus_log','/sdcard/ColorOS/Log')
    foreach ($Remote in $ReadableLogDirs) {
        $SafeName = ($Remote.Trim('/') -replace '[/\\:]','_')
        $PullLog = Join-Path $Script:Session ('pull_' + $SafeName + '.txt')
        & $Script:Adb -s $Script:DeviceSerial pull $Remote (Join-Path $PhoneLogs $SafeName) 2>&1 | Out-File -LiteralPath $PullLog -Encoding utf8
        Write-RunLog ('PHONE LOCAL LOG PULL: ' + $Remote + ' => ' + $LASTEXITCODE)
    }
    if ($IncludeFullDumpsys) {
        Invoke-AdbFile 'dumpsys_all_services.txt' @('-s',$Script:DeviceSerial,'shell','dumpsys') | Out-Null
    }
}

function Get-Bugreport {
    if ($SkipBugreport) {
        Write-RunLog 'BUGREPORT SKIPPED BY PARAMETER'
        return
    }
    if ($Script:AdbIsMock) {
        [IO.File]::WriteAllText((Join-Path $Script:Session 'bugreport_mock.txt'),'Mock bugreport completed.',[Text.Encoding]::UTF8)
        return
    }
    $Bug = Join-Path $Script:Session 'bugreport.zip'
    Write-Host '正在生成 Android 完整 bugreport，通常需要 2 至 10 分钟，请保持连接……' -ForegroundColor Yellow
    & $Script:Adb -s $Script:DeviceSerial bugreport $Bug 2>&1 | Tee-Object -FilePath (Join-Path $Script:Session 'bugreport_progress.txt')
    Write-RunLog ('BUGREPORT EXIT: ' + $LASTEXITCODE)
}

function Compress-Session {
    $Archive = $Script:Session + '.7z'
    Write-Host '正在压缩日志包……' -ForegroundColor DarkCyan
    & $Script:SevenZip a -t7z -mx=5 -mmt=on -- $Archive $Script:Session | Out-File -LiteralPath (Join-Path $Script:Session 'compress_output.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Archive)) {
        throw ('压缩失败，请保留原始目录：' + $Script:Session)
    }
    & $Script:SevenZip t -- $Archive | Out-File -LiteralPath (Join-Path $Script:Session 'archive_test.txt') -Encoding utf8
    if ($LASTEXITCODE -ne 0) { throw ('日志压缩包校验失败：' + $Archive) }
    $Hash = [Security.Cryptography.SHA256]::Create()
    $Stream = [IO.File]::OpenRead($Archive)
    try { $HashText = ([BitConverter]::ToString($Hash.ComputeHash($Stream))).Replace('-','') } finally { $Stream.Dispose(); $Hash.Dispose() }
    [IO.File]::WriteAllText($Archive + '.sha256.txt', ($HashText + '  ' + [IO.Path]::GetFileName($Archive)), [Text.Encoding]::ASCII)
    Write-Host ''
    Write-Host '抓取和压缩完成。请发送下面这个文件：' -ForegroundColor Green
    Write-Host $Archive -ForegroundColor Cyan
    Write-Host ('SHA-256：' + $HashText)
    Write-Host ''
    Write-Host '隐私提醒：bugreport 可能包含应用列表、Wi-Fi 名称、账号标识和设备状态，只发给可信任的排查人员。' -ForegroundColor Yellow
}

function Run-Live {
    New-Session '实时日志'
    Get-BaseInfo 'before'
    Get-ComprehensiveSystemLogs 'before'
    Write-Host ''
    Write-Host '实时抓取已经开始。现在可以打开游戏、风扇、相机或复现其他问题。' -ForegroundColor Green
    Write-Host '复现完成后，回到此窗口按 Ctrl+C 停止。请不要直接关闭窗口。' -ForegroundColor Yellow
    Write-Host ''
    $Captures = @()
    try {
        $Captures += Start-AdbCapture 'live_logcat_all' @('-s',$Script:DeviceSerial,'logcat','-b','all','-v','threadtime')
        $Captures += Start-AdbCapture 'live_kernel_dmesg' @('-s',$Script:DeviceSerial,'shell','dmesg','-w')
        if ($LiveSeconds -gt 0) {
            $Deadline = (Get-Date).AddSeconds($LiveSeconds)
            while ((Get-Date) -lt $Deadline) { Start-Sleep -Milliseconds 200 }
        } else {
            [Console]::TreatControlCAsInput = $true
            $Stop = $false
            while (-not $Stop) {
                if ([Console]::KeyAvailable) {
                    $Key = [Console]::ReadKey($true)
                    if ($Key.Key -eq [ConsoleKey]::C -and (($Key.Modifiers -band [ConsoleModifiers]::Control) -ne 0)) { $Stop = $true }
                }
                Start-Sleep -Milliseconds 150
            }
        }
    } finally {
        try { [Console]::TreatControlCAsInput = $false } catch {}
        Stop-Captures $Captures
    }
    Write-Host '实时记录已停止，正在补抓停止时的现场和历史缓存……' -ForegroundColor Cyan
    Get-BaseInfo 'after'
    Get-ComprehensiveSystemLogs 'after'
    Get-History -IncludeFullDumpsys
    Get-Bugreport
    Compress-Session
}

function Run-History {
    New-Session '历史临时日志'
    Get-BaseInfo 'current'
    Get-ComprehensiveSystemLogs 'current'
    Get-History -IncludeFullDumpsys
    Get-Bugreport
    Compress-Session
}

try {
    Write-Title
    Resolve-Tools
    if ($Mode -eq 'Menu') {
        Write-Host '1. 实时完整抓取（复现问题，按 Ctrl+C 停止，随后自动补抓历史日志）'
        Write-Host '2. 只抓历史和临时日志（无需现场复现）'
        Write-Host '0. 退出'
        Write-Host ''
        $Choice = Read-Host '请输入 1、2 或 0'
        if ($Choice -eq '1') { $Mode = 'Live' }
        elseif ($Choice -eq '2') { $Mode = 'History' }
        elseif ($Choice -eq '0') { exit 0 }
        else { throw '选项无效。' }
    }
    $Script:DeviceSerial = Get-Device
    Write-Host ('已连接设备：' + $Script:DeviceSerial) -ForegroundColor Green
    if ($Mode -eq 'Live') { Run-Live } else { Run-History }
    exit 0
} catch {
    Write-Host ''
    Write-Host ('执行失败：' + $_.Exception.Message) -ForegroundColor Red
    if ($Script:Session) { Write-Host ('已产生的文件保留在：' + $Script:Session) -ForegroundColor Yellow }
    exit 1
}
