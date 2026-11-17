$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -LiteralPath $root -File -Recurse -Force |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }

$tooLarge = $files | Where-Object Length -GT 1MB
$forbiddenExt = @('.img','.bin','.raw','.apk','.apex','.jar','.dex','.so','.ko','.zip','.7z','.rar','.vhd','.vhdx','.key','.pem','.pk8','.jks')
$binary = $files | Where-Object { $forbiddenExt -contains $_.Extension.ToLowerInvariant() }
$secretPattern = 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|O77HJNW4JFCYOJVG|125088|adbkey'
$secretHits = foreach ($file in $files) {
    if ($file.FullName -ne $PSCommandPath -and ($file.Extension -in '.md','.txt','.sh','.ps1','.py','.c','.cpp','.h','.json','.xml','.prop' -or [string]::IsNullOrEmpty($file.Extension))) {
        Select-String -LiteralPath $file.FullName -Pattern $secretPattern -AllMatches -ErrorAction SilentlyContinue
    }
}

if ($tooLarge -or $binary -or $secretHits) {
    $tooLarge | ForEach-Object { Write-Error "文件超过 1 MiB: $($_.FullName)" }
    $binary | ForEach-Object { Write-Error "禁止的二进制类型: $($_.FullName)" }
    $secretHits | ForEach-Object { Write-Error "疑似敏感内容: $($_.Path):$($_.LineNumber)" }
    throw '公开仓库检查失败'
}

[pscustomobject]@{
    Files = $files.Count
    Bytes = ($files | Measure-Object Length -Sum).Sum
    LargestBytes = ($files | Measure-Object Length -Maximum).Maximum
    Status = 'PASS'
}
