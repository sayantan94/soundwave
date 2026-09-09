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

`AVAudioEngine` emits a continuous tone through an `AVAudioSourceNode` and captures microphone samples through an `AVAudioSinkNode` without playing them back. The input callback writes timestamped samples to a bounded, single-producer/single-consumer C11 atomic ring. A serial analysis timer drains it every 4 ms and runs Accelerate 4096-sample Hann-windowed FFTs with 512-sample hops. Every FFT frame reaches the gesture recognizer; UI updates are limited to 30 Hz.

Calibration measures the relative background spectrum. Detection compares excess energy on either side of the pilot, excludes bins within 40 Hz (rounded up to a whole bin), checks signal quality, rejects ambiguous bidirectional motion, and requires two agreeing frames. The previous 75 Hz exclusion missed moderate-speed strokes, sometimes leaving only their faster return detectable. This is inspired by the Doppler principle in the paper, with a different calibrated detection algorithm.

Before the FFT, a precomputed complex window shifts the pilot exactly onto its nearest bin. Merely rounding the analysis index gave the two directions unequal exclusion regions and could turn symmetric loudness modulation into a false left gesture. Regression tests cover that failure and equal confidence for opposite echoes at multiple tone frequencies and sample rates.

The timestamp-based recognizer requires consistent direction and confidence, then locks out return strokes until a cooldown and a quiet interval have both passed. Lost or stale audio requires stillness before rearming. Response presets adjust these thresholds. Practice mode shows accepted directions without emitting actions. A nonactivating panel gives immediate gesture feedback across Spaces; it confirms recognition, not whether the target app handled the command.

`CGEvent` sends pixel scrolling and keyboard shortcuts. A Carbon hotkey provides a global stop without installing a keyboard event tap. The audio engine is only started by the user. Audio samples stay in memory for analysis; there is no audio recording, network client, camera access, telemetry, or external service.

Desktop shortcuts include the Fn/numeric-pad flags that macOS attaches to arrow keys, plus explicit timed modifier press/release events. The `--test-desktop /absolute/path/report.json` diagnostic tests both directions and counts actual `NSWorkspace.activeSpaceDidChangeNotification` events; it does not start audio. The desktop-switch fix was verified on this Mac with two commands producing two Space-change notifications.

On the development MacBook Air, the sink delivered 512-frame input blocks with zero dropped samples during the seven-second audio check. Frame age at the model had a 6.4 ms median and 17.4 ms 95th percentile. These measure pipeline delivery, not total hand-to-screen latency. Synthetic waveform tests cover both signs, moderate and faster movements, and return-stroke suppression; physical gesture accuracy still depends on placement and acoustic conditions.

For local troubleshooting, launch with `--diagnostics /absolute/path/status.json` to write current signal levels, permissions, control state, and event counters twice a second. This opt-in report contains no audio or document content. `--audio-check /absolute/path/report.json` runs a seven-second sensing check (only if microphone permission is already granted), writes the same status, and exits without enabling gesture actions.
