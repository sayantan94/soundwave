import AVFoundation
import AudioToolbox
import CoreAudio
import SoundWaveCore

enum SensorError: LocalizedError {
    case unavailable(String)
    var errorDescription: String? {
        switch self { case .unavailable(let message): return message }
    }
}

final class AudioSensor {
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?
    private let analysisQueue = DispatchQueue(label: "soundwave.analysis", qos: .userInitiated)
    private let pending = DispatchSemaphore(value: 3)

    func start(frequency: Double, amplitude: Double, sensitivity: Double,
               onDetection: @escaping (Detection) -> Void,
               onChange: @escaping () -> Void) throws -> String {
        stop()
        if let issue = Self.outputIssue() { throw SensorError.unavailable(issue) }
        let audio = AVAudioEngine()
        let input = audio.inputNode
        let output = audio.outputNode
        // AVAudioEngine pairs separate default input/output devices internally.
        // Assigning each I/O node's CurrentDevice breaks that pairing on MacBooks.
        let inputDevice = try Self.defaultBuiltInDevice(input: true)
        let outputDevice = try Self.defaultBuiltInDevice(input: false)
        let inputFormat = input.outputFormat(forBus: 0)
        let outputFormat = output.inputFormat(forBus: 0)
        guard inputFormat.channelCount > 0, outputFormat.channelCount > 0,
              inputFormat.sampleRate >= 44100, outputFormat.sampleRate >= 44100,
              frequency + 1000 < min(inputFormat.sampleRate, outputFormat.sampleRate) / 2,
              let toneFormat = AVAudioFormat(standardFormatWithSampleRate: outputFormat.sampleRate, channels: 1) else {
            throw SensorError.unavailable("The audio devices need a sample rate of at least 44.1 kHz. Check Audio MIDI Setup.")
        }
        let detector = DopplerDetector(sampleRate: inputFormat.sampleRate, frequency: frequency)
        detector.sensitivity = sensitivity
        var phase = 0.0
        var ramp = 0.0
        let increment = 2 * Double.pi * frequency / outputFormat.sampleRate
        let level = min(0.3, max(0.01, amplitude))
        let source = AVAudioSourceNode(format: toneFormat) { _, _, count, list -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            for frame in 0..<Int(count) {
                ramp = min(1, ramp + 1 / (outputFormat.sampleRate * 0.04))
                let sample = Float(sin(phase) * level * ramp)
                phase += increment
                if phase >= 2 * .pi { phase -= 2 * .pi }
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }
        audio.attach(source)
        audio.connect(source, to: audio.mainMixerNode, format: toneFormat)
        // Only the generated pilot reaches the speakers; microphone audio is never played back.
        let queue = analysisQueue
        let gate = pending
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
            guard let channel = buffer.floatChannelData?[0], gate.wait(timeout: .now()) == .success else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            queue.async {
                defer { gate.signal() }
                let detections = detector.process(samples)
                if let latest = detections.last { onDetection(latest) }
            }
        }
        do {
            audio.prepare()
            try audio.start()
        } catch {
            input.removeTap(onBus: 0)
            audio.stop()
            throw error
        }
        engine = audio
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: audio, queue: .main) { _ in onChange() }
        return "\(inputDevice.1) → \(outputDevice.1)"
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
    }

    static func outputIssue() -> String? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        address.mSelector = kAudioDevicePropertyMute
        address.mScope = kAudioDevicePropertyScopeOutput
        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &address),
           AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr, muted != 0 {
            return "Your Mac’s speakers are muted. Unmute them at a comfortable, low volume, then start again. SoundWave needs to play a tone to detect your hand."
        }
        address.mSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
        var volume = Float32(1)
        size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(device, &address),
           AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr, volume < 0.001 {
            return "Speaker volume is zero. Raise your Mac’s volume a little, then start again."
        }
        return nil
    }

    private static func defaultBuiltInDevice(input: Bool) throws -> (AudioDeviceID, String) {
        var address = AudioObjectPropertyAddress(
            mSelector: input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var bytes = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &bytes, &device) == noErr, device != 0 else {
            throw SensorError.unavailable("No default \(input ? "microphone" : "speakers") available. Check System Settings → Sound.")
        }
        address.mSelector = kAudioDevicePropertyTransportType
        var transport = UInt32(0)
        bytes = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &bytes, &transport) == noErr,
              transport == kAudioDeviceTransportTypeBuiltIn else {
            throw SensorError.unavailable("Select MacBook \(input ? "Microphone under Input" : "Speakers under Output") in System Settings → Sound, then start again. Headphones and external audio devices aren’t supported.")
        }
        address.mSelector = kAudioObjectPropertyName
        var name: Unmanaged<CFString>?
        bytes = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        _ = AudioObjectGetPropertyData(device, &address, 0, nil, &bytes, &name)
        return (device, name?.takeUnretainedValue() as String? ?? "Built-in audio")
    }
}
