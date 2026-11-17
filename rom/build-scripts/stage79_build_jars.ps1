$ErrorActionPreference = 'Stop'

$tools = 'D:\K90Max_ColorOS17_完整迁移_20261028\06_WSL关键产物_虚拟磁盘不迁移\工具JAR'
$java = 'C:\Users\USERNAME\Documents\Codex\2026-10-08\wo\temurin17-jre\jdk-17.0.21+9-jre\bin\java.exe'
$live = 'D:\K90_stage79_live'
$work = 'D:\K90_STAGE79_WORK_V1'
$out = Join-Path $work 'stage79_out'
$teleBase = 'D:\K90_AOD_STAGE75_WORK\stage78_jars\telephony_verify'
$oplusBaseRaw = Join-Path $work 'oplus_smali'
$cp = @(
    "$tools\lspwork\guava-31.1-jre.jar",
    "$tools\lspwork\jcommander-1.78.jar",
    "$tools\jars\antlr.jar",
    "$tools\jars3\smali-3.0.10.jar",
    "$tools\jars3\smali-baksmali-3.0.10.jar",
    "$tools\jars3\smali-dexlib2-3.0.10.jar",
    "$tools\jars3\smali-util-3.0.10.jar"
) -join ';'

function Assemble([string]$src, [string]$dst) {
    & $java -cp $cp com.android.tools.smali.smali.Main assemble --api 34 $src -o $dst
    if ($LASTEXITCODE) { throw "smali assemble failed: $src" }
}

function Disassemble([string]$src, [string]$dst) {
    Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue
    & $java -cp $cp com.android.tools.smali.baksmali.Main disassemble --api 34 $src -o $dst
    if ($LASTEXITCODE) { throw "baksmali failed: $src" }
}

function Replace-Method([string]$path, [string]$signature, [string]$body) {
    $text = [IO.File]::ReadAllText($path)
    $start = $text.IndexOf($signature)
    if ($start -lt 0) { throw "method not found: $signature" }
    $end = $text.IndexOf('.end method', $start)
    if ($end -lt 0) { throw "method end not found: $signature" }
    $end += '.end method'.Length
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $body = (($body -replace "`r`n", "`n") -replace "`n", $nl)
    [IO.File]::WriteAllText($path, $text.Substring(0, $start) + $body + $text.Substring($end), [Text.UTF8Encoding]::new($false))
}

function Replace-Dex([string]$jar, [string]$dex) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $z = [IO.Compression.ZipFile]::Open($jar, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $e = $z.GetEntry('classes.dex')
        if (-not $e) { throw "classes.dex missing: $jar" }
        $e.Delete()
        $e = $z.CreateEntry('classes.dex', [IO.Compression.CompressionLevel]::Optimal)
        $s = $e.Open()
        try {
            $b = [IO.File]::ReadAllBytes($dex)
            $s.Write($b, 0, $b.Length)
        } finally { $s.Dispose() }
    } finally { $z.Dispose() }
}

function Entry-Hashes([string]$jar) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $r = @{}
    $z = [IO.Compression.ZipFile]::OpenRead($jar)
    try {
        foreach ($e in $z.Entries) {
            if ($e.FullName.EndsWith('/')) { continue }
            $s = $e.Open()
            try {
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $r[$e.FullName] = [Convert]::ToHexString($sha.ComputeHash($s)) }
                finally { $sha.Dispose() }
            } finally { $s.Dispose() }
        }
    } finally { $z.Dispose() }
    return $r
}

function Verify-Jar([string]$before, [string]$after, [string]$baseSmali, [string]$verifySmali, [string[]]$targets) {
    $a = Entry-Hashes $before
    $b = Entry-Hashes $after
    if ((($a.Keys | Sort-Object) -join '|') -ne (($b.Keys | Sort-Object) -join '|')) { throw "jar member set changed: $after" }
    foreach ($name in $a.Keys) {
        if ($name -ne 'classes.dex' -and $a[$name] -ne $b[$name]) { throw "non-dex member changed: $name" }
    }
    $baseFiles = @(Get-ChildItem -LiteralPath $baseSmali -Recurse -Filter '*.smali')
    $verifyFiles = @(Get-ChildItem -LiteralPath $verifySmali -Recurse -Filter '*.smali')
    if ($baseFiles.Count -ne $verifyFiles.Count) { throw "class count changed: $($baseFiles.Count) -> $($verifyFiles.Count)" }
    $changed = @()
    foreach ($f in $baseFiles) {
        $rel = $f.FullName.Substring($baseSmali.Length + 1)
        $v = Join-Path $verifySmali $rel
        if (-not (Test-Path -LiteralPath $v)) { throw "missing class: $rel" }
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $v).Hash) { $changed += $rel }
    }
    $actual = @( $changed | Sort-Object )
    $expected = @( $targets | Sort-Object )
    if (($actual -join '|') -ne ($expected -join '|')) { throw "unexpected classes changed: $($changed -join ', ')" }
    return $baseFiles.Count
}

