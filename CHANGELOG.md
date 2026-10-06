# Changelog

## 0.2.0 — developer preview

- Discover authorized Android devices without a model whitelist or fixed serial.
- Query and select device-reported hardware H.264 encoders.
- Scan connected devices in the background every three seconds.
- Use unique connection sockets and server filenames.
- Stop camera publishing when the video stream fails.
- Add a standard Quit menu, English UI, macOS 13 arm64 target, and reproducible runtime download.
- Document the existing OBS camera backend, distribution limitations, privacy and release process.

## Working local prototype

- Astra and S24 Ultra tested through the OBS Virtual Camera sink on this Mac.
- Hardware Android encoding, VideoToolbox decoding and Metal conversion.
- One camera output with selectable device; no desktop/window capture.
