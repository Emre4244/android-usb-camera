# Release preparation — 0.2.0 preview

## Prepared

- Generic ADB device discovery; no fixed serial or model whitelist.
- Device-reported hardware H.264 encoder selection; explicit rejection of software-only devices.
- Pinned scrcpy 5.0 server protocol, unique sockets and temporary server filenames.
- Hardware-required VideoToolbox and GPU conversion.
- Existing OBS camera extension backend and documented producer conflict.
- macOS 13 arm64 deployment target; checksum-verified runtime download.
- Source, build script, parser checks, licenses, user instructions and troubleshooting.
- Separate working-version backup. Private backup files are not included in this public source/package.

## Before advertising a general-public installer

1. Choose final project owner/name and repository URL. The project can be published as a source/developer preview with its limitations stated. The binary preview is not notarized.
2. Build with a valid **Developer ID Application** identity, sign nested executable code, sign the app with hardened runtime, and verify it. Apple Development signing is not equivalent to public Developer ID distribution.
3. Submit a zip using Apple's `notarytool`, wait for an Accepted result, and staple the ticket to the app. Store notarization credentials in the release owner's keychain or CI secrets, never in this repository. Create the distribution zip after stapling and verify Gatekeeper on a clean machine.
4. Verify clean install on the supported macOS versions. Current physical tests cover one M4 Mac, OBS 32.2.2 and two Qualcomm Android 16 devices. The declared macOS 13 minimum is a deployment target, not a claim that every older OS has already been tested.
5. Test real MediaTek/Exynos hardware, multiple identical device models, USB authorization denied/offline states, unplug/replug, portrait/landscape changes, sleep/wake, and OBS camera-producer conflict.
6. Validate OBS extension behavior across the OBS versions the release advertises. This preview depends on OBS's existing camera extension. A standalone camera named Android USB Camera requires a separate extension, signing/provisioning and user activation.
7. Run controlled sustained FPS, dropped-frame, end-to-end latency and power comparisons before making performance claims. Do not describe camera pacing as unique-frame FPS.

Reference: [Apple macOS notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

No GitHub repository, release, account, payment, telemetry service or public upload has been created by this preparation task.
