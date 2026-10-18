# SPDX-License-Identifier: MIT
# Copyright (c) 2026 LogiCapture NVENC Patch contributors

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$TargetPath,
    [string]$OffsetsPath,
    [switch]$Probe
)

$ErrorActionPreference = 'Stop'
if (-not $OffsetsPath) { $OffsetsPath = Join-Path $PSScriptRoot 'offsets.json' }
. (Join-Path $PSScriptRoot 'common.ps1')

try {
    $target = Resolve-LogiCaptureTarget -Path $TargetPath
    $spec = Get-PatchSpec -Path $OffsetsPath
    $hash = Get-FileSha256 -Path $target
    $item = Get-Item -LiteralPath $target

    Write-Host "Target: $($item.FullName)"
    Write-Host "Size:   $($item.Length)"
    Write-Host "SHA256: $hash"

    if ($hash -eq $spec.patched_sha256) {
        Write-Host 'Status: patched'
    }
    elseif ($hash -eq $spec.original_sha256) {
        Write-Host 'Status: original (not patched)'
    }
    else {
        Write-Host 'Status: unknown build (hash does not match offsets.json)'
        exit 2
    }

    $backupRoot = Join-Path $env:LOCALAPPDATA 'LogiCaptureNVENC\backup'
    $backups = @()
    if (Test-Path -LiteralPath $backupRoot) {
        $backups = @(Get-ChildItem -LiteralPath $backupRoot -Filter 'VHMultiWriterExt2.exe.*.bak' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
    }
    $originalBackups = @()
    foreach ($backup in $backups) {
        if ((Get-FileSha256 -Path $backup.FullName) -eq $spec.original_sha256) {
            $originalBackups += $backup
        }
    }
    Write-Host "Original backups: $($originalBackups.Count) in $backupRoot"
    if ($originalBackups.Count -gt 0) {
        Write-Host "Latest restore:   $($originalBackups[0].FullName)"
    }

    if ($Probe) {
        Write-Host 'Running h264nvenc_probe...'
        & $target h264nvenc_probe
        $probeExit = $LASTEXITCODE
        Write-Host "Probe exit code: $probeExit"
        if ($probeExit -ne 2) {
            Write-Host 'Probe did not return exit code 2.'
            exit 3
        }
    }

    exit 0
}
catch {
    Write-Error $_
    exit 1
}
