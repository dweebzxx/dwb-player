import Foundation

/// Anything media options can be added to. `VLCMedia` conforms in `VLCMedia+DecoderPreference.swift`;
/// tests use a fake.
protocol MediaOptionAdding: AnyObject {
    func addOption(_ option: String)
}

/// The three ways the player assigns a new media object to a player.
enum MediaAssignmentSite: String, CaseIterable {
    case reuse = "reuse"
    case handshakeRecovery = "handshake-recovery"
    case freshPlayer = "fresh-player"
}

/// P143: VLC's bundled dav1d crashes on some AV1 streams (`dav1d-worker`, inter-frame prediction),
/// so every media assigned to a player asks VLC to try its bundled libaom decoder first.
/// `codec` is VLC's "preferred decoders list": the named modules are tried first and every other
/// decoder stays in the normal order behind them. Only the `aom` module opens AV1, so other
/// codecs are decoded as before. This is a per-media option, not a library setting.
enum AV1DecoderPreference {
    static let option = ":codec=aom"

    static func apply(to media: MediaOptionAdding) {
        media.addOption(option)
    }

    /// The `[dwb-playback]` line for a media that asked for the preference. "requested" is
    /// deliberate: the log does not show which decoder VLC then used.
    static func requestLogLine(site: MediaAssignmentSite, mediaName: String) -> String {
        "decoderPreference: requested av1=libaom option=\(option) site=\(site.rawValue) media=\(mediaName)"
    }
}
