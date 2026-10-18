# Troubleshooting

## The patcher says "Unsupported build"

The installed `VHMultiWriterExt2.exe` does not match the supported LogiCapture
2.08.11 build. The patcher intentionally refuses to guess offsets.

Check the file:

```powershell
Get-Item "C:\Program Files\Logitech\LogiCapture\bin\VHMultiWriterExt2.exe" |
    Select-Object Length, LastWriteTime

Get-FileHash -Algorithm SHA256 "C:\Program Files\Logitech\LogiCapture\bin\VHMultiWriterExt2.exe"
```

Expected original build:

```text
Size:   1000864
SHA256: 1E6671E8427C3A7F7EE6118E12D81E2BC358285EA56117F8EF7C05B6CC5D41A3
```

If the hash is different, the repository does not support that build yet. Do not
force the patch.

## The patcher says "Already patched"

The file hash matches the known patched build. Nothing needs to be done. To
roll back, use `src/unpatch.ps1`.

## Access denied / UAC

Run the script normally. It requests elevation itself:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\patch.ps1
```

If UAC is cancelled, the script exits without changing the file. You can also
start an elevated PowerShell and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\patch.ps1 -NoElevate
```

Do not use `-NoElevate` from a normal shell if the target is under
`C:\Program Files`.

## The file is locked

Close LogiCapture first. The patcher stops these processes automatically:

```text
LogiCapture
LogiCapture.bp
VHMultiWriterExt2
```

If a process restarts immediately, close the LogiCapture window, wait a few
seconds, and retry. Antivirus or endpoint protection may also block writes to
`Program Files`.

## Probe still fails

Run the probe directly:

```powershell
& "C:\Program Files\Logitech\LogiCapture\bin\VHMultiWriterExt2.exe" h264nvenc_probe
$LASTEXITCODE
```

Expected:

```text
SUCCEEDED
2
```

If it returns another code:

- Check the NVIDIA driver is installed and the GPU is visible.
- Check that the patcher reported `Patched successfully`.
- Run `src/verify.ps1` and confirm the status is `patched`.
- Restore the backup and re-apply to rule out a partial write.

## Recording works, but the camera is not detected

This is usually unrelated to NVENC. LogiCapture can fail to open a camera when it
is in use by another application. Close browser camera tests, Windows Camera,
SplitCam previews, and other capture applications, then restart LogiCapture.

Windows camera privacy settings must also allow desktop applications:

```text
Settings -> Privacy & security -> Camera
```

## The recording is empty or very small

Start the recording, wait several seconds, then stop it with `Alt+R`. A valid
short test clip should be several megabytes. Check that the output folder exists:

```text
HKCU\Software\Logitech\Capture\recordingsLocation
```

The default is under `Videos\Logitech\LogiCapture`.

## LogiCapture was updated and the patch disappeared

Any update or repair that replaces `VHMultiWriterExt2.exe` removes the patch.
Run `src/verify.ps1` again. If the new build hash is unsupported, do not re-apply
the old offsets.

## The patcher log

Logs are written to:

```text
%LOCALAPPDATA%\LogiCaptureNVENC\patch.log
```

Backups are written to:

```text
%LOCALAPPDATA%\LogiCaptureNVENC\backup
```

## Restoring manually

If the scripts cannot run, restore the latest `.bak` file over
`VHMultiWriterExt2.exe` while LogiCapture is closed:

```powershell
$target = "C:\Program Files\Logitech\LogiCapture\bin\VHMultiWriterExt2.exe"
$backup = Get-ChildItem "$env:LOCALAPPDATA\LogiCaptureNVENC\backup\VHMultiWriterExt2.exe.*.bak" |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

Copy-Item -LiteralPath $backup.FullName -Destination $target -Force
```
