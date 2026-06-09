param(
    [string]$ExePath = "C:\Program Files (x86)\TriggerSoft\RhakMu\Rhakmu.exe",
    [switch]$Revert
)

# CGameMenu::DrawMenuMouse crashes after timeout/draw cleanup when the global
# form/image table at 0x006E0218 is null, then the original code dereferences
# [ecx+0x14]. Guard that one draw block: if the table is null, jump to the
# function epilogue; otherwise execute the original instructions exactly.

$ErrorActionPreference = "Stop"

function Convert-VaToFileOffset([byte[]]$Bytes, [uint32]$Va) {
    $pe = [BitConverter]::ToUInt32($Bytes, 0x3C)
    $imageBase = [BitConverter]::ToUInt32($Bytes, $pe + 0x34)
    $sections = [BitConverter]::ToUInt16($Bytes, $pe + 0x06)
    $optSize = [BitConverter]::ToUInt16($Bytes, $pe + 0x14)
    $secOff = $pe + 0x18 + $optSize
    for ($i = 0; $i -lt $sections; $i++) {
        $off = $secOff + ($i * 40)
        $virtualSize = [BitConverter]::ToUInt32($Bytes, $off + 8)
        $virtualAddress = [BitConverter]::ToUInt32($Bytes, $off + 12)
        $rawSize = [BitConverter]::ToUInt32($Bytes, $off + 16)
        $rawPtr = [BitConverter]::ToUInt32($Bytes, $off + 20)
        $start = $imageBase + $virtualAddress
        $size = [Math]::Max($virtualSize, $rawSize)
        if ($Va -ge $start -and $Va -lt ($start + $size)) {
            return [int]($rawPtr + ($Va - $start))
        }
    }
    throw ("VA 0x{0:X8} not in a PE section" -f $Va)
}

function Test-BytesEqual([byte[]]$Bytes, [int]$Offset, [byte[]]$Expected) {
    for ($i = 0; $i -lt $Expected.Length; $i++) {
        if ($Bytes[$Offset + $i] -ne $Expected[$i]) { return $false }
    }
    return $true
}

if (-not (Test-Path -LiteralPath $ExePath)) { throw "File not found: $ExePath" }

$bytes = [IO.File]::ReadAllBytes($ExePath)
$va = [uint32]0x004248E5
$offset = Convert-VaToFileOffset $bytes $va
$expected = [byte[]]@(
    0x8B,0x0D,0x18,0x02,0x6E,0x00,
    0x8B,0x51,0x14,
    0x8B,0x44,0x02,0x10,
    0x50,
    0x6A,0x00,
    0x0F,0xBF,0x4D,0xE0
)
$patch = [byte[]]@(
    # mov ecx, [0x006E0218]
    0x8B,0x0D,0x18,0x02,0x6E,0x00,
    # test ecx, ecx; je 0x0042494E
    0x85,0xC9,0x74,0x5F,
    # original path
    0x8B,0x51,0x14,
    0x8B,0x44,0x02,0x10,
    0x50,
    0x6A,0x00,
    0x0F,0xBF,0x4D,0xE0
)

if ($Revert) {
    if (Test-BytesEqual $bytes $offset $expected) {
        Write-Host "Already original: DrawMenuMouse guard is not patched." -ForegroundColor Yellow
        return
    }
    $backup = "$ExePath.bak_drawmenumouse_revert_$(Get-Date -Format yyyyMMdd_HHmmss)"
    [IO.File]::WriteAllBytes($backup, $bytes)
    [Array]::Copy($expected, 0, $bytes, $offset, $expected.Length)
    [IO.File]::WriteAllBytes($ExePath, $bytes)
    Write-Host "Reverted: restored original DrawMenuMouse block." -ForegroundColor Green
    Write-Host "Backup: $backup"
    return
}

if (Test-BytesEqual $bytes $offset $patch) {
    Write-Host "Already patched: DrawMenuMouse null table guard." -ForegroundColor Yellow
    return
}

if (-not (Test-BytesEqual $bytes $offset $expected)) {
    $current = New-Object byte[] $expected.Length
    [Array]::Copy($bytes, $offset, $current, 0, $current.Length)
    $hex = ($current | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    throw "Unexpected bytes at VA 0x$('{0:X8}' -f $va) (file 0x$('{0:X}' -f $offset)): $hex"
}

$backup = "$ExePath.bak_drawmenumouse_$(Get-Date -Format yyyyMMdd_HHmmss)"
[IO.File]::WriteAllBytes($backup, $bytes)
[Array]::Copy($patch, 0, $bytes, $offset, $patch.Length)
[IO.File]::WriteAllBytes($ExePath, $bytes)

Write-Host "Patched: DrawMenuMouse skips drawing when form table is null." -ForegroundColor Green
Write-Host "Backup: $backup"
