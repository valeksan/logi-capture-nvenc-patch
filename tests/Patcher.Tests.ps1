# SPDX-License-Identifier: MIT
# Copyright (c) 2026 LogiCapture NVENC Patch contributors

#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    . (Join-Path $PSScriptRoot '..\src\common.ps1')
    $offsetsPath = Join-Path $PSScriptRoot '..\src\offsets.json'
    $spec = Get-PatchSpec -Path $offsetsPath
}

Describe 'offsets.json' {
    It 'targets the expected product and file' {
        $spec.product | Should -Be 'LogiCapture'
        $spec.version | Should -Be '2.08.11'
        $spec.target | Should -Be 'VHMultiWriterExt2.exe'
    }

    It 'contains SHA-256 values' {
        $spec.original_sha256 | Should -Match '^[0-9A-F]{64}$'
        $spec.patched_sha256 | Should -Match '^[0-9A-F]{64}$'
        $spec.original_sha256 | Should -Not -Be $spec.patched_sha256
    }

    It 'has a positive original size' {
        [int64]$spec.original_size | Should -BeGreaterThan 0
    }

    It 'contains patches with matching old/new lengths' {
        foreach ($patch in $spec.patches) {
            $old = Convert-HexToBytes -Hex $patch.old
            $new = Convert-HexToBytes -Hex $patch.new
            $old.Length | Should -Be $new.Length -Because $patch.name
            [int]$patch.length | Should -Be $old.Length -Because $patch.name
        }
    }

    It 'keeps all patch ranges inside the file' {
        foreach ($patch in $spec.patches) {
            $offset = [Convert]::ToInt32($patch.offset, 16)
            $length = (Convert-HexToBytes -Hex $patch.old).Length
            $offset | Should -BeGreaterOrEqual 0
            ($offset + $length) | Should -BeLessOrEqual ([int64]$spec.original_size)
        }
    }

    It 'does not contain overlapping patch ranges' {
        $ranges = @()
        foreach ($patch in $spec.patches) {
            $offset = [Convert]::ToInt32($patch.offset, 16)
            $length = (Convert-HexToBytes -Hex $patch.old).Length
            $end = $offset + $length
            foreach ($range in $ranges) {
                ($offset -lt $range.End -and $range.Offset -lt $end) | Should -BeFalse -Because "$($patch.name) overlaps $($range.Name)"
            }
            $ranges += [pscustomobject]@{ Name = $patch.name; Offset = $offset; End = $end }
        }
    }

    It 'is sorted by file offset' {
        $previous = -1
        foreach ($patch in $spec.patches) {
            $offset = [Convert]::ToInt32($patch.offset, 16)
            $offset | Should -BeGreaterThan $previous
            $previous = $offset
        }
    }
}

Describe 'hex conversion' {
    It 'converts upper and lower case hex' {
        $bytes = Convert-HexToBytes -Hex '0a FF 10'
        $bytes.Length | Should -Be 3
        $bytes[0] | Should -Be 10
        $bytes[1] | Should -Be 255
        $bytes[2] | Should -Be 16
    }

    It 'rejects odd-length hex' {
        { Convert-HexToBytes -Hex 'ABC' } | Should -Throw
    }
}
