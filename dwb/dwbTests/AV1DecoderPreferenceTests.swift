import XCTest

final class AV1DecoderPreferenceTests: XCTestCase {

    private final class FakeMedia: MediaOptionAdding {
        var options: [String] = []
        func addOption(_ option: String) { options.append(option) }
    }

    func testOptionPrefersTheAomModuleOnly() {
        XCTAssertEqual(AV1DecoderPreference.option, ":codec=aom")
    }

    func testApplyAddsExactlyTheOptionOnce() {
        let media = FakeMedia()
        AV1DecoderPreference.apply(to: media)
        XCTAssertEqual(media.options, [":codec=aom"])
    }

    func testApplyNeverNamesDav1dOrAnyOtherDecoder() {
        let media = FakeMedia()
        AV1DecoderPreference.apply(to: media)
        XCTAssertFalse(media.options.joined().contains("dav1d"))
        XCTAssertFalse(media.options.contains { $0.contains(",") })
    }

    func testAllThreeAssignmentSitesAreCovered() {
        XCTAssertEqual(Set(MediaAssignmentSite.allCases.map(\.rawValue)),
                       ["reuse", "handshake-recovery", "fresh-player"])
    }

    func testEveryAssignmentSiteGetsTheOptionAndALogLine() {
        for site in MediaAssignmentSite.allCases {
            let media = FakeMedia()
            AV1DecoderPreference.apply(to: media)
            XCTAssertEqual(media.options, [":codec=aom"], "site \(site.rawValue)")
            let line = AV1DecoderPreference.requestLogLine(site: site, mediaName: "clip.mp4")
            XCTAssertTrue(line.contains("site=\(site.rawValue)"), line)
        }
    }

    func testLogLineSaysRequestedAndNamesOptionAndMedia() {
        let line = AV1DecoderPreference.requestLogLine(site: .reuse, mediaName: "clip.mp4")
        XCTAssertEqual(line, "decoderPreference: requested av1=libaom option=:codec=aom site=reuse media=clip.mp4")
    }
}
