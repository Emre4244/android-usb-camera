# Validation record — 6 October 2026

- Working-version backup: application signature verified; ZIP integrity and all 15 backed-up file hashes checked. Private OBS scene included only in the private backup, not in the public source/app archives.
- Seven parser/compatibility checks passed: native Qualcomm preference, generic MediaTek, generic Exynos, software rejection, wrong-codec rejection, empty input rejection, mixed Annex-B start codes.
- Generic build compiles for arm64 macOS 13; Mach-O deployment target checked as 13.0.
- Ad-hoc code signature verified including nested code/resources.
- Generic app discovered connected Samsung SM-S928B without a fixed serial number or device-name whitelist.
- H.264 encoder enumeration was performed directly through the bundled scrcpy Android server; the desktop scrcpy executable is not bundled or required.
- Hardware-required VideoToolbox decoder verified at runtime.
- OBS Video Capture Device preview and main scene visibly received the Samsung screen. An observed snapshot reported 60 new decoded frames/s, 6088 camera frames sent, and zero camera queue drops. This snapshot is not a sustained performance benchmark.
- The original working app remains installed separately and the source was not overwritten.

Unverified: real non-Qualcomm devices, older macOS deployment targets, Intel Macs, clean-machine notarized installation, multiple simultaneous camera outputs, controlled latency/power measurements. A parser fixture for a vendor does not prove that vendor's hardware compatibility.
