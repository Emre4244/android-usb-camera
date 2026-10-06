# Privacy

The bridge has no analytics, account, cloud service or automatic upload. Screen frames travel from the authorized Android device to this Mac and to the local camera extension. Any local application allowed to read OBS Virtual Camera can potentially receive the bridged screen, just as with other camera devices. Stop the bridge when screen sharing should end.

The app invokes bundled ADB and copies its bundled Android server to a unique file under `/data/local/tmp/`. It uses localhost ADB forwarding, then removes its forwarding entry and temporary server file during normal cleanup. The existing ADB daemon may remain running. Device authorization and camera-extension permissions remain controlled by Android/macOS.

The build script contacts GitHub to download the pinned runtime if it is not already available. Runtime use does not download updates or transmit screen data to GitHub.

If reporting a problem, review logs/screenshots first: they can reveal device identifiers and screen content. Do not upload local OBS configurations or the private working-version backup.
