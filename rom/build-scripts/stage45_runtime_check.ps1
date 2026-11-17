param([int]$WaitSeconds=180)
$ErrorActionPreference='Stop'
# Resolve the verified package through the same explicit path as the flash.
$Root='D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage45_UNIPERF_FAN'
$Adb=Join-Path $Root 'platform-tools\adb.exe'
$Serial=$env:ANDROID_SERIAL
if ([string]::IsNullOrWhiteSpace($Serial)) { throw '请先设置 ANDROID_SERIAL 环境变量' }
$Out=Join-Path $PSScriptRoot 'stage45_runtime'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Deadline=[DateTime]::UtcNow.AddSeconds($WaitSeconds)
$Ready=$false
do {
    $Devices=& $Adb devices
    if ($Devices -match ($Serial+'\s+device\s*$')) {
        $Boot=& $Adb -s $Serial shell getprop sys.boot_completed
        if (($Boot | Out-String).Trim() -eq '1') {$Ready=$true;break}
    }
    Start-Sleep -Seconds 3
} while ([DateTime]::UtcNow -lt $Deadline)
if (-not $Ready) {Write-Output 'BOOT_NOT_CONFIRMED';exit 2}
& $Adb -s $Serial shell 'getprop sys.boot_completed; pidof system_server; getprop init.svc.k90-stage44-native; getprop ro.mi.os.soc.vendor; getprop -Z ro.mi.os.soc.vendor; cat /sys/fs/selinux/enforce; ls -lZ /proc/powerhal_cpu_ctrl/perfserv_freq; cmd package has-oplusfeature oplus.misc.fan.support; ps -A -Z | grep -E "k90_native|scene-daemon|uniperf"; cat /proc/mtk_freq_qos/max_dominant; cat /proc/mtk_freq_qos/min_dominant' | Tee-Object -FilePath (Join-Path $Out 'boot_and_permissions.txt')
& $Adb -s $Serial shell 'input keyevent 224; wm dismiss-keyguard; input keyevent 3; sleep 1; am start -W -a android.settings.SETTINGS; sleep 1; input keyevent 3; sleep 1; am start -W -a android.settings.SETTINGS' | Out-File -LiteralPath (Join-Path $Out 'launches.txt') -Encoding utf8
& $Adb -s $Serial shell 'for i in 1 2 3 4 5 6; do date; for p in /sys/devices/system/cpu/cpufreq/policy0 /sys/devices/system/cpu/cpufreq/policy4 /sys/devices/system/cpu/cpufreq/policy7; do echo $p; cat $p/scaling_cur_freq $p/scaling_min_freq $p/scaling_max_freq; done; sleep 1; done; cat /proc/mtk_freq_qos/max_dominant' | Out-File -LiteralPath (Join-Path $Out 'cpu_readbacks.txt') -Encoding utf8
& $Adb -s $Serial logcat -b all -d | Out-File -LiteralPath (Join-Path $Out 'logcat_all.txt') -Encoding utf8
& $Adb -s $Serial shell dmesg | Out-File -LiteralPath (Join-Path $Out 'dmesg.txt') -Encoding utf8
& $Adb -s $Serial logcat -b crash -d | Out-File -LiteralPath (Join-Path $Out 'crashes.txt') -Encoding utf8
Write-Output 'STAGE45_SNAPSHOT_COMPLETE'
