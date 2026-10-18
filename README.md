# LogiCapture 2.08.11 NVENC patch (unofficial)

Unofficial compatibility patch that restores hardware H.264 encoding through
NVIDIA NVENC in **LogiCapture 2.08.11** on modern NVIDIA drivers.

The repository contains **no Logitech binaries**. The patcher modifies only a
locally installed, legally obtained copy of `VHMultiWriterExt2.exe`. A timestamped
backup is created before any byte is written.

> This project is not affiliated with Logitech or NVIDIA. Use at your own risk.
> See [DISCLAIMER.md](DISCLAIMER.md).

## The problem

LogiCapture 2.08.11 was built against an old NVENC API. It creates
`NV_ENCODE_API_FUNCTION_LIST` with API version **8.1** and then asks the driver
for legacy presets. On current NVIDIA drivers this fails with:

```text
NV_ENC_ERR_INVALID_VERSION (0xf)
```

or with an unsupported-parameter error after the preset is changed. The driver
itself can support a much newer API, but the application never negotiates it.

The patch moves the 8.1 code path to API **11.1**, switches to NVIDIA P-presets,
uses `nvEncGetEncodePresetConfigEx`, and sets a valid `tuningInfo`.

## Tested configuration

| Item | Value |
|---|---|
| LogiCapture | 2.08.11 x64 |
| Windows | Windows 11 26H2 (build 26300.9711) |
| GPU | NVIDIA RTX 3080 Ti |
| Driver | 32.0.16.1714 |
| Result | `h264nvenc_probe` exits with code `2`; recording is H.264 (`avc1`) |

Other LogiCapture builds, GPU models, and driver versions are **not tested**.
The patcher refuses to run if the input file hash does not match the supported
build.

## Requirements

- Windows 10 or 11, x64.
- LogiCapture 2.08.11 installed in the default location.
- PowerShell 5.1 or newer.
- Administrator rights (the patcher requests UAC).
- A locally installed copy of LogiCapture. The repository does not provide one.

## Usage

Clone the repository and inspect the scripts before running anything:

```powershell
git clone <your-repository-url>
cd logi-capture-nvenc-patch
```

Check the current state:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\verify.ps1
```

Apply the patch:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\patch.ps1
```

The script will:

1. Locate `VHMultiWriterExt2.exe`.
2. Verify its size and SHA-256.
3. Validate every old byte at every offset.
4. Create a timestamped backup in
   `%LOCALAPPDATA%\LogiCaptureNVENC\backup`.
5. Stop LogiCapture processes.
6. Write the patched file.
7. Verify the final SHA-256.

After patching, start LogiCapture again. Select the NVIDIA encoder / let the
application probe hardware encoders, then record a short test clip.

### Dry run

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\patch.ps1 -DryRun
```

`-DryRun` performs all hash and byte checks but does not write anything and does
not request elevation.

### Custom install path

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\patch.ps1 -TargetPath "D:\Apps\LogiCapture\bin\VHMultiWriterExt2.exe"
```

## Verification

Run the hardware probe from the installed directory:

```powershell
& "C:\Program Files\Logitech\LogiCapture\bin\VHMultiWriterExt2.exe" h264nvenc_probe
$LASTEXITCODE
```

Expected result:

```text
SUCCEEDED
2
```

A full recording is the stronger test. While recording, `VHMultiWriterExt2.exe`
should load `nvEncodeAPI64.dll` and `nvcuda.dll`. The resulting MP4 should contain
an H.264 video track (`avc1`).

The helper script can run the probe for you:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\verify.ps1 -Probe
```

## Rollback

Restore the latest backup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\unpatch.ps1
```

Restore a specific backup:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\unpatch.ps1 -BackupPath "C:\Users\you\AppData\Local\LogiCaptureNVENC\backup\VHMultiWriterExt2.exe.20261019_054125_000.bak"
```

The unpatcher verifies that the current file is the known patched build and that
the backup matches the known original build before restoring it.

## What is changed

The patch set is data-driven in [src/offsets.json](src/offsets.json). It covers:

- `NV_ENCODE_API_FUNCTION_LIST` version;
- `NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS` version and `apiVersion`;
- `NV_ENC_INITIALIZE_PARAMS`, `NV_ENC_CONFIG`, `NV_ENC_RC_PARAMS`, and related
  version fields;
- the legacy preset GUID tables (mapped to NVIDIA P1-P7 presets);
- a small wrapper that redirects the legacy preset call to
  `nvEncGetEncodePresetConfigEx`;
- a hook that sets `tuningInfo = NV_ENC_TUNING_INFO_LOW_LATENCY`.

The technical details are in [docs/technical.md](docs/technical.md).

`VHMediaCOM.dll` is intentionally not modified. In the tested build the actual
recording path uses `VHMultiWriterExt2.exe`; adding a second binary increases
risk without a demonstrated benefit.

## Repository layout

```text
src/patch.ps1       apply the patch
src/unpatch.ps1     restore a backup
src/verify.ps1      inspect hash/status and optionally run the probe
src/common.ps1      shared helpers
src/offsets.json    supported build hashes and byte-level patches
tests/              offset-map tests
docs/               technical notes and troubleshooting
```

## Testing

The offset map can be checked without Pester or a LogiCapture installation:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Offsets.ps1
```

A Pester 5 test suite is also included for maintainers:

```powershell
Invoke-Pester .\tests\Patcher.Tests.ps1
```

## Safety

- No binaries, DLLs, installers, or Logitech assets are distributed.
- The patcher never downloads anything.
- Every target byte is checked before writing.
- The original file is backed up first.
- The result is hash-verified; on failure the backup is restored.
- The patcher refuses unknown builds instead of guessing offsets.

## Limitations

- LogiCapture updates will overwrite the patched file; re-check the hash and
  re-apply only if the new build is supported.
- `VHMultiWriterExt2.exe` may be blocked by antivirus or a running LogiCapture
  instance. Close LogiCapture and retry.
- The patch is specific to one file build. It is not a generic NVENC fix for all
  Logitech software.
- Windows camera privacy settings and other applications using the camera can
  independently prevent preview/recording.

## Legal

This is an unofficial interoperability project. It does not grant any rights to
LogiCapture, NVENC, or other proprietary software. Distributing patched Logitech
binaries is not permitted by this project; only the patch data and scripts are
provided. Read [DISCLAIMER.md](DISCLAIMER.md) before use.

## License

The scripts and documentation in this repository are licensed under the MIT
License. See [LICENSE](LICENSE).
