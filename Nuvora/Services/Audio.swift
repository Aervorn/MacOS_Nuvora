import AVFoundation
import Foundation
import Observation
import Speech

/// Enregistrement d'une note vocale (AAC, mono), avec le niveau du micro.
@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Niveau du micro entre 0 et 1
    private(set) var level: Float = 0
    /// Derniers niveaux, pour l'animation
    private(set) var levels: [Float] = Array(repeating: 0, count: 40)

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private(set) var fileURL: URL?

    enum RecorderError: LocalizedError {
        case microphoneDenied, cannotStart

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                String(localized: "Nuvora n'a pas accès au micro. Autorise-le dans Réglages Système › Confidentialité et sécurité › Micro.")
            case .cannotStart:
                String(localized: "L'enregistrement n'a pas pu démarrer.")
            }
        }
    }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(to url: URL) async throws {
        guard await Self.requestPermission() else { throw RecorderError.microphoneDenied }
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.cannotStart }
        self.recorder = recorder
        fileURL = url
        isRecording = true
        elapsed = 0
        levels = Array(repeating: 0, count: levels.count)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0) // de -160 à 0
        level = max(0, min(1, (db + 50) / 50))
        levels.removeFirst()
        levels.append(level)
        elapsed = recorder.currentTime
    }

    /// Arrête l'enregistrement et renvoie sa durée.
    @discardableResult
    func stop() -> TimeInterval {
        let duration = recorder?.currentTime ?? elapsed
        recorder?.stop()
        finish()
        return duration
    }

    /// Arrête et supprime l'enregistrement.
    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        fileURL = nil
        finish()
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        isRecording = false
        level = 0
    }
}

/// Lecture des notes vocales : une seule à la fois.
@MainActor
@Observable
final class AudioPlayback {
    static let shared = AudioPlayback()

    private(set) var currentID: UUID?
    private(set) var isPlaying = false
    /// Avancement entre 0 et 1
    private(set) var progress: Double = 0
    private(set) var currentTime: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?

    private init() {}

    func toggle(_ id: UUID, url: URL) {
        if currentID == id, let player {
            if player.isPlaying { pause() } else { resume() }
            return
        }
        play(id, url: url, from: 0)
    }

    /// Lit depuis une position (entre 0 et 1), par exemple après un clic sur la forme d'onde
    func seek(_ id: UUID, url: URL, to fraction: Double) {
        if currentID == id, let player {
            player.currentTime = player.duration * min(max(fraction, 0), 1)
            if !player.isPlaying { resume() }
            update()
        } else {
            play(id, url: url, from: fraction)
        }
    }

    func stop() {
        player?.stop()
        player = nil
        timer?.invalidate()
        timer = nil
        currentID = nil
        isPlaying = false
        progress = 0
        currentTime = 0
    }

    func stopIfPlaying(_ ids: Set<UUID>) {
        if let currentID, ids.contains(currentID) { stop() }
    }

    private func play(_ id: UUID, url: URL, from fraction: Double) {
        stop()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.prepareToPlay()
        player.currentTime = player.duration * min(max(fraction, 0), 1)
        self.player = player
        currentID = id
        resume()
    }

    private func resume() {
        guard let player else { return }
        player.play()
        isPlaying = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        guard let player else { return }
        currentTime = player.currentTime
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
        if !player.isPlaying && isPlaying {
            // Fin de la lecture
            isPlaying = false
            progress = 0
            currentTime = 0
            timer?.invalidate()
            timer = nil
        }
    }
}

/// Transcription des notes vocales, uniquement sur le Mac (jamais envoyée à un serveur).
enum Transcriber {
    enum TranscriptionError: LocalizedError {
        case denied, unavailable, onDeviceUnsupported, empty

        var errorDescription: String? {
            switch self {
            case .denied:
                String(localized: "Nuvora n'a pas accès à la reconnaissance vocale. Autorise-la dans Réglages Système › Confidentialité et sécurité.")
            case .unavailable:
                String(localized: "La reconnaissance vocale n'est pas disponible pour cette langue.")
            case .onDeviceUnsupported:
                String(localized: "La transcription sur le Mac n'est pas disponible pour cette langue. Télécharge-la dans Réglages Système › Clavier › Dictée.")
            case .empty:
                String(localized: "Aucune parole reconnue.")
            }
        }
    }

    /// Langue de transcription : celle choisie dans les réglages, sinon celle de macOS
    static var locale: Locale {
        if let id = UserDefaults.standard.string(forKey: Prefs.transcriptionLocale), !id.isEmpty, id != "system" {
            return Locale(identifier: id)
        }
        return Locale.current
    }

    static func authorize() async -> Bool {
        let status = SFSpeechRecognizer.authorizationStatus()
        if status == .authorized { return true }
        guard status == .notDetermined else { return false }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    @MainActor
    static func transcribe(_ url: URL) async throws -> String {
        guard await authorize() else { throw TranscriptionError.denied }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }
        guard recognizer.supportsOnDeviceRecognition else { throw TranscriptionError.onDeviceUnsupported }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        let box = ResumeOnce()
        let text: String = try await withCheckedThrowingContinuation { continuation in
            box.continuation = continuation
            box.task = recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    box.resume(.success(result.bestTranscription.formattedString))
                } else if let error {
                    box.resume(.failure(error))
                }
            }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.empty }
        return trimmed
    }

    /// La reconnaissance peut rappeler plusieurs fois : on ne reprend la suite qu'une fois.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        var continuation: CheckedContinuation<String, Error>?
        var task: SFSpeechRecognitionTask?

        func resume(_ result: Result<String, Error>) {
            lock.lock()
            let c = continuation
            continuation = nil
            lock.unlock()
            c?.resume(with: result)
        }
    }
}
