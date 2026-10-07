import Foundation
import XCTest

final class SettingsDefaultsRegistryTests: XCTestCase {

    func testDefaultValuesPreserveSettingsDefaults() {
        let defaults = SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: true)
        let keys = SettingsDefaultsRegistry.Keys.self

        XCTAssertEqual(defaults[keys.skipDurationSeconds] as? Int, 10)
        XCTAssertEqual(defaults[keys.imageDurationSeconds] as? Int, 3)
        XCTAssertEqual(defaults[keys.gifLoopCount] as? Int, 1)
        XCTAssertEqual(defaults[keys.acceptVideoMedia] as? Bool, true)
        XCTAssertEqual(defaults[keys.acceptImageMedia] as? Bool, true)
        XCTAssertEqual(defaults[keys.acceptGIFMedia] as? Bool, true)
        XCTAssertEqual(defaults[keys.autoHideTitlebar] as? Bool, false)
        XCTAssertEqual(defaults[keys.completeVideoWindowMode] as? Bool, false)
        XCTAssertEqual(defaults[keys.showTitleOverlay] as? Bool, true)
        XCTAssertEqual(defaults[keys.deletePrefixRenameEnabled] as? Bool, false)
        XCTAssertEqual(defaults[keys.videoPageDButtonEnabled] as? Bool, false)
        XCTAssertEqual(defaults[keys.customPrefixValue] as? String, "")
        XCTAssertEqual(defaults[keys.customPrefixSecondaryValue] as? String, "")
        XCTAssertEqual(defaults[keys.debugConsoleEnabled] as? Bool, false)
        XCTAssertEqual(defaults[keys.verboseAutoplayTrace] as? Bool, false)
        XCTAssertEqual(defaults[keys.chromeAutohideThreshold] as? Double, 3.0)
        XCTAssertEqual(defaults[keys.chromeReducedMotion] as? Bool, true)
        XCTAssertEqual(defaults[keys.queuePanelOpenAtLaunch] as? Bool, false)
        XCTAssertEqual(defaults[keys.bottomRailShowXButton] as? Bool, true)
        XCTAssertEqual(defaults[keys.bottomRailShowShuffleButton] as? Bool, true)
        XCTAssertEqual(defaults[keys.bottomRailShowReplayButton] as? Bool, true)
        XCTAssertEqual(defaults[keys.bottomRailShowVolumeButton] as? Bool, true)
        XCTAssertEqual(defaults[keys.bottomRailShowBookmarkButton] as? Bool, true)
        XCTAssertEqual(defaults[keys.playerWindowOpacity] as? Double, 1.0)
    }

    func testDefaultValuesIgnoreRemovedAndLegacyQueueSettings() {
        let defaults = SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)

        XCTAssertNil(defaults["com.dwb.queueColumnDurationVisible"])
        XCTAssertNil(defaults["com.dwb.queueColumnSizeVisible"])
        XCTAssertNil(defaults["com.dwb.queueColumnDurationWidth"])
        XCTAssertNil(defaults["com.dwb.queueColumnSizeWidth"])
    }

    func testDefaultValuesKeepMigratedKeysUnset() {
        let defaults = SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)
        let keys = SettingsDefaultsRegistry.Keys.self

        XCTAssertNil(defaults[keys.customPrefixQueuePageEnabled])
        XCTAssertNil(defaults[keys.persistedVolume])
    }

    func testReduceMotionDefaultComesFromCaller() {
        let keys = SettingsDefaultsRegistry.Keys.self

        XCTAssertEqual(
            SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: true)[keys.chromeReducedMotion] as? Bool,
            true
        )
        XCTAssertEqual(
            SettingsDefaultsRegistry.defaultValues(reduceMotionDefault: false)[keys.chromeReducedMotion] as? Bool,
            false
        )
    }

    func testRegisterDefaultsUsesRegistrationDomainWithoutOverwritingStoredValues() {
        let suiteName = "com.dwb.test.SettingsDefaultsRegistryTests"
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: false)

        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.skipDurationSeconds), 10)
        XCTAssertEqual(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.acceptVideoMedia), true)
        XCTAssertEqual(defaults.bool(forKey: SettingsDefaultsRegistry.Keys.chromeReducedMotion), false)

        defaults.set(30, forKey: SettingsDefaultsRegistry.Keys.skipDurationSeconds)
        SettingsDefaultsRegistry.register(defaults: defaults, reduceMotionDefault: true)

        XCTAssertEqual(defaults.integer(forKey: SettingsDefaultsRegistry.Keys.skipDurationSeconds), 30)
    }
}
