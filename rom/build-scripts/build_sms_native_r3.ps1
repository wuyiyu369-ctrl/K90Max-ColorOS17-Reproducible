$ErrorActionPreference = 'Stop'

$java = 'D:\gpt\2026-10-20\http-149-104-21-154-index\work\toolchain\microsoft-jdk17\jdk-17.0.20.1+1\bin\java.exe'
$archiveRoot = (Get-ChildItem 'D:\' -Directory | Where-Object { $_.Name -like 'K90Max_ColorOS17*' } | Select-Object -First 1).FullName
if (-not $archiveRoot) { throw 'K90 archive root not found' }
$jarRoot = (Get-ChildItem $archiveRoot -Directory -Recurse | Where-Object { Test-Path (Join-Path $_.FullName 'jars3') } | Select-Object -First 1).FullName
if (-not $jarRoot) { throw 'tool jar directory not found' }
$cp = @(
    (Join-Path $jarRoot 'lspwork\guava-31.1-jre.jar'),
    (Join-Path $jarRoot 'lspwork\jcommander-1.78.jar'),
    (Join-Path $jarRoot 'jars\antlr.jar'),
    (Join-Path $jarRoot 'jars3\smali-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-baksmali-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-dexlib2-3.0.10.jar'),
    (Join-Path $jarRoot 'jars3\smali-util-3.0.10.jar')
) -join ';'

$root = Join-Path $PSScriptRoot 'sms_native_r3'
$inputJar = Join-Path $PSScriptRoot 'sms_native_r2\telephony-common.native-sms-r2.jar'
$baseline = Join-Path $root 'baseline_smali'
$smali = Join-Path $root 'smali'
$verify = Join-Path $root 'verify_smali'
$dex = Join-Path $root 'classes.patched.dex'
$outputJar = Join-Path $root 'telephony-common.native-sms-r3.jar'
if (-not (Test-Path -LiteralPath $inputJar)) { throw 'R2 telephony JAR is missing' }
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
New-Item -ItemType Directory -Path $root | Out-Null

& $java -cp $cp com.android.tools.smali.baksmali.Main disassemble --api 34 $inputJar -o $baseline
if ($LASTEXITCODE -ne 0) { throw "R2 baksmali failed: $LASTEXITCODE" }
Copy-Item -LiteralPath $baseline -Destination $smali -Recurse

function Replace-ExactlyOnce([string]$Path, [string]$Needle, [string]$Replacement) {
    $text = [IO.File]::ReadAllText($Path)
    $nativeNeedle = $Needle.Replace("`r`n", "`n").Replace("`n", [Environment]::NewLine)
    $nativeReplacement = $Replacement.Replace("`r`n", "`n").Replace("`n", [Environment]::NewLine)
    $count = ([regex]::Matches($text, [regex]::Escape($nativeNeedle))).Count
    if ($count -ne 1) { throw "Expected one match, found $count in $Path" }
    [IO.File]::WriteAllText($Path, $text.Replace($nativeNeedle, $nativeReplacement), [Text.UTF8Encoding]::new($false))
}

$inbound = Join-Path $smali 'com\android\internal\telephony\InboundSmsHandler.smali'
$dispatcher = Join-Path $smali 'com\android\internal\telephony\SMSDispatcher.smali'
$ims = Join-Path $smali 'com\android\internal\telephony\ImsSmsDispatcher.smali'

$inboundNeedle = @'
    invoke-interface/range {v0 .. v5}, Lcom/android/internal/telephony/IOplusInboundSmsHandler;->oemCheck(Lcom/android/internal/telephony/InboundSmsTracker;I[[BLjava/lang/String;Landroid/content/Context;)Z

    move-result v0
'@
$inboundReplacement = @'
    # The ported Oplus implementation rejects valid MTK inbound SMS here.
    const/4 v0, 0x1
'@
Replace-ExactlyOnce $inbound $inboundNeedle $inboundReplacement

$sendNeedle = @'
    invoke-interface {v1, v2}, Lcom/android/internal/telephony/IOplusSMSDispatcher;->repairSmsNumber(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v10

    const/4 v11, 0x0
'@
$sendReplacement = @'
    invoke-interface {v1, v2}, Lcom/android/internal/telephony/IOplusSMSDispatcher;->repairSmsNumber(Ljava/lang/String;)Ljava/lang/String;

    move-result-object v10

    invoke-static {v10}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z

    move-result v1

    if-eqz v1, :k90_sms_destination_ready

    move-object v10, v2

    :k90_sms_destination_ready
    const/4 v11, 0x0
'@
Replace-ExactlyOnce $dispatcher $sendNeedle $sendReplacement

$imsNeedle = @'
    invoke-virtual {v0}, Lcom/android/ims/ImsManager;->getSmsFormat()Ljava/lang/String;

    move-result-object p0
    :try_end_f
    .catch Lcom/android/ims/ImsException; {:try_start_7 .. :try_end_f} :catch_10

    return-object p0
'@
$imsReplacement = @'
    invoke-virtual {v0}, Lcom/android/ims/ImsManager;->getSmsFormat()Ljava/lang/String;

    move-result-object p0
    :try_end_f
    .catch Lcom/android/ims/ImsException; {:try_start_7 .. :try_end_f} :catch_10

    if-eqz p0, :k90_ims_format_fallback

    invoke-virtual {p0}, Ljava/lang/String;->trim()Ljava/lang/String;

    move-result-object v0

    invoke-virtual {v0}, Ljava/lang/String;->isEmpty()Z

    move-result v0

    if-eqz v0, :k90_ims_format_ready

    :k90_ims_format_fallback
    const-string p0, "3gpp"

    :k90_ims_format_ready
    return-object p0
'@
Replace-ExactlyOnce $ims $imsNeedle $imsReplacement

& $java -cp $cp com.android.tools.smali.smali.Main assemble --api 34 $smali -o $dex
if ($LASTEXITCODE -ne 0) { throw "smali failed: $LASTEXITCODE" }

@'
from pathlib import Path
import zipfile
root = Path(__file__).resolve().parent / "sms_native_r3"
src = Path(__file__).resolve().parent / "sms_native_r2" / "telephony-common.native-sms-r2.jar"
dex = root / "classes.patched.dex"
out = root / "telephony-common.native-sms-r3.jar"
with zipfile.ZipFile(src, "r") as zin, zipfile.ZipFile(out, "w") as zout:
    for info in zin.infolist():
        data = dex.read_bytes() if info.filename == "classes.dex" else zin.read(info.filename)
        clone = zipfile.ZipInfo(info.filename, info.date_time)
        for attr in ("compress_type", "comment", "extra", "internal_attr", "external_attr", "create_system", "create_version", "extract_version"):
            setattr(clone, attr, getattr(info, attr))
        zout.writestr(clone, data)
'@ | & py -3 -
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputJar)) { throw 'JAR packaging failed' }

& $java -cp $cp com.android.tools.smali.baksmali.Main disassemble --api 34 $outputJar -o $verify
if ($LASTEXITCODE -ne 0) { throw "R3 verification baksmali failed: $LASTEXITCODE" }

$beforeFiles = Get-ChildItem -LiteralPath $baseline -Recurse -Filter '*.smali'
$afterFiles = Get-ChildItem -LiteralPath $verify -Recurse -Filter '*.smali'
if ($beforeFiles.Count -ne $afterFiles.Count) { throw "Class count changed: $($beforeFiles.Count) -> $($afterFiles.Count)" }
$changed = foreach ($file in $beforeFiles) {
    $relative = $file.FullName.Substring($baseline.Length + 1)
    $other = Join-Path $verify $relative
    if (-not (Test-Path -LiteralPath $other)) { throw "Missing output class: $relative" }
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $other).Hash) { $relative }
}
$expected = @(
    'com\android\internal\telephony\ImsSmsDispatcher.smali',
    'com\android\internal\telephony\InboundSmsHandler.smali',
    'com\android\internal\telephony\SMSDispatcher.smali'
)
if ((Compare-Object ($changed | Sort-Object) ($expected | Sort-Object))) {
    throw "Unexpected changed classes: $($changed -join ', ')"
}

