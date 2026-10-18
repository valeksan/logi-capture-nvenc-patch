# SPDX-License-Identifier: MIT
# Copyright (c) 2026 LogiCapture NVENC Patch contributors

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$TargetPath,
    [string]$OffsetsPath,
    [switch]$DryRun,
    [switch]$NoElevate
)

$ErrorActionPreference = 'Stop'
if (-not $OffsetsPath) { $OffsetsPath = Join-Path $PSScriptRoot 'offsets.json' }
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $target = Resolve-LogiCaptureTarget -Path $TargetPath
    $spec = Get-PatchSpec -Path $OffsetsPath

    Write-PatchLog "Target: $target"
    Write-PatchLog "Expected original SHA-256: $($spec.original_sha256)"

    $targetItem = Get-Item -LiteralPath $target
    if ($targetItem.Length -ne [int64]$spec.original_size) {
        throw "Unsupported file size: $($targetItem.Length), expected $($spec.original_size). Nothing was changed."
    }

    $actualHash = Get-FileSha256 -Path $target
    if ($actualHash -eq $spec.patched_sha256) {
        Write-PatchLog "Already patched. SHA-256: $actualHash"
        exit 0
    }
    if ($actualHash -ne $spec.original_sha256) {
        throw "Unsupported build. SHA-256 is $actualHash, expected $($spec.original_sha256). Nothing was changed."
    }

    if (-not (Test-IsAdministrator) -and -not $DryRun -and -not $NoElevate) {
        $arguments = @('-TargetPath', $target, '-OffsetsPath', $OffsetsPath, '-NoElevate')
        $exitCode = Invoke-ElevatedPowerShell -ScriptPath $PSCommandPath -Arguments $arguments
        exit $exitCode
    }

    $bytes = [IO.File]::ReadAllBytes($target)
    $patched = [byte[]]$bytes.Clone()
    $seen = [System.Collections.Generic.List[object]]::new()

    foreach ($patch in $spec.patches) {
        $offset = [Convert]::ToInt32($patch.offset, 16)
        $oldBytes = Convert-HexToBytes -Hex $patch.old
        $newBytes = Convert-HexToBytes -Hex $patch.new

        if ($oldBytes.Length -ne $newBytes.Length) {
            throw "Patch '$($patch.name)' has different old/new lengths."
        }
        if ($offset -lt 0 -or ($offset + $oldBytes.Length) -gt $bytes.Length) {
            throw "Patch '$($patch.name)' is outside the file."
        }

        foreach ($range in $seen) {
            $rangeEnd = $range.Offset + $range.Length
            $patchEnd = $offset + $oldBytes.Length
            if ($offset -lt $rangeEnd -and $range.Offset -lt $patchEnd) {
                throw "Patch '$($patch.name)' overlaps '$($range.Name)'."
            }
        }
        $seen.Add([pscustomobject]@{ Name = $patch.name; Offset = $offset; Length = $oldBytes.Length })

        for ($i = 0; $i -lt $oldBytes.Length; $i++) {
            if ($bytes[$offset + $i] -ne $oldBytes[$i]) {
                $position = '0x{0:X}' -f ($offset + $i)
                throw "Patch '$($patch.name)' does not match at $position. Nothing was changed."
            }
        }

        [Array]::Copy($newBytes, 0, $patched, $offset, $newBytes.Length)
        Write-PatchLog ("Verified {0} at {1} ({2} bytes)" -f $patch.name, $patch.offset, $oldBytes.Length)
    }

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $patchedHash = ([BitConverter]::ToString($sha.ComputeHash($patched))).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }

    if ($patchedHash -ne $spec.patched_sha256) {
        throw "Internal check failed: result SHA-256 is $patchedHash, expected $($spec.patched_sha256)."
    }

    Write-PatchLog "Result SHA-256: $patchedHash"

    if ($DryRun) {
        Write-PatchLog 'Dry run complete. No files were written.'
        exit 0
    }

    $backupRoot = Join-Path $env:LOCALAPPDATA 'LogiCaptureNVENC\backup'
    if (-not (Test-Path -LiteralPath $backupRoot)) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    }

    Stop-LogiCaptureProcesses

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $backup = Join-Path $backupRoot ("VHMultiWriterExt2.exe.$stamp.bak")
    Copy-Item -LiteralPath $target -Destination $backup -Force
    Write-PatchLog "Backup: $backup"

    $temp = Join-Path (Split-Path -Parent $target) ('.VHMultiWriterExt2.{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllBytes($temp, $patched)
        Copy-Item -LiteralPath $temp -Destination $target -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
    }

    $finalHash = Get-FileSha256 -Path $target
    if ($finalHash -ne $spec.patched_sha256) {
        Copy-Item -LiteralPath $backup -Destination $target -Force
        throw "Final verification failed. Original file was restored from $backup."
    }

    Write-PatchLog "Patched successfully: $target"
    Write-PatchLog 'Restart LogiCapture and test hardware encoding.'
    exit 0
}
catch {
    Write-PatchLog "ERROR: $($_.Exception.Message)"
    Write-PatchLog "STACK: $($_.ScriptStackTrace)"
    Write-Error $_
    exit 1
}
