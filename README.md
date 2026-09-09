# SoundWave for Mac

A native macOS experiment that uses the **built-in speaker and microphone**, with **no camera**, to navigate with toward/away hand motion. Inspired by [SoundWave (Microsoft Research, CHI 2012)](https://www.microsoft.com/en-us/research/project/soundwave-using-the-doppler-effect-to-sense-gestures/). This is an independent implementation, not Microsoft software or a complete reproduction of the research system.

## Run

Open `dist/SoundWave.app`, or the installed copy in `~/Applications/SoundWave.app`.

1. Select your Mac’s built-in speakers and microphone in **System Settings → Sound**. Start with moderate system speaker volume. Headphones won’t work for acoustic hand sensing; the app uses the system’s default audio pair and checks that both devices are built-in.
2. Select an action, click **Start gesture control**, and allow **Microphone** and **Accessibility** access. Keep your hands still for about three seconds of calibration. Control turns on once calibration and permissions are ready.
3. Hold an open palm about 15–40 cm above the keyboard, near the speakers. Make a deliberate push toward the Mac or pull away. Watch the **Motion** indicator. Return your hand slowly to avoid an opposite gesture.
4. Open your PDF reader or browser and place the pointer over the document for scrolling. Keyboard actions go to the active app. Confirm the app status says **Gesture control on**.
5. Use **Preview only** when you want to inspect the audio signal without sending actions; enable **Control my Mac** when ready.

If neither PDF scrolling nor desktop switching works, use **Test action in 5 seconds**, then click the PDF or target app during the countdown. This sends one action independently of the audio detector. Gesture control pauses during the test. If the test works, check the tone, Motion indicator, and control status. If it doesn’t, check Accessibility access and the reader’s or Mission Control’s keyboard shortcuts.

For **Switch desktops**, the test can run while SoundWave is the active app. It sends Control–Right; use **Reverse direction** to test Control–Left if you’re already at the last desktop. If Accessibility is enabled but macOS still caches an event-posting denial, use **Apply permission & restart**. The app only enables control when both permission checks pass.

**Stop from any app: Control–Option–Command–S (⌃⌥⌘S).** You can also use the menu-bar waveform icon. Stopping sensing releases the microphone and stops the tone; disabling control keeps the signal preview running. Closing the window leaves the menu-bar app running. Quit to stop everything.

## Actions

| Mode | Toward | Away | Requirements |
| --- | --- | --- | --- |
| Scroll vertically | Down | Up | Pointer over a scrollable page or PDF |
| Turn PDF pages | Page Down | Page Up | Active reader must support these keys; continuous readers may move by one viewport |
| Switch desktops | Control–Right | Control–Left | Enable Mission Control’s move-left/right-a-space shortcuts in System Settings → Keyboard → Keyboard Shortcuts |
| Switch apps | Command–Tab | Command–Shift–Tab | Operates the macOS app switcher; repeated forward gestures may toggle the two most recent apps |
| Scroll horizontally | Right | Left | Pointer over content that supports horizontal scrolling |
| Zoom in / out | Command–Plus | Command–Minus | Active app must support these shortcuts; key mappings assume a US-compatible keyboard layout |

**Reverse direction** swaps the mappings. Discrete actions require a neutral pause of at least 0.3 seconds and have a 0.8-second cooldown. Scroll mode responds continuously to motion and suppresses quick return strokes. Settings for tone and sensitivity are adjustable while sensing is stopped; speed and action can change while running.

## Signal setup and limits

- Default tone: 20 kHz. If calibration fails, stop sensing and try **19 kHz**, then adjust tone level or Mac speaker volume gradually. The app doesn’t change your system volume.
- Speakers must be **unmuted**, with volume above zero. The app checks this before starting and stops with a clear message if output is muted during sensing.
- A near-ultrasonic tone can still be audible to some people. Stop or reduce the level if it’s audible or uncomfortable.
- Keep microphone mode on **Standard**, if macOS offers that setting. Voice isolation, noise suppression, music, nearby movement, and room reflections can interfere.
- Keep your MacBook’s lid open: [Apple silicon MacBooks disconnect the built-in microphone when the lid is closed](https://support.apple.com/en-euro/guide/security/secbbd20b00b/web).
- The app requires a clear pilot tone before calibration can complete, and motion control stays disabled during calibration. Calibration times out after 18 seconds without success.
- Audio route changes, loss of microphone input, and sleep stop sensing. Start again to recalibrate.
- This detects radial motion, not finger poses or exact hand position. It cannot distinguish arbitrary left/right/up/down hand movements, steer a mouse pointer, drag windows, or control every UI element. Modes map the detectable push/pull motion to useful navigation actions.
- Acoustic performance needs a real hand test on your Mac. Automated tests verify the signal processing using synthesized tones and Doppler echoes, not recognition accuracy in a room.

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
