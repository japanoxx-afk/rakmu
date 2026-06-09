param(
    [string]$ExePath = "C:\Program Files (x86)\TriggerSoft\RhakMu\Rhakmu.exe",
    [switch]$Revert
)

# CGameMenu::Menu_GameBeforeProcess changes the menu resolution before entering
# the match. On modern Windows with DDrawCompat/compat shims this can crash in
# apphelp.dll -> iCARUS_InitDDraw immediately after countdown. The real display
# mode is already handled by DDrawCompat, so skip this redundant pre-game
# ResolutionChange call setup at VA 0x00423028..0x00423045.

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
$va = [uint32]0x00423028
$offset = Convert-VaToFileOffset $bytes $va
$expected = [byte[]]@(
    0x68,0x58,0x02,0x00,0x00,
    0x68,0x20,0x03,0x00,0x00,
    0x8B,0x45,0xFC,
    0x8B,0x88,0x0C,0x03,0x00,0x00,
    0x51,
    0xB9,0xD0,0x94,0x06,0x01,
    0xE8,0xEA,0x86,0x0B,0x00
)
$patch = [byte[]]@(0x90) * $expected.Length

if ($Revert) {
    if (Test-BytesEqual $bytes $offset $expected) {
        Write-Host "Already original: pre-game ResolutionChange call is not patched." -ForegroundColor Yellow
        return
    }
    $backup = "$ExePath.bak_pregameres_revert_$(Get-Date -Format yyyyMMdd_HHmmss)"
    [IO.File]::WriteAllBytes($backup, $bytes)
    [Array]::Copy($expected, 0, $bytes, $offset, $expected.Length)
    [IO.File]::WriteAllBytes($ExePath, $bytes)
    Write-Host "Reverted: restored pre-game ResolutionChange call." -ForegroundColor Green
    Write-Host "Backup: $backup"
    return
}

if (Test-BytesEqual $bytes $offset $patch) {
    Write-Host "Already patched: pre-game ResolutionChange is NOPped." -ForegroundColor Yellow
    return
}

if (-not (Test-BytesEqual $bytes $offset $expected)) {
    $current = New-Object byte[] $expected.Length
    [Array]::Copy($bytes, $offset, $current, 0, $current.Length)
    $hex = ($current | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    throw "Unexpected bytes at VA 0x$('{0:X8}' -f $va) (file 0x$('{0:X}' -f $offset)): $hex"
}

$backup = "$ExePath.bak_pregameres_$(Get-Date -Format yyyyMMdd_HHmmss)"
[IO.File]::WriteAllBytes($backup, $bytes)
[Array]::Copy($patch, 0, $bytes, $offset, $patch.Length)
[IO.File]::WriteAllBytes($ExePath, $bytes)

Write-Host "Patched: skipped pre-game ResolutionChange (no DirectDraw re-init crash on match start)." -ForegroundColor Green
Write-Host "Backup: $backup"