foreach ($p in @($java, $live, $teleBase, $oplusBaseRaw) + ($cp -split ';')) {
    if (-not (Test-Path -LiteralPath $p)) { throw "missing input: $p" }
}
Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $out | Out-Null

# Normalize the shipping Oplus DEX once before patching. One unrelated class
# has a non-canonical encoding that changes on any smali round trip.
$oplusBaseDex = Join-Path $out 'oplus.base.classes.dex'
$oplusBase = Join-Path $out 'oplus_base_verify'
Assemble $oplusBaseRaw $oplusBaseDex
Disassemble $oplusBaseDex $oplusBase
$oplusCompareDex = Join-Path $out 'oplus.compare.classes.dex'
$oplusCompareBase = Join-Path $out 'oplus_compare_verify'
Assemble $oplusBase $oplusCompareDex
Disassemble $oplusCompareDex $oplusCompareBase

# Telephony: repair the value before SubscriptionDatabaseManager stores it.
$teleTree = Join-Path $out 'telephony_smali'
$teleVerify = Join-Path $out 'telephony_verify'
$teleDex = Join-Path $out 'telephony.classes.dex'
$teleJar = Join-Path $out 'telephony-common.stage79.jar'
$teleSource = Join-Path $live 'telephony-common.jar'
$teleClass = 'com\android\internal\telephony\subscription\SubscriptionManagerService.smali'
Copy-Item -LiteralPath $teleBase -Destination $teleTree -Recurse
$teleTarget = Join-Path $teleTree $teleClass

$helper = @'
.method private static k90ResolveCarrierName(Lcom/android/internal/telephony/subscription/SubscriptionInfoInternal;Ljava/lang/String;)Ljava/lang/String;
    .registers 4

    invoke-static {p1}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z
    move-result v0
    if-eqz v0, :k90_return_name
    if-eqz p0, :k90_return_name

    invoke-virtual {p0}, Lcom/android/internal/telephony/subscription/SubscriptionInfoInternal;->getMcc()Ljava/lang/String;
    move-result-object v0
    const-string v1, "460"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :k90_return_name

    invoke-virtual {p0}, Lcom/android/internal/telephony/subscription/SubscriptionInfoInternal;->getMnc()Ljava/lang/String;
    move-result-object v0
    const-string v1, "11"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :k90_ct
    const-string v1, "03"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :k90_ct
    const-string v1, "05"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :k90_ct
    const-string v1, "00"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :k90_cmcc
    const-string v1, "02"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :k90_cmcc
    const-string v1, "04"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :k90_cmcc
    const-string v1, "07"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :k90_cmcc
    const-string v1, "01"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :k90_cucc
    const-string v1, "06"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v1
    if-nez v1, :k90_cucc
    const-string v1, "15"
    invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
    move-result v0
    if-eqz v0, :k90_return_name
    const-string p1, "中国广电"
    goto :k90_return_name

    :k90_ct
    const-string p1, "中国电信"
    goto :k90_return_name
    :k90_cmcc
    const-string p1, "中国移动"
    goto :k90_return_name
    :k90_cucc
    const-string p1, "中国联通"
    :k90_return_name
    return-object p1
.end method
'@
$t = [IO.File]::ReadAllText($teleTarget)
$at = $t.IndexOf('.method public blacklist setCarrierName(ILjava/lang/String;)V')
if ($at -lt 0) { throw 'setCarrierName not found' }
$nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }
$helper = (($helper -replace "`r`n", "`n") -replace "`n", $nl)
[IO.File]::WriteAllText($teleTarget, $t.Substring(0, $at) + $helper + $nl + $t.Substring($at), [Text.UTF8Encoding]::new($false))