$verifyInbound = [IO.File]::ReadAllText((Join-Path $verify $expected[1]))
$verifyDispatcher = [IO.File]::ReadAllText((Join-Path $verify $expected[2]))
$verifyIms = [IO.File]::ReadAllText((Join-Path $verify $expected[0]))
if ($verifyInbound -match 'IOplusInboundSmsHandler;->oemCheck\(') { throw 'Oplus inbound oemCheck call remains' }
if ($verifyDispatcher -notmatch 'invoke-static \{v10\}, Landroid/text/TextUtils;->isEmpty' -or
    $verifyDispatcher -notmatch 'move-object v10, v2') { throw 'Destination fallback missing' }
if ($verifyIms -notmatch 'invoke-virtual \{p0\}, Ljava/lang/String;->trim\(\)' -or
    $verifyIms -notmatch 'const-string p0, "3gpp"') { throw 'IMS format fallback missing' }

$gsm = [IO.File]::ReadAllText((Join-Path $verify 'com\android\internal\telephony\gsm\GsmInboundSmsHandler.smali'))
$cdma = [IO.File]::ReadAllText((Join-Path $verify 'com\android\internal\telephony\cdma\CdmaInboundSmsHandler.smali'))
$startNeedle = 'invoke-virtual {v0, v1}, Lcom/android/internal/telephony/StateMachine;->sendMessage(I)V'
if (([regex]::Matches($gsm, [regex]::Escape($startNeedle))).Count -ne 1) { throw 'GSM R2 startup patch missing' }
if (([regex]::Matches($cdma, [regex]::Escape($startNeedle))).Count -ne 1) { throw 'CDMA R2 startup patch missing' }

[IO.File]::WriteAllLines((Join-Path $root 'CHANGED_CLASSES.txt'), ($changed | Sort-Object), [Text.UTF8Encoding]::new($false))
Get-FileHash -LiteralPath $inputJar, $outputJar -Algorithm SHA256
Write-Output "CLASS_COUNT_OK=$($beforeFiles.Count)"
Write-Output 'R2_STARTUP_PATCHES_PRESERVED'
Write-Output 'R3_SMS_PATCHES_OK'
