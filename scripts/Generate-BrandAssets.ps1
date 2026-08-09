[CmdletBinding()]
param(
    [switch]$Check,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$recipePath = Join-Path $repoRoot 'build\branding.json'
if (-not (Test-Path -LiteralPath $recipePath -PathType Leaf)) {
    throw "Branding recipe is missing: $recipePath"
}

$recipe = Get-Content -LiteralPath $recipePath -Raw | ConvertFrom-Json
$sourcePath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $recipe.source))
$defaultOutput = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $recipe.outputDirectory))
$targetDirectory = if ($OutputDirectory) {
    [System.IO.Path]::GetFullPath($OutputDirectory)
}
else {
    $defaultOutput
}

if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Canonical brand source is missing: $sourcePath"
}
if (-not $Check -and -not (Test-Path -LiteralPath $targetDirectory)) {
    New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
}

Add-Type -AssemblyName System.Drawing
$expectedFiles = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

function New-ResizedPngBytes {
    param(
        [Parameter(Mandatory)][System.Drawing.Image]$Source,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    $bitmap = New-Object System.Drawing.Bitmap(
        $Width,
        $Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    try {
        $bitmap.SetResolution(96, 96)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.Clear([System.Drawing.Color]::Transparent)
            $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
            $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
            $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $attributes = New-Object System.Drawing.Imaging.ImageAttributes
            try {
                $attributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
                $destination = New-Object System.Drawing.Rectangle(0, 0, $Width, $Height)
                $graphics.DrawImage(
                    $Source,
                    $destination,
                    0,
                    0,
                    $Source.Width,
                    $Source.Height,
                    [System.Drawing.GraphicsUnit]::Pixel,
                    $attributes
                )
            }
            finally {
                $attributes.Dispose()
            }
        }
        finally {
            $graphics.Dispose()
        }

        $stream = New-Object System.IO.MemoryStream
        try {
            $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
            return $stream.ToArray()
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

function New-IcoBytes {
    param(
        [Parameter(Mandatory)][System.Drawing.Image]$Source,
        [Parameter(Mandatory)][int[]]$Sizes
    )

    $frames = @(
        foreach ($size in $Sizes) {
            $pngBytes = New-ResizedPngBytes -Source $Source -Width $size -Height $size
            $pngStream = New-Object System.IO.MemoryStream(,$pngBytes)
            $bitmap = [System.Drawing.Bitmap]::FromStream($pngStream)
            try {
                $dibStream = New-Object System.IO.MemoryStream
                $dibWriter = New-Object System.IO.BinaryWriter($dibStream)
                try {
                    $pixelBytes = $size * $size * 4
                    $maskStride = [int]([Math]::Ceiling($size / 32.0) * 4)
                    $maskBytes = $maskStride * $size

                    # BITMAPINFOHEADER. ICO DIB height includes XOR and AND planes.
                    $dibWriter.Write([uint32]40)
                    $dibWriter.Write([int32]$size)
                    $dibWriter.Write([int32]($size * 2))
                    $dibWriter.Write([uint16]1)
                    $dibWriter.Write([uint16]32)
                    $dibWriter.Write([uint32]0)
                    $dibWriter.Write([uint32]$pixelBytes)
                    $dibWriter.Write([int32]0)
                    $dibWriter.Write([int32]0)
                    $dibWriter.Write([uint32]0)
                    $dibWriter.Write([uint32]0)

                    # ICO DIB pixels are stored bottom-up in BGRA order.
                    for ($y = $size - 1; $y -ge 0; $y--) {
                        for ($x = 0; $x -lt $size; $x++) {
                            $color = $bitmap.GetPixel($x, $y)
                            $dibWriter.Write([byte]$color.B)
                            $dibWriter.Write([byte]$color.G)
                            $dibWriter.Write([byte]$color.R)
                            $dibWriter.Write([byte]$color.A)
                        }
                    }

                    # Retain a conventional 1-bit transparency mask for shell
                    # readers that do not honor the 32-bit alpha channel.
                    $mask = [byte[]]::new($maskBytes)
                    for ($row = 0; $row -lt $size; $row++) {
                        $sourceY = $size - 1 - $row
                        for ($x = 0; $x -lt $size; $x++) {
                            if ($bitmap.GetPixel($x, $sourceY).A -eq 0) {
                                $byteIndex = ($row * $maskStride) + [int][Math]::Floor($x / 8.0)
                                $bit = 7 - ($x % 8)
                                $mask[$byteIndex] = $mask[$byteIndex] -bor (1 -shl $bit)
                            }
                        }
                    }
                    $dibWriter.Write($mask)
                    $dibWriter.Flush()

                    [pscustomobject]@{
                        Size = $size
                        Bytes = $dibStream.ToArray()
                    }
                }
                finally {
                    $dibWriter.Dispose()
                    $dibStream.Dispose()
                }
            }
            finally {
                $bitmap.Dispose()
                $pngStream.Dispose()
            }
        }
    )
    $stream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($stream)
    try {
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]$frames.Count)
        $offset = 6 + (16 * $frames.Count)
        foreach ($frame in $frames) {
            $dimension = if ($frame.Size -ge 256) { [byte]0 } else { [byte]$frame.Size }
            $writer.Write($dimension)
            $writer.Write($dimension)
            $writer.Write([byte]0)
            $writer.Write([byte]0)
            $writer.Write([uint16]1)
            $writer.Write([uint16]32)
            $writer.Write([uint32]$frame.Bytes.Length)
            $writer.Write([uint32]$offset)
            $offset += $frame.Bytes.Length
        }
        foreach ($frame in $frames) {
            $writer.Write($frame.Bytes)
        }
        $writer.Flush()
        return $stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

function Test-ByteEquality {
    param(
        [Parameter(Mandatory)][byte[]]$Expected,
        [Parameter(Mandatory)][byte[]]$Actual
    )

    if ($Expected.Length -ne $Actual.Length) { return $false }
    for ($index = 0; $index -lt $Expected.Length; $index++) {
        if ($Expected[$index] -ne $Actual[$index]) { return $false }
    }
    return $true
}

function Set-OrCheckAsset {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [Parameter(Mandatory)][byte[]]$Bytes
    )

    $null = $expectedFiles.Add($FileName)
    $path = Join-Path $targetDirectory $FileName
    if ($Check) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Generated brand asset is missing: $path"
        }
        $actual = [System.IO.File]::ReadAllBytes($path)
        if (-not (Test-ByteEquality -Expected $Bytes -Actual $actual)) {
            throw "Generated brand asset is stale or invalid: $path"
        }
    }
    else {
        [System.IO.File]::WriteAllBytes($path, $Bytes)
    }
}

$source = [System.Drawing.Image]::FromFile($sourcePath)
try {
    $iconBytes = New-IcoBytes -Source $source -Sizes @($recipe.icon.sizes | ForEach-Object { [int]$_ })
    Set-OrCheckAsset -FileName $recipe.icon.file -Bytes $iconBytes

    foreach ($asset in $recipe.assets) {
        $baseWidth = [int]$asset.width
        $baseHeight = [int]$asset.height
        $baseBytes = New-ResizedPngBytes -Source $source -Width $baseWidth -Height $baseHeight
        Set-OrCheckAsset -FileName $asset.file -Bytes $baseBytes

        $stem = [System.IO.Path]::GetFileNameWithoutExtension($asset.file)
        foreach ($scale in $asset.scales) {
            $scaleValue = [int]$scale
            $width = [int][Math]::Round($baseWidth * $scaleValue / 100.0, [MidpointRounding]::AwayFromZero)
            $height = [int][Math]::Round($baseHeight * $scaleValue / 100.0, [MidpointRounding]::AwayFromZero)
            $bytes = New-ResizedPngBytes -Source $source -Width $width -Height $height
            Set-OrCheckAsset -FileName "$stem.scale-$scaleValue.png" -Bytes $bytes
        }
    }

    foreach ($targetSize in $recipe.targetSizeAsset.sizes) {
        $size = [int]$targetSize
        $bytes = New-ResizedPngBytes -Source $source -Width $size -Height $size
        $stem = $recipe.targetSizeAsset.fileStem
        Set-OrCheckAsset -FileName "$stem.targetsize-$size.png" -Bytes $bytes
        if ([bool]$recipe.targetSizeAsset.includeUnplated) {
            Set-OrCheckAsset -FileName "$stem.targetsize-${size}_altform-unplated.png" -Bytes $bytes
        }
    }
}
finally {
    $source.Dispose()
}

if ($Check) {
    $unexpected = @(
        Get-ChildItem -LiteralPath $targetDirectory -File |
            Where-Object {
                $_.Extension -in @('.png', '.ico') -and
                -not $expectedFiles.Contains($_.Name)
            }
    )
    if ($unexpected.Count -gt 0) {
        throw "Unexpected brand assets are not defined by the recipe: $($unexpected.Name -join ', ')"
    }
}

$verb = if ($Check) { 'validated' } else { 'generated' }
Write-Host "Brand assets $verb successfully: $targetDirectory" -ForegroundColor Green
