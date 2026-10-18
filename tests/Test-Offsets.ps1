#Requires -Version 5.1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\common.ps1')

try {
    $offsetsPath = Join-Path $PSScriptRoot '..\src\offsets.json'
    $spec = Get-PatchSpec -Path $offsetsPath
    $patches = @($spec.patches)

    if ($spec.product -ne 'LogiCapture') { throw 'Unexpected product' }
    if ($spec.version -ne '2.08.11') { throw 'Unexpected product version' }
    if ($spec.target -ne 'VHMultiWriterExt2.exe') { throw 'Unexpected target file' }
    if ($spec.original_sha256 -notmatch '^[0-9A-F]{64}$') { throw 'Invalid original hash' }
    if ($spec.patched_sha256 -notmatch '^[0-9A-F]{64}$') { throw 'Invalid patched hash' }
    if ($spec.original_sha256 -eq $spec.patched_sha256) { throw 'Hashes must differ' }
    if ([int64]$spec.original_size -le 0) { throw 'Invalid file size' }
    if ($patches.Count -eq 0) { throw 'No patches' }

    $names = @{}
    $ranges = @()
    $previous = -1

    foreach ($patch in $patches) {
        if (-not $patch.name) { throw 'Patch without a name' }
        if ($names.ContainsKey($patch.name)) { throw "Duplicate patch name: $($patch.name)" }
        $names[$patch.name] = $true

        $offset = [Convert]::ToInt32($patch.offset, 16)
        $old = Convert-HexToBytes -Hex $patch.old
        $new = Convert-HexToBytes -Hex $patch.new

        if ($old.Length -ne $new.Length) { throw "Old/new length mismatch: $($patch.name)" }
        if ([int]$patch.length -ne $old.Length) { throw "Length field mismatch: $($patch.name)" }
        if ($offset -lt 0) { throw "Negative offset: $($patch.name)" }
        if (($offset + $old.Length) -gt [int64]$spec.original_size) { throw "Patch outside file: $($patch.name)" }
        if ($offset -le $previous) { throw "Patches are not sorted: $($patch.name)" }
        $previous = $offset

        $end = $offset + $old.Length
        foreach ($range in $ranges) {
            if ($offset -lt $range.End -and $range.Offset -lt $end) {
                throw "Overlapping patches: $($patch.name) and $($range.Name)"
            }
        }
        $ranges += [pscustomobject]@{ Name = $patch.name; Offset = $offset; End = $end }
    }

    Write-Host "OK: $($patches.Count) patches, $($spec.target) $($spec.version)"
    Write-Host "Original: $($spec.original_sha256)"
    Write-Host "Patched:  $($spec.patched_sha256)"
    exit 0
}
catch {
    Write-Error $_
    exit 1
}
