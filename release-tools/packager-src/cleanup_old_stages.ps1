$ErrorActionPreference = 'Stop'
$Delivery = [System.IO.Path]::GetFullPath((Split-Path -Parent $MyInvocation.MyCommand.Path)).TrimEnd('\')
$Names = @(
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage36_FAN_PERF',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage37_FAN_PERF_SELINUX',
    'K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage38_FAN_PERF_ROOT_WRITER'
)

Write-Host '将删除以下三个已淘汰目录（不可恢复）：' -ForegroundColor Yellow
$Targets = @()
foreach ($Name in $Names) {
    $Path = [System.IO.Path]::GetFullPath((Join-Path $Delivery $Name))
    if (-not $Path.StartsWith($Delivery + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "目标超出交付目录：$Path"
    }
    if ($Path -match 'Stage48|OneClick') { throw "命中保护目录：$Path" }
    if (Test-Path -LiteralPath $Path) {
        $Item = Get-Item -LiteralPath $Path
        if (-not $Item.PSIsContainer) { throw "目标不是目录：$Path" }
        $Targets += $Path
        Write-Host ('  ' + $Path)
    }
}

if ($Targets.Count -eq 0) {
    Write-Host '三个旧目录已经不存在，无需清理。' -ForegroundColor Green
    exit 0
}

if ((Read-Host '确认只删除以上目录请输入 DELETE') -cne 'DELETE') {
    Write-Host '已取消，没有删除任何文件。'
    exit 0
}

foreach ($Path in $Targets) {
    Write-Host ('正在删除：' + $Path) -ForegroundColor Yellow
    Remove-Item -LiteralPath $Path -Recurse -Force
    if (Test-Path -LiteralPath $Path) { throw "删除失败：$Path" }
}

Write-Host ('清理完成，D 盘当前可用：{0:N2} GiB' -f ((Get-PSDrive D).Free / 1GB)) -ForegroundColor Green
Write-Host 'Stage48 和新一键包没有被删除。' -ForegroundColor Green
