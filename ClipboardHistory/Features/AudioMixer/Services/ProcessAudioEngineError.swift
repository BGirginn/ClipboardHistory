import Foundation

enum ProcessAudioEngineError: LocalizedError, Equatable {
    case outputDeviceUnavailable
    case outputDeviceIdentifierUnavailable
    case tapCreationFailed(OSStatus)
    case aggregateDeviceCreationFailed(OSStatus)
    case ioProcedureCreationFailed(OSStatus)
    case deviceStartFailed(OSStatus)
    case unsupportedStreamFormat

    var errorDescription: String? {
        switch self {
        case .outputDeviceUnavailable:
            String(localized: "The default audio output device is unavailable.")
        case .outputDeviceIdentifierUnavailable:
            String(localized: "The output device identifier could not be read.")
        case .tapCreationFailed:
            String(localized: "System Audio Recording permission is required or the app audio tap could not start.")
        case .aggregateDeviceCreationFailed:
            String(localized: "The private audio routing device could not be created.")
        case .ioProcedureCreationFailed:
            String(localized: "The real-time audio processor could not be created.")
        case .deviceStartFailed:
            String(localized: "The processed audio output could not be started.")
        case .unsupportedStreamFormat:
            String(localized: "This audio stream format is unsupported; native audio was restored.")
        }
    }
}
