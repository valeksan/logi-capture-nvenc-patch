# SPDX-License-Identifier: MIT
# Copyright (c) 2026 LogiCapture NVENC Patch contributors

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$TargetPath,
    [string]$BackupPath,
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
    $currentHash = Get-FileSha256 -Path $target

    if ($currentHash -eq $spec.original_sha256) {
        Write-PatchLog 'File is already original. Nothing to restore.'
        exit 0
    }
    if ($currentHash -ne $spec.patched_sha256) {
        throw "Unsupported current file. SHA-256 is $currentHash. Nothing was changed."
    }

    if (-not (Test-IsAdministrator) -and -not $DryRun -and -not $NoElevate) {
        $arguments = @('-TargetPath', $target, '-OffsetsPath', $OffsetsPath, '-NoElevate')
        if ($BackupPath) {
            $arguments += @('-BackupPath', $BackupPath)
        }
        $exitCode = Invoke-ElevatedPowerShell -ScriptPath $PSCommandPath -Arguments $arguments
        exit $exitCode
    }

    if (-not $BackupPath) {
        $backupRoot = Join-Path $env:LOCALAPPDATA 'LogiCaptureNVENC\backup'
        $backups = @()
        if (Test-Path -LiteralPath $backupRoot) {
            $backups = @(Get-ChildItem -LiteralPath $backupRoot -Filter 'VHMultiWriterExt2.exe.*.bak' -File -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending)
        }

        foreach ($candidate in $backups) {
            if ((Get-FileSha256 -Path $candidate.FullName) -eq $spec.original_sha256) {
                $BackupPath = $candidate.FullName
                break
            }
        }
        if (-not $BackupPath) {
            throw "No original backup found in $backupRoot. Pass -BackupPath explicitly."
        }
    }

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Leaf)) {
        throw "Backup not found: $BackupPath"
    }

    $backupHash = Get-FileSha256 -Path $BackupPath
    if ($backupHash -ne $spec.original_sha256) {
        throw "Backup does not match the expected original build. SHA-256: $backupHash"
    }

    Write-PatchLog "Backup: $BackupPath"
    Write-PatchLog "Backup SHA-256: $backupHash"

    if ($DryRun) {
        Write-PatchLog 'Dry run complete. No files were written.'
        exit 0
    }

    Stop-LogiCaptureProcesses

    $safetyRoot = Join-Path $env:LOCALAPPDATA 'LogiCaptureNVENC\backup'
    if (-not (Test-Path -LiteralPath $safetyRoot)) {
        New-Item -ItemType Directory -Path $safetyRoot -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $safety = Join-Path $safetyRoot ("VHMultiWriterExt2.exe.patched.$stamp.bak")
    Copy-Item -LiteralPath $target -Destination $safety -Force
    Write-PatchLog "Saved current patched file: $safety"

    $temp = Join-Path (Split-Path -Parent $target) ('.VHMultiWriterExt2.{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    try {
        Copy-Item -LiteralPath $BackupPath -Destination $temp -Force
        Copy-Item -LiteralPath $temp -Destination $target -Force
    }
    finally {
        if (Test-Path -LiteralPath $temp) {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
    }

    $finalHash = Get-FileSha256 -Path $target
    if ($finalHash -ne $spec.original_sha256) {
        Copy-Item -LiteralPath $safety -Destination $target -Force
        throw "Restore verification failed. Patched file was restored from $safety."
    }

    Write-PatchLog "Restored original: $target"
    Write-PatchLog 'Restart LogiCapture.'
    exit 0
}
catch {
    Write-PatchLog "ERROR: $($_.Exception.Message)"
    Write-Error $_
    exit 1
}
