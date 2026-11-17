$ErrorActionPreference = 'Stop'
$Root = 'D:\K90Max_ColorOS17_完整迁移_20261028'
$Doc = Join-Path $Root '00_总交接与清单'
$Final = Join-Path $Doc '完整文件清单.tsv'
$Temp = 'D:\K90Max迁移文件清单_最终.tmp'
$Utf8 = [System.Text.UTF8Encoding]::new($true)
$Writer = [System.IO.StreamWriter]::new($Temp, $false, $Utf8, 1048576)
try {
    $Writer.WriteLine("相对路径`t字节`t最后修改时间")
    Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $Final } |
        ForEach-Object {
            $Relative = $_.FullName.Substring($Root.Length + 1).Replace("`t", ' ')
            $Writer.WriteLine("$Relative`t$($_.Length)`t$($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'))")
        }
}
finally {
    $Writer.Dispose()
}
Move-Item -LiteralPath $Temp -Destination $Final -Force

$Rows = (Get-Content -LiteralPath $Final -ReadCount 10000 |
    ForEach-Object { $_.Count } | Measure-Object -Sum).Sum - 1
Write-Output "清单条目：$Rows"
Write-Output "清单大小：$((Get-Item -LiteralPath $Final).Length) 字节"
