# Developing SoundWave

## Build and test

Requires macOS 13+ and Xcode or Command Line Tools with Swift 5.9+; no third-party dependencies.

```sh
swift test
zsh scripts/build.sh
open dist/SoundWave.app
```

The script builds for the current Mac architecture, creates the app icon and bundle, and signs it using an existing local Apple Development certificate when available, falling back to ad-hoc signing. Set `SOUNDWAVE_SIGNING_IDENTITY` to override the identity. This is not a notarized distribution build. Microphone permission belongs to the bundled app; use the `.app` instead of `swift run`. Switching signing identities or rebuilding an ad-hoc signed app may require granting permissions again; using the same development certificate keeps the app’s signing identity stable across subsequent builds.

## Implementation

`AVAudioEngine` emits a continuous tone through an `AVAudioSourceNode` and captures microphone samples without playing them back. A bounded serial analysis queue runs 4096-sample Hann-windowed FFTs with 1024-sample hops, using Accelerate. Calibration measures the relative background spectrum. Motion detection compares excess energy on either side of the pilot, excludes a 75 Hz region around it, checks signal quality, rejects ambiguous bidirectional motion, and requires three consecutive agreeing frames. This is inspired by the Doppler principle in the paper, with a different calibrated detection algorithm.

`CGEvent` sends pixel scrolling and keyboard shortcuts. A Carbon hotkey provides a global stop without installing a keyboard event tap. The audio engine is only started by the user. Audio samples stay in memory for analysis; there is no audio recording, network client, camera access, telemetry, or external service.

Desktop shortcuts include the Fn/numeric-pad flags that macOS attaches to arrow keys, plus explicit timed modifier press/release events. The `--test-desktop /absolute/path/report.json` diagnostic tests both directions and counts actual `NSWorkspace.activeSpaceDidChangeNotification` events; it does not start audio. The desktop-switch fix was verified on this Mac with two commands producing two Space-change notifications.

Reference: Gupta, Morris, Patel, and Tan, [“SoundWave: Using the Doppler Effect to Sense Gestures,” CHI 2012](https://www.microsoft.com/en-us/research/wp-content/uploads/2012/05/guptasoundwavechi2012.pdf).

For local troubleshooting, launch with `--diagnostics /absolute/path/status.json` to write current signal levels, permissions, control state, and event counters twice a second. This opt-in report contains no audio or document content. `--audio-check /absolute/path/report.json` runs a seven-second sensing check (only if microphone permission is already granted), writes the same status, and exits without enabling gesture actions.
