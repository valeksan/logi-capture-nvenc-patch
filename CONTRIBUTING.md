# Contributing

Thanks for helping improve the patch.

## Do not upload proprietary files

Do not attach, commit, or link to:

- `VHMultiWriterExt2.exe`, `VHMediaCOM.dll`, or any other Logitech file;
- NVIDIA NVENC libraries or SDK binaries;
- installers, product keys, or activation material;
- full binaries "for testing".

Only submit hashes, offsets, old/new byte sequences, logs, and your own test
results.

## Adding support for another build

A new build entry needs:

1. LogiCapture version and file size.
2. SHA-256 of the original, unmodified `VHMultiWriterExt2.exe`.
3. A complete diff against the supported behavior, with old and new bytes.
4. Proof that `h264nvenc_probe` returns exit code `2`.
5. Proof that a real recording is H.264 (`avc1`) and loads `nvEncodeAPI64.dll`.
6. Confirmation that the patch is reversible with a backup.

Keep patches sorted by file offset and non-overlapping. Update
`src/offsets.json` and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-Offsets.ps1
```

## Code style

- PowerShell 5.1 compatible.
- No external dependencies for `src/*.ps1`.
- Validate all input bytes before writing.
- Fail closed on unknown builds.
- Never write a file without a backup and a final hash check.
