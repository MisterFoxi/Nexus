param([string]$OutputDir = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$backgroundPath = Join-Path $OutputDir 'chop_background.png'
$toolPath = Join-Path $OutputDir 'chop_tool.png'
$background = [System.Drawing.Bitmap]::FromFile($backgroundPath)
$tool = [System.Drawing.Bitmap]::FromFile($toolPath)
if ($tool.GetPixel(0,0).A -ne 0) { throw 'Tool sprite must have transparent corners.' }
$cellWidth = 512
$cellHeight = 640
$toolWidth = 360.0
$toolHeight = $toolWidth * $tool.Height / $tool.Width
# Same tool, same scale, fixed right-hand cutting-edge pivot for A and B.
$poses = @(
    @{Name='rest'; Angle=-8.0; X=437.0; Y=470.0},
    @{Name='actionA'; Angle=32.0; X=420.0; Y=440.0},
    @{Name='actionB'; Angle=0.0; X=420.0; Y=440.0}
)
$atlas = [System.Drawing.Bitmap]::new(1536,640,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$atlasGraphics = [System.Drawing.Graphics]::FromImage($atlas)
$frames = @()
for ($index = 0; $index -lt 3; ++$index) {
    $pose = $poses[$index]
    $frame = [System.Drawing.Bitmap]::new($cellWidth,$cellHeight,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($frame)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.DrawImage($background,[System.Drawing.Rectangle]::new(0,0,$cellWidth,$cellHeight))
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $graphics.TranslateTransform([single]$pose.X,[single]$pose.Y)
    $graphics.RotateTransform([single]$pose.Angle)
    $toolRect = [System.Drawing.RectangleF]::new([single](-0.85*$toolWidth),[single](-0.98*$toolHeight),[single]$toolWidth,[single]$toolHeight)
    $graphics.DrawImage($tool,$toolRect)
    $graphics.Dispose()
    $frame.Save((Join-Path $OutputDir ('chop_' + $pose.Name + '.png')),[System.Drawing.Imaging.ImageFormat]::Png)
    $atlasGraphics.DrawImageUnscaled($frame,$index*$cellWidth,0)
    $frames += $frame
}
$atlasGraphics.Dispose()
# Check unchanged background pixels in a strip outside the tool's movement.
for ($y=0; $y -lt 60; ++$y) {
    for ($x=0; $x -lt $cellWidth; ++$x) {
        if ($frames[1].GetPixel($x,$y).ToArgb() -ne $frames[2].GetPixel($x,$y).ToArgb()) {
            throw "Background alignment failed at $x,$y"
        }
    }
}
$atlas.Save((Join-Path $OutputDir 'atlas_chop_fond_fixe_v3.png'),[System.Drawing.Imaging.ImageFormat]::Png)
foreach ($frame in $frames) { $frame.Dispose() }
$atlas.Dispose()
$background.Dispose()
$tool.Dispose()
Write-Output 'Built 1536x640 atlas, 3 cells of 512x640. Background strip verified pixel-identical.'
