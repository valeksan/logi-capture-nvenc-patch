Set-StrictMode -Version Latest

function Get-PatchLogPath {
    $dir = Join-Path $env:LOCALAPPDATA 'LogiCaptureNVENC'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return (Join-Path $dir 'patch.log')
}

function Write-PatchLog {
    param([Parameter(Mandatory = $true)][string]$Message)

    $line = '{0} {1}' -f (Get-Date -Format o), $Message
    Write-Host $line

    try {
        Add-Content -LiteralPath (Get-PatchLogPath) -Value $line -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not write log: $($_.Exception.Message)"
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($Path)
        try {
            $hash = $sha.ComputeHash($stream)
            return ([BitConverter]::ToString($hash)).Replace('-', '')
        }
        finally {
            $stream.Dispose()
        }
    }
    finally {
        $sha.Dispose()
    }
}

function Convert-HexToBytes {
    param([Parameter(Mandatory = $true)][string]$Hex)

    $clean = $Hex -replace '[^0-9A-Fa-f]', ''
    if (($clean.Length % 2) -ne 0) {
        throw "Hex string has odd length: $Hex"
    }

    $bytes = New-Object byte[] ($clean.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($clean.Substring($i * 2, 2), 16)
    }
    return ,$bytes
}

function Resolve-LogiCaptureTarget {
    param([string]$Path)

    if ($Path) {
        if (Test-Path -LiteralPath $Path -PathType Container) {
            $Path = Join-Path $Path 'VHMultiWriterExt2.exe'
        }
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Target not found: $Path"
        }
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $candidates = [System.Collections.Generic.List[string]]::new()

    if ($env:ProgramFiles) {
        $candidates.Add((Join-Path $env:ProgramFiles 'Logitech\LogiCapture\bin\VHMultiWriterExt2.exe'))
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates.Add((Join-Path ${env:ProgramFiles(x86)} 'Logitech\LogiCapture\bin\VHMultiWriterExt2.exe'))
    }
    if ($env:LOCALAPPDATA) {
        $candidates.Add((Join-Path $env:LOCALAPPDATA 'Logitech\LogiCapture\bin\VHMultiWriterExt2.exe'))
    }

    $registryRoots = @(
        'HKCU:\Software\Logitech\Capture',
        'HKLM:\SOFTWARE\Logitech\Capture',
        'HKLM:\SOFTWARE\WOW6432Node\Logitech\Capture'
    )

    foreach ($root in $registryRoots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $props = Get-ItemProperty -LiteralPath $root -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($prop in $props.PSObject.Properties) {
            if ($prop.Name -notmatch '(?i)(path|location|install|folder)') { continue }
            if ($prop.Value -isnot [string]) { continue }
            if ($prop.Value -notmatch '(?i)LogiCapture') { continue }

            $base = $prop.Value.Trim('"')
            $candidates.Add((Join-Path $base 'VHMultiWriterExt2.exe'))
            $candidates.Add((Join-Path $base 'bin\VHMultiWriterExt2.exe'))
        }
    }

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'LogiCapture VHMultiWriterExt2.exe was not found. Pass -TargetPath.'
}

function Get-PatchSpec {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Offsets file not found: $Path"
    }

    $spec = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($name in 'schema', 'target', 'version', 'original_size', 'original_sha256', 'patched_sha256', 'patches') {
        if ($null -eq $spec.$name) {
            throw "Offsets file is missing '$name'"
        }
    }
    if ($spec.schema -ne 1) {
        throw "Unsupported offsets schema: $($spec.schema)"
    }
    if ($spec.target -ne 'VHMultiWriterExt2.exe') {
        throw "Offsets file targets '$($spec.target)', expected 'VHMultiWriterExt2.exe'"
    }
    if (@($spec.patches).Count -eq 0) {
        throw 'Offsets file contains no patches'
    }

    return $spec
}

function Stop-LogiCaptureProcesses {
    $names = @('LogiCapture', 'LogiCapture.bp', 'VHMultiWriterExt2')
    foreach ($name in $names) {
        Get-Process -Name $name -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 1000
}

function Quote-CommandLineArgument {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ($Value -notmatch '[\s"]') {
        return $Value
    }
    return '"' + ($Value -replace '"', '\"') + '"'
}

function Invoke-ElevatedPowerShell {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $quoted = @()
    foreach ($arg in $Arguments) {
        $quoted += (Quote-CommandLineArgument -Value $arg)
    }

    $argLine = '-NoProfile -ExecutionPolicy Bypass -File {0} {1}' -f (Quote-CommandLineArgument -Value $ScriptPath), ($quoted -join ' ')
    Write-PatchLog "Requesting elevation: powershell.exe $argLine"

    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList $argLine
    return $process.ExitCode
}