$setCarrier = @'
.method public blacklist setCarrierName(ILjava/lang/String;)V
    .registers 6

    new-instance v0, Ljava/lang/StringBuilder;
    const-string v1, "setCarrierName: subId="
    invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    const-string v1, ", carrierName="
    invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v0
    invoke-direct {p0, v0}, Lcom/android/internal/telephony/subscription/SubscriptionManagerService;->logl(Ljava/lang/String;)V

    :try_start_k90
    iget-object v0, p0, Lcom/android/internal/telephony/subscription/SubscriptionManagerService;->mSubscriptionDatabaseManager:Lcom/android/internal/telephony/subscription/SubscriptionDatabaseManager;
    invoke-virtual {v0, p1}, Lcom/android/internal/telephony/subscription/SubscriptionDatabaseManager;->getSubscriptionInfoInternal(I)Lcom/android/internal/telephony/subscription/SubscriptionInfoInternal;
    move-result-object v1
    invoke-static {v1, p2}, Lcom/android/internal/telephony/subscription/SubscriptionManagerService;->k90ResolveCarrierName(Lcom/android/internal/telephony/subscription/SubscriptionInfoInternal;Ljava/lang/String;)Ljava/lang/String;
    move-result-object p2
    invoke-virtual {v0, p1, p2}, Lcom/android/internal/telephony/subscription/SubscriptionDatabaseManager;->setCarrierName(ILjava/lang/String;)V
    if-eqz v1, :k90_carrier_done
    invoke-virtual {v1}, Lcom/android/internal/telephony/subscription/SubscriptionInfoInternal;->getDisplayName()Ljava/lang/String;
    move-result-object v1
    invoke-static {v1}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z
    move-result v1
    if-eqz v1, :k90_carrier_done
    invoke-static {p2}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z
    move-result v1
    if-nez v1, :k90_carrier_done
    invoke-virtual {v0, p1, p2}, Lcom/android/internal/telephony/subscription/SubscriptionDatabaseManager;->setDisplayName(ILjava/lang/String;)V
    :try_end_k90
    .catch Ljava/lang/IllegalArgumentException; {:try_start_k90 .. :try_end_k90} :catch_k90

    :k90_carrier_done
    return-void
    :catch_k90
    move-exception p2
    new-instance p2, Ljava/lang/StringBuilder;
    const-string v0, "setCarrierName: invalid subId="
    invoke-direct {p2, v0}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
    invoke-virtual {p2, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    invoke-virtual {p2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object p1
    invoke-direct {p0, p1}, Lcom/android/internal/telephony/subscription/SubscriptionManagerService;->loge(Ljava/lang/String;)V
    return-void
.end method
'@
Replace-Method $teleTarget '.method public blacklist setCarrierName(ILjava/lang/String;)V' $setCarrier
Assemble $teleTree $teleDex
Copy-Item -LiteralPath $teleSource -Destination $teleJar
Replace-Dex $teleJar $teleDex
Disassemble $teleDex $teleVerify
$teleCount = Verify-Jar $teleSource $teleJar $teleBase $teleVerify @($teleClass)

# Display color: use MTK PQ only when the actual reflection bridge resolves.
$oplusTree = Join-Path $out 'oplus_smali'
$oplusVerify = Join-Path $out 'oplus_verify'
$oplusDex = Join-Path $out 'oplus.classes.dex'
$oplusJar = Join-Path $out 'oplus-services.stage79.jar'
$oplusSource = Join-Path $live 'oplus-services.jar'
$oplusClass = 'com\android\server\display\color\feature\OplusFeatureColorMode.smali'
Copy-Item -LiteralPath $oplusBase -Destination $oplusTree -Recurse
$oplusTarget = Join-Path $oplusTree $oplusClass

$initMtk = @'
.method private initMtkReflection()V
    .registers 7
    :try_start_k90
    const-string v0, "com.mediatek.pq.PictureQuality"
    invoke-static {v0}, Ljava/lang/Class;->forName(Ljava/lang/String;)Ljava/lang/Class;
    move-result-object v0
    iput-object v0, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mMtkPqClass:Ljava/lang/Class;
    const-string/jumbo v1, "oplusSetMode"
    const/4 v2, 0x1
    new-array v3, v2, [Ljava/lang/Class;
    sget-object v4, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
    const/4 v5, 0x0
    aput-object v4, v3, v5
    invoke-virtual {v0, v1, v3}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
    move-result-object v0
    iput-object v0, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mMtkSetMode:Ljava/lang/reflect/Method;
    iget-object v0, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mMtkPqClass:Ljava/lang/Class;
    const-string/jumbo v1, "setPictureMode"
    new-array v3, v2, [Ljava/lang/Class;
    sget-object v4, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
    aput-object v4, v3, v5
    invoke-virtual {v0, v1, v3}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
    move-result-object v0
    iput-object v0, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mMtkSetPictureMode:Ljava/lang/reflect/Method;
    iget-object v0, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mMtkPqClass:Ljava/lang/Class;
    const-string/jumbo v1, "setGammaIndex"
    new-array v2, v2, [Ljava/lang/Class;
    sget-object v3, Ljava/lang/Integer;->TYPE:Ljava/lang/Class;
    aput-object v3, v2, v5
    invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
    move-result-object v0
    iput-object v0, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mMtkSetGammaIndex:Ljava/lang/reflect/Method;
    const/4 v0, 0x1
    iput-boolean v0, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mIsMTK:Z
    const-string v0, "OplusFeatureColorMode"
    const-string v1, "K90 MTK PictureQuality bridge enabled"
    invoke-static {v0, v1}, Lcom/android/server/display/feature/ambience/utils/AmbienceLog;->f(Ljava/lang/String;Ljava/lang/String;)V
    :try_end_k90
    .catch Ljava/lang/ClassNotFoundException; {:try_start_k90 .. :try_end_k90} :catch_k90
    .catch Ljava/lang/NoSuchMethodException; {:try_start_k90 .. :try_end_k90} :catch_k90
    return-void
    :catch_k90
    move-exception v0
    const-string v1, "OplusFeatureColorMode"
    const-string v2, "MTK PictureQuality reflection init failed"
    invoke-static {v1, v2, v0}, Lcom/android/server/display/feature/ambience/utils/AmbienceLog;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)V
    const/4 v1, 0x0
    iput-boolean v1, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mIsMTK:Z
    const/4 v1, 0x0
    iput-object v1, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mMtkPqClass:Ljava/lang/Class;
    return-void
.end method
'@
Replace-Method $oplusTarget '.method private initMtkReflection()V' $initMtk

$updateMtk = @'
.method private updateColorMode2(I)V
    .registers 6
    iget-object v0, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mMtkPqClass:Ljava/lang/Class;
    const-string v1, "OplusFeatureColorMode"
    if-eqz v0, :k90_mtk_unavailable
    iget-object v0, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mMtkSetMode:Ljava/lang/reflect/Method;
    if-eqz v0, :k90_mtk_unavailable
    move v2, p1
    const/16 v0, 0xa
    if-ne p1, v0, :k90_check_11
    const/4 v2, 0x0
    goto :k90_mode_ready
    :k90_check_11
    const/16 v0, 0xb
    if-ne p1, v0, :k90_check_12
    const/4 v2, 0x1
    goto :k90_mode_ready
    :k90_check_12
    const/16 v0, 0xc
    if-ne p1, v0, :k90_mode_ready
    const/4 v2, 0x6
    :k90_mode_ready
    :try_start_k90
    invoke-direct {p0, v2}, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->applyMtkColorMode2(I)V
    :try_end_k90
    .catch Ljava/lang/IllegalAccessException; {:try_start_k90 .. :try_end_k90} :catch_k90
    .catch Ljava/lang/reflect/InvocationTargetException; {:try_start_k90 .. :try_end_k90} :catch_k90
    iput p1, p0, Lcom/android/server/display/color/feature/OplusFeatureColorMode;->mCurrentColorMode:I
    new-instance v0, Ljava/lang/StringBuilder;
    const-string v3, "K90 color logical="
    invoke-direct {v0, v3}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    const-string p1, " mtk="
    invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
    invoke-virtual {v0, v2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object p1
    invoke-static {v1, p1}, Lcom/android/server/display/feature/ambience/utils/AmbienceLog;->f(Ljava/lang/String;Ljava/lang/String;)V
    return-void
    :catch_k90
    move-exception v0
    new-instance v2, Ljava/lang/StringBuilder;
    const-string v3, "MTK PictureQuality invoke failed, mode="
    invoke-direct {v2, v3}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
    invoke-virtual {v2, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
    invoke-virtual {v2}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
    move-result-object v2
    invoke-static {v1, v2, v0}, Lcom/android/server/display/feature/ambience/utils/AmbienceLog;->e(Ljava/lang/String;Ljava/lang/String;Ljava/lang/Throwable;)V
    return-void
    :k90_mtk_unavailable
    const-string v0, "MTK PictureQuality unavailable, skip updateColorMode2"
    invoke-static {v1, v0}, Lcom/android/server/display/feature/ambience/utils/AmbienceLog;->e(Ljava/lang/String;Ljava/lang/String;)V
    return-void
.end method
'@
Replace-Method $oplusTarget '.method private updateColorMode2(I)V' $updateMtk
Assemble $oplusTree $oplusDex
Copy-Item -LiteralPath $oplusSource -Destination $oplusJar
Replace-Dex $oplusJar $oplusDex
Disassemble $oplusDex $oplusVerify
$oplusEncodingShift = 'com\android\server\hans\oguard\OGuardDBConfig$FileParser.smali'
$oplusCount = Verify-Jar $oplusSource $oplusJar $oplusCompareBase $oplusVerify @($oplusClass, $oplusEncodingShift)

Get-FileHash -Algorithm SHA256 -LiteralPath $teleJar,$oplusJar,$teleDex,$oplusDex | Format-Table -AutoSize Path,Hash
Write-Output "TELEPHONY_CLASS_COUNT_OK=$teleCount"
Write-Output "OPLUS_SERVICES_CLASS_COUNT_OK=$oplusCount"
Write-Output 'STAGE79_JARS_BUILD_PASSED'
