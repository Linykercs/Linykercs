# Converts a photo into ASCII art (one file per theme).
# Usage: powershell -File scripts/ascii.ps1 -Image assets/avatar.png
param(
    [Parameter(Mandatory)] [string] $Image,
    [int] $Cols = 58,
    [int] $Rows = 40,
    # Crop rectangle in source pixels: x, y, width, height
    [int[]] $Crop = @(88, 62, 204, 237),
    # Head ellipse as fractions of the crop: centre x, centre y, radius x, radius y
    [double[]] $Head = @(0.475, 0.38, 0.36, 0.42),
    # Where the shoulders start, as a fraction of the crop height
    [double] $ShouldersTop = 0.70,
    [string] $OutDir = "assets"
)

Add-Type -AssemblyName System.Drawing

$ramp = ' .:-=+*#%@'
$src = [System.Drawing.Bitmap]::FromFile((Resolve-Path $Image))
$small = New-Object System.Drawing.Bitmap $Cols, $Rows
$g = [System.Drawing.Graphics]::FromImage($small)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$srcRect = New-Object System.Drawing.Rectangle $Crop[0], $Crop[1], $Crop[2], $Crop[3]
$dstRect = New-Object System.Drawing.Rectangle 0, 0, $Cols, $Rows
$g.DrawImage($src, $dstRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
$g.Dispose(); $src.Dispose()

# Luminance grid, 0..1
$lum = New-Object 'double[,]' $Rows, $Cols
$all = New-Object System.Collections.Generic.List[double]
for ($y = 0; $y -lt $Rows; $y++) {
    for ($x = 0; $x -lt $Cols; $x++) {
        $p = $small.GetPixel($x, $y)
        $v = (0.2126 * $p.R + 0.7152 * $p.G + 0.0722 * $p.B) / 255
        $lum[$y, $x] = $v
        $all.Add($v)
    }
}
$small.Dispose()

# Contrast stretch between the 3rd and 97th percentiles
$sorted = $all | Sort-Object
$lo = $sorted[[int]($sorted.Count * 0.03)]
$hi = $sorted[[int]($sorted.Count * 0.97)]

function Get-Art([bool] $darkTheme) {
    $lines = for ($y = 0; $y -lt $Rows; $y++) {
        $sb = New-Object System.Text.StringBuilder
        for ($x = 0; $x -lt $Cols; $x++) {
            $v = ($lum[$y, $x] - $lo) / ($hi - $lo)
            $v = [Math]::Min(1.0, [Math]::Max(0.0, [double]$v))
            # Subject mask (head ellipse + shoulders) hides the busy background
            $u = $x / $Cols
            $w = $y / $Rows
            $d = [Math]::Sqrt([Math]::Pow(($u - $Head[0]) / $Head[2], 2) + [Math]::Pow(($w - $Head[1]) / $Head[3], 2))
            $inHead = [Math]::Min(1.0, [Math]::Max(0.0, [double]((1.05 - $d) / 0.12)))
            $half = 0.30 + ($w - $ShouldersTop) / (1 - $ShouldersTop) * 0.24
            $side = [Math]::Min(1.0, [Math]::Max(0.0, [double](($half - [Math]::Abs($u - 0.5)) / 0.04)))
            $rise = [Math]::Min(1.0, [Math]::Max(0.0, [double](($w - $ShouldersTop) / 0.05)))
            $mask = [Math]::Max($inHead, $side * $rise)
            # Dark theme: bright pixels get dense glyphs. Light theme: the opposite.
            $ink = if ($darkTheme) { $v } else { 1 - $v }
            $ink = [Math]::Pow($ink, 0.9) * $mask
            $idx = [int][Math]::Round($ink * ($ramp.Length - 1))
            [void]$sb.Append($ramp[$idx])
        }
        $sb.ToString().TrimEnd()
    }
    $lines -join "`n"
}

$utf8 = New-Object System.Text.UTF8Encoding $false
$out = (Resolve-Path $OutDir).Path
[System.IO.File]::WriteAllText((Join-Path $out 'ascii-dark.txt'), (Get-Art $true), $utf8)
[System.IO.File]::WriteAllText((Join-Path $out 'ascii-light.txt'), (Get-Art $false), $utf8)
Write-Host "Wrote ascii-dark.txt and ascii-light.txt ($Cols x $Rows)"
