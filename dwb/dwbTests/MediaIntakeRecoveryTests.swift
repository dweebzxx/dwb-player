import Foundation
import XCTest

final class MediaIntakeRecoveryTests: XCTestCase {
    func testUnsupportedFilesMappingIsPersistentAndLocal() {
        let result = MediaIntakeRecoveryMapper.presentation(
            for: .unsupportedFiles(supportedExtensions: ["mov", "mp4"])
        )
        XCTAssertEqual(result.title, "Unsupported Media")
        XCTAssertTrue(result.message.contains("queue were left unchanged"))
        XCTAssertEqual(result.actions, [.addMedia, .showDetails])
        XCTAssertEqual(result.persistence, .untilDismissedOrSuccessfulIntake)
        XCTAssertEqual(result.style, .warning)
        XCTAssertTrue(result.allowsDismissal)
        XCTAssertTrue(result.details.contains("mov, mp4"))
    }

    func testDisabledKindsPointsToAcceptSettingsWithoutChangingSettings() {
        let result = MediaIntakeRecoveryMapper.presentation(for: .mediaKindsDisabled)
        XCTAssertEqual(result.title, "Media Type Disabled")
        XCTAssertEqual(result.actions, [.openAcceptSettings, .addMedia, .showDetails])
        XCTAssertTrue(result.details.contains("Settings > Playback > Accept"))
    }

    func testEmptyFolderOffersLocalRecovery() {
        let result = MediaIntakeRecoveryMapper.presentation(for: .emptyFolders(names: ["Clips"]))
        XCTAssertEqual(result.title, "Folder Has No Media")
        XCTAssertEqual(result.actions, [.addMedia, .revealSource, .showDetails])
        XCTAssertTrue(result.message.contains("Clips"))
    }

    func testFailedScanOffersRetryLocateAndDetails() {
        let result = MediaIntakeRecoveryMapper.presentation(
            for: .folderScanFailed(name: "Clips", diagnostic: "Permission denied")
        )
        XCTAssertEqual(result.actions, [.retryRescan, .locateSource, .showDetails])
        XCTAssertEqual(result.style, .error)
        XCTAssertEqual(result.details, "Permission denied")
    }

    func testUnavailableSourceOffersLocateAndRetry() {
        let result = MediaIntakeRecoveryMapper.presentation(
            for: .sourceUnavailable(name: "Archive", diagnostic: "Folder no longer exists")
        )
        XCTAssertEqual(result.title, "Source Folder Unavailable")
        XCTAssertEqual(result.actions, [.locateSource, .retryRescan, .showDetails])
        XCTAssertTrue(result.message.contains("queue were left unchanged"))
    }

    func testScanningPresentationIsInformationalAndNonDismissible() {
        let result = MediaIntakeRecoveryPresentation.scanning(folderCount: 2)
        XCTAssertEqual(result.title, "Scanning Media")
        XCTAssertTrue(result.message.contains("2 selected folders"))
        XCTAssertEqual(result.actions, [])
        XCTAssertEqual(result.style, .progress)
        XCTAssertFalse(result.allowsDismissal)
    }
}
