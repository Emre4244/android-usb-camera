# Android USB Camera

**Android screen → USB → a video capture device on macOS. No window capture.**

0.2.0 is a **developer preview**. The bridge uses hardware H.264 encoding on Android, Apple VideoToolbox hardware decoding, and Metal frame conversion. It sends frames directly to the sink of the already-installed **OBS Virtual Camera** extension. It does not install its own camera driver or modify OBS.

## Requirements

- Apple Silicon Mac. The bridge executable targets macOS 13+. Functional testing so far used one M4 Mac on macOS 27; older supported deployment targets have not been device-tested.
- OBS Studio with **OBS Virtual Camera extension installed and enabled**. OBS 32.2.2 is the version tested.
- Android device with USB debugging authorized and a reported H.264 hardware encoder. Device discovery is not restricted by brand or model; encoder, firmware and screen-capture compatibility still varies. Actual device tests: REDMAGIC Astra and Samsung S24 Ultra, both Android 16.
- USB data cable. 5/10 Gbit/s is not a requirement for the compressed video stream.

ADB and the scrcpy 5.0 Android server are bundled. FFmpeg, SDL, Homebrew and a desktop scrcpy installation are not required by the bridge. There is no telemetry or automatic upload.

## Use

1. Unlock your Android device, enable USB debugging, connect it, and approve the Mac's ADB authorization request on the device.
2. Open **Android USB Camera**. It scans for authorized ADB devices every three seconds and starts the first available device on initial detection. Select another device from the picker when needed.
3. In OBS add **Video Capture Device**, select **OBS Virtual Camera**, and leave buffering disabled if low latency is desired.
4. **Keep OBS's Start Virtual Camera output OFF.** This bridge owns the producer side of that camera while running. Starting OBS's own camera output competes for the same sink and can cause a blank image or feedback.
5. Use Stop/Start to retry or stop the stream. Closing the app stops the bridge. Its status window is not captured and may be minimized.

To enable the existing camera extension, follow the [OBS instructions](https://obsproject.com/kb/virtual-camera-troubleshooting). This bridge does not bypass system security settings.

## Compatibility and limitations

- The app queries the device's actual encoder list, prefers native Codec2 vendor H.264 hardware, then other vendor hardware. Qualcomm, MediaTek and Exynos names are handled by capability parsing rather than a device whitelist. Only Qualcomm devices have been physically tested; parser fixtures for the other vendors are not hardware validation.
- Software-only encoders are rejected explicitly. Some older Android firmware may not report hardware classification and can be rejected even if suitable hardware exists. Support for every Android device is not claimed.
- One device feeds one virtual camera at a time. Two separate simultaneous video capture devices require a dedicated multi-device camera extension or another backend.
- Capture is capped at 2400 pixels on the long edge, 60 FPS, 24 Mbit/s H.264. Output is fixed 1920×1080 BGRA with aspect-fit black bars. Orientation/encoding-session changes reset the decoder while preserving the output camera format.
- The last converted frame is paced to the camera at 60 Hz. This does not guarantee 60 new Android frames per second. Static Android screens normally produce very few new frames.
- Audio, Android input control, HEVC, HDR, Intel Macs and independent camera driver installation are not included.
- This is not end-to-end zero-copy: compressed packet data is copied and NV12 is converted to BGRA on the GPU. No full-frame CPU RGB conversion or software video decoder is used.
- Private/DRM-protected Android surfaces may not be capturable. Sustained performance, latency and total system power consumption are not yet benchmarked.
- The downloadable preview is ad-hoc signed, **not Developer ID signed or notarized**. It is not a finished general-public macOS installer. Do not disable Gatekeeper or SIP to use it; build from source or wait for the signed release.

## Build from source

With Xcode tools installed:

```sh
./build.command
```

The script downloads the official scrcpy 5.0 arm64 runtime, verifies its pinned SHA-256, and bundles only ADB, the Android server and its license. Build products go to a temporary directory; the zip is placed beside the source folder. An already-extracted runtime directory can be supplied as the first argument. Source files do not contain device serial numbers, account identities, or local OBS configuration.

For compatibility/parser checks:

```sh
swiftc -target arm64-apple-macos13.0 ScreenReceiver.swift tests/main.swift -o /tmp/android-camera-tests
/tmp/android-camera-tests
```

`SIGNING_IDENTITY` can be supplied for a Developer ID release build. That requires a valid signing identity; the script does not invent credentials or perform notarization. See [RELEASE.md](RELEASE.md) for the remaining release work.

## How it works

```text
Android display Surface
  → device-reported hardware H.264 encoder
  → scrcpy 5.0 packet protocol over ADB USB forwarding
  → hardware-required VideoToolbox NV12 decoder
  → Metal / Core Image aspect-fit conversion
  → existing OBS Camera Extension sink
  → Video Capture Device input in OBS
```

Frames and camera queues are bounded; compressed packets are not arbitrarily dropped. Each connection uses a unique socket ID and a unique temporary Android server file. On disconnect the sender is stopped; it does not silently keep publishing an old frame indefinitely. Restarting is supported. Launch/connect discovery is automatic; recovery after a stream error may require Start/Refresh.

## Attribution

Independent bridge project, not an official Genymobile, OBS or Qualcomm product. [scrcpy](https://github.com/Genymobile/scrcpy) is used under Apache-2.0. The installed OBS extension is used through Core Media I/O; it is not redistributed or modified. The MIT [cameraextension example](https://github.com/ldenoue/cameraextension) by Laurent Denoue informed the initial sink integration; its notice is retained in `third-party/`. Bridge code is MIT licensed.
