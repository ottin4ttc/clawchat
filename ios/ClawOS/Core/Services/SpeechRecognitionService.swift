import Speech
import AVFoundation

@Observable
final class SpeechRecognitionService {
    private(set) var transcribedText: String = ""
    private(set) var isRecording: Bool = false
    private(set) var audioLevel: Float = 0
    var error: SpeechError?

    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    enum SpeechError: LocalizedError {
        case microphoneDenied
        case recognitionDenied
        case recognizerUnavailable
        case recordingFailed(String)

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                "麦克风权限未开启，请在系统设置中允许 ClawOS 访问麦克风"
            case .recognitionDenied:
                "语音识别权限未开启，请在系统设置中允许 ClawOS 使用语音识别"
            case .recognizerUnavailable:
                "语音识别服务暂不可用，请稍后重试"
            case .recordingFailed(let detail):
                "录音失败：\(detail)"
            }
        }
    }

    // MARK: - Permissions

    static func requestPermissions() async -> (mic: Bool, speech: Bool) {
        let mic = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        return (mic, speech)
    }

    // MARK: - Recording

    func startRecording() throws {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        stopRecordingInternal()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if #available(iOS 17, *) {
            request.requiresOnDeviceRecognition = speechRecognizer.supportsOnDeviceRecognition
        }
        recognitionRequest = request

        transcribedText = ""
        error = nil

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, taskError in
            guard let self else { return }
            let transcript = result?.bestTranscription.formattedString
            let shouldStop = taskError != nil || (result?.isFinal ?? false)

            Task { @MainActor [weak self] in
                guard let self else { return }

                if let transcript, transcript != self.transcribedText {
                    self.transcribedText = transcript
                }

                if shouldStop {
                    self.stopRecordingInternal()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    @discardableResult
    func stopRecording() -> String {
        let finalText = transcribedText

        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        let engine = audioEngine
        let request = recognitionRequest
        let task = recognitionTask
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        audioLevel = 0

        Task.detached(priority: .utility) {
            if engine.isRunning {
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
            }
            _ = request
            _ = task
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        return finalText
    }

    private func stopRecordingInternal() {
        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        let engine = audioEngine
        let request = recognitionRequest
        let task = recognitionTask
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        audioLevel = 0

        Task.detached(priority: .utility) {
            if engine.isRunning {
                engine.stop()
                engine.inputNode.removeTap(onBus: 0)
            }
            _ = request
            _ = task
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrtf(sum / Float(max(frames, 1)))
        let db = 20 * log10f(max(rms, 1e-6))
        let normalized = max(0, min(1, (db + 50) / 50))

        Task { @MainActor in
            self.audioLevel = normalized
        }
    }
}
