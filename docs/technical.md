# Technical notes

This document describes the compatibility problem and the byte-level patch set in
[`src/offsets.json`](../src/offsets.json).

## Target build

| Field | Value |
|---|---|
| Product | LogiCapture 2.08.11 |
| File | `VHMultiWriterExt2.exe` |
| Size | 1,000,864 bytes |
| SHA-256 | `1E6671E8427C3A7F7EE6118E12D81E2BC358285EA56117F8EF7C05B6CC5D41A3` |
| Patched SHA-256 | `159C3CE0C6A0A480A27A8D469075239042DA35661B2F064A405154D83010C10B` |

The patcher validates both the size and the original hash before applying
anything. The patched hash is used as an internal consistency check and to
detect an already patched file.

## File offsets vs RVAs

`offsets.json` stores **file offsets** because the patcher operates on the file
directly. The `rva` field is included for documentation only.

For this build:

- `.text`: file offset `0x400` maps to RVA `0x1000`, so `RVA = file offset + 0xC00`.
- `.rdata`: file offset `0xACE00` maps to RVA `0xAE000`, so `RVA = file offset + 0x1200`.

## Why the old client fails

LogiCapture 2.08.11 negotiates an NVENC API version of **8.1**:

```text
NV_ENCODE_API_FUNCTION_LIST.version = 0x71020008
```

The driver on a modern NVIDIA system can support a newer API, but the
application keeps using the old function list and old structure versions. When
the application later passes an 8.1 structure to the driver, the driver rejects
it with:

```text
NV_ENC_ERR_INVALID_VERSION = 0xf
```

The patch moves the 8.1 path to API **11.1**:

```text
NV_ENCODE_API_FUNCTION_LIST.version = 0x7102000B
```

The `0x71SS000B` format is used instead of the older `0x80000000`-based encoding:

- `0x71` selects the modern version encoding;
- `SS` is the structure number (1, 2, 4, 5, 9, ...);
- `000B` is the API version (11).

For API 11.1 the tested structure versions are:

| Structure | Version value |
|---|---|
| Function list | `0x7102000B` |
| Open session params | `0x7101000B` |
| Preset config | `0x7104000B` |
| `NV_ENC_CONFIG` | `0x7109000B` (version 9) |
| Initialize params | `0x7105000B` |
| RC params | `0x7101000B` |
| Input buffer / bitstream / map / lock | `0x7101000B` / `0x7103000B` / `0x7104000B` |

Using `NV_ENC_CONFIG` version 7 or 8 still fails; version 9 is accepted.
Using `NV_ENC_INITIALIZE_PARAMS` version 6 is rejected; version 5 is accepted.

## P-presets

Modern drivers expose P1-P7 presets, but the legacy
`nvEncGetEncodePresetConfig` path only accepts the old preset GUIDs. The patch
replaces both legacy GUID tables in `.rdata`:

| Legacy slot | Replacement |
|---|---|
| `LOSSLESS_HP` | `P7` |
| `LOSSLESS_DEFAULT` | `P7` |
| `LL_HP` | `P2` |
| `LL_HQ` | `P5` |
| `LL_DEFAULT` | `P4` |
| `BD` | `P6` |
| `HQ` | `P6` |
| `HP` | `P2` |
| `DEFAULT` | `P4` |

P-preset GUIDs in memory layout:

```text
P1  0x3e8d0afcf845f84c80c7298871590ebf
P2  0xb8cf81f5d688814393f0df13f9c27dab
P3  0x10018536073a1f4494d53670631f91f6
P4  0x26b8a79006df6248b9d2cd6d73a08681
P5  0xb4e6c6217a29ba4c998fb6cbde72ade3
P6  0x79c2758e9962b64a83020b215a335cf5
P7  0x128c8484716f134c931b53e283f57974
```

## Legacy call redirection

Replacing GUIDs alone is not enough: the legacy
`nvEncGetEncodePresetConfig` function does not accept P-preset GUIDs on current
drivers. The patch redirects the call site to a small wrapper that invokes
`nvEncGetEncodePresetConfigEx` with `tuningInfo = 2`
(`NV_ENC_TUNING_INFO_LOW_LATENCY`).

Key locations:

| Purpose | File offset | RVA |
|---|---|---|
| Legacy preset call site | `0x26E76` | `0x27A76` |
| Ex wrapper code cave | `0xACCD0` | `0xAD8D0` |
| Initialize-params tuning hook | `0x2715B` | `0x27D5B` |
| Tuning code cave | `0xACD20` | `0xAD920` |

The wrapper preserves the config pointer in `r9` (not `rcx`), sets
`r9d = 2`, and calls the Ex entry point at `PresetConfig + 0xD0` through the
function-list global. The tuning hook writes `tuningInfo = 2` into
`NV_ENC_INITIALIZE_PARAMS` before `nvEncInitializeEncoder` is called.

An earlier version of the wrapper saved `rcx`, which caused an invalid-parameter
failure. Saving `r9` is required for the x64 calling convention used here.

## Version constants

The 8.1 path contains multiple copies of `0x71010008`, `0xF1010008`,
`0xF1040008`, `0xF1050008`, and `0xF1070008`-style constants. The patch updates
all of them to the API 11.1 equivalents. Some are single-byte changes from `08`
to `0B` because only the low byte of the version differs.

The second, older 9.1 code path in the binary is not modified. The tested
`h264nvenc_probe` and recording path use the 8.1 path after patching. Modifying
the 9.1 path without a test case would add risk without evidence of benefit.

## VHMediaCOM.dll

The installed `VHMediaCOM.dll` contains additional NVENC-related strings and
preset GUIDs, but in the tested build the actual recording encoder runs inside
`VHMultiWriterExt2.exe`. Patching only the executable is sufficient for
recording. `VHMediaCOM.dll` is intentionally left untouched.

## Probe behavior

The diagnostic command:

```powershell
& "C:\Program Files\Logitech\LogiCapture\bin\VHMultiWriterExt2.exe" h264nvenc_probe
```

returns exit code `2` and prints `SUCCEEDED` on success. The probe initializes
the NVENC session and preset configuration; it does not prove that a complete
encode works. A real recording is the final test.

During a successful recording, the encoder process loads:

```text
nvEncodeAPI64.dll
nvcuda.dll
nvcuda64.dll
```

and the output MP4 contains an H.264 video track (`avc1`).

## Error codes seen during development

| Code | Meaning |
|---|---|
| `0x0` | Success |
| `0x8` | `NV_ENC_ERR_INVALID_PARAM` |
| `0xC` | `NV_ENC_ERR_UNSUPPORTED_PARAM` |
| `0xF` | `NV_ENC_ERR_INVALID_VERSION` |

## Why API 11.1

The driver reported a maximum API of 13.1, but using the newest API was not
necessary. API 11.1 is the first version that matches the structure layouts used
by this code path after the version changes, and it is accepted by the driver in
the tested configuration. The exact version choice is part of the tested patch
set; do not change it without re-verifying the probe and a real recording.
