$ErrorActionPreference = 'Stop'

$root = 'D:\K90Max_ColorOS17_完整迁移_20261028\02_Codex完整工作区\wo\stage29_camera_apk\system_compat_test\classes3_smali2\com\android\camera\ui'
$targets = @(
    @{ Path = (Join-Path $root 'SideFadingLayout.smali'); Super = 'Landroid/widget/FrameLayout;' },
    @{ Path = (Join-Path $root 'SideFadingMiuiRecyclerView.smali'); Super = 'Lmiuix/recyclerview/widget/RecyclerView;' }
)

foreach ($target in $targets) {
    $text = [IO.File]::ReadAllText($target.Path)
    $pattern = '(?ms)^\.method public final dispatchDraw\(Landroid/graphics/Canvas;\)V\r?\n.*?^\.end method\r?\n'
    $matches = [regex]::Matches($text, $pattern)
    if ($matches.Count -ne 1) {
        throw "Expected one dispatchDraw in $($target.Path), got $($matches.Count)"
    }
    $replacement = @"
.method public final dispatchDraw(Landroid/graphics/Canvas;)V
    .registers 2

    invoke-super {p0, p1}, $($target.Super)->dispatchDraw(Landroid/graphics/Canvas;)V

    return-void
.end method
"@
    $updated = [regex]::Replace($text, $pattern, $replacement.Trim() + "`r`n", 1)
    [IO.File]::WriteAllText($target.Path, $updated, [Text.UTF8Encoding]::new($false))
    Write-Output "patched $($target.Path)"
}
