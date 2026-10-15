import Foundation

enum MediaIntakeFailure: Equatable {
    case unsupportedFiles(supportedExtensions: [String])
    case mediaKindsDisabled
    case emptyFolders(names: [String])
    case folderScanFailed(name: String?, diagnostic: String)
    case sourceUnavailable(name: String?, diagnostic: String)
}

enum MediaIntakeRecoveryAction: String, Equatable {
    case addMedia
    case openAcceptSettings
    case retryRescan
    case revealSource
    case locateSource
    case showDetails
    case cancelIntake

    var title: String {
        switch self {
        case .addMedia: return "Add Media"
        case .openAcceptSettings: return "Open Settings"
        case .retryRescan: return "Retry Rescan"
        case .revealSource: return "Reveal"
        case .locateSource: return "Locate"
        case .showDetails: return "Show Details"
        case .cancelIntake: return "Cancel"
        }
    }
}

enum MediaIntakeRecoveryPersistence: Equatable {
    case untilDismissedOrSuccessfulIntake
}

enum MediaIntakeRecoveryStyle: Equatable {
    case progress
    case warning
    case error
}

struct MediaIntakeRecoveryPresentation: Equatable {
    let title: String
    let message: String
    let details: String
    let actions: [MediaIntakeRecoveryAction]
    let persistence: MediaIntakeRecoveryPersistence
    let style: MediaIntakeRecoveryStyle
    let allowsDismissal: Bool

    static func scanning(folderCount: Int, foundCount: Int = 0) -> MediaIntakeRecoveryPresentation {
        let subject = folderCount == 1 ? "the selected folder" : "\(folderCount) selected folders"
        let message = foundCount > 0
            ? "Found \(countText(foundCount)) \(foundCount == 1 ? "file" : "files") in \(subject). Playback and the queue remain available."
            : "Checking \(subject) for accepted local media. Playback and the queue remain available."
        return .init(
            title: "Scanning Media",
            message: message,
            details: "",
            actions: [.cancelIntake],
            persistence: .untilDismissedOrSuccessfulIntake,
            style: .progress,
            allowsDismissal: false
        )
    }

    /// P138: shown after a large intake while its GIF durations load in the background.
    static func loadingGIFDurations(finished: Int, total: Int) -> MediaIntakeRecoveryPresentation {
        .init(
            title: "Loading Media",
            message: "Reading GIF durations: \(countText(finished)) of \(countText(total)). Playback and the queue remain available.",
            details: "",
            actions: [.cancelIntake],
            persistence: .untilDismissedOrSuccessfulIntake,
            style: .progress,
            allowsDismissal: false
        )
    }

    private static func countText(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }
}

enum MediaIntakeRecoveryMapper {
    static func presentation(for failure: MediaIntakeFailure) -> MediaIntakeRecoveryPresentation {
        let persistence = MediaIntakeRecoveryPersistence.untilDismissedOrSuccessfulIntake
        switch failure {
        case .unsupportedFiles(let extensions):
            let supported = extensions.sorted().joined(separator: ", ")
            return .init(
                title: "Unsupported Media",
                message: "No supported local media was added. Playback and the queue were left unchanged.",
                details: supported.isEmpty ? "The selected files are not supported." : "Supported filename extensions: \(supported)",
                actions: [.addMedia, .showDetails],
                persistence: persistence,
                style: .warning,
                allowsDismissal: true
            )
        case .mediaKindsDisabled:
            return .init(
                title: "Media Type Disabled",
                message: "Matching media is disabled in Accept settings. Playback and the queue were left unchanged.",
                details: "Enable Video, Images, or GIF in Settings > Playback > Accept, then try again.",
                actions: [.openAcceptSettings, .addMedia, .showDetails],
                persistence: persistence,
                style: .warning,
                allowsDismissal: true
            )
        case .emptyFolders(let names):
            let displayNames = names.isEmpty ? "The selected folder" : names.joined(separator: ", ")
            return .init(
                title: "Folder Has No Media",
                message: "\(displayNames) contains no accepted local media. Playback and the queue were left unchanged.",
                details: "The folder scan completed successfully but found no accepted media files.",
                actions: [.addMedia, .revealSource, .showDetails],
                persistence: persistence,
                style: .warning,
                allowsDismissal: true
            )
        case .folderScanFailed(let name, let diagnostic):
            let subject = name.map { "\"\($0)\"" } ?? "the selected folders"
            return .init(
                title: "Folder Scan Failed",
                message: "Could not scan \(subject). Playback and the queue were left unchanged.",
                details: diagnostic,
                actions: [.retryRescan, .locateSource, .showDetails],
                persistence: persistence,
                style: .error,
                allowsDismissal: true
            )
        case .sourceUnavailable(let name, let diagnostic):
            let subject = name.map { "\"\($0)\"" } ?? "The source folder"
            return .init(
                title: "Source Folder Unavailable",
                message: "\(subject) could not be found or opened. Playback and the queue were left unchanged.",
                details: diagnostic,
                actions: [.locateSource, .retryRescan, .showDetails],
                persistence: persistence,
                style: .error,
                allowsDismissal: true
            )
        }
    }
}
