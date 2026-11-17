$ErrorActionPreference = 'Stop'
$Root = 'D:\K90Max_ColorOS17_完整迁移_20261028'
$Output = Join-Path $Root '00_总交接与清单\目录容量汇总.tsv'
$Stats = @{}
Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $Output } |
    ForEach-Object {
        $Relative = $_.FullName.Substring($Root.Length + 1)
        $Top = $Relative.Split([char]'\')[0]
        if (-not $Stats.ContainsKey($Top)) {
            $Stats[$Top] = [pscustomobject]@{ Count = [long]0; Bytes = [long]0 }
        }
        $Stats[$Top].Count++
        $Stats[$Top].Bytes += $_.Length
    }
$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add("目录`t文件数`t字节`tGB")
$Stats.GetEnumerator() | Sort-Object Name | ForEach-Object {
    $Lines.Add("$($_.Name)`t$($_.Value.Count)`t$($_.Value.Bytes)`t$([math]::Round($_.Value.Bytes / 1GB, 3))")
}
[System.IO.File]::WriteAllLines($Output, $Lines, [System.Text.UTF8Encoding]::new($true))
Get-Content -LiteralPath $Output
