# Changelog

## 1.0.0 - 2026-10-19

- Initial public scaffold.
- Added byte-level patch map for LogiCapture 2.08.11 x64
  (`VHMultiWriterExt2.exe`).
- Added PowerShell patcher, unpatcher, and verification helper.
- Added hash and overlap validation; the patcher refuses unknown builds.
- Added dry-run mode and UAC self-elevation.
- Added a dependency-free offset-map test and an optional Pester 5 test suite.
- Documented the NVENC API 8.1 vs 11.1 compatibility issue.
- Verified hardware recording with an NVIDIA RTX 3080 Ti on driver 32.0.16.1714:
  `h264nvenc_probe` returns `2`, the output is H.264 (`avc1`), and the encoder
  process loads `nvEncodeAPI64.dll` and `nvcuda.dll`.
