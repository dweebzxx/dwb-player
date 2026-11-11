import Foundation
import VLCKitSPM

extension VLCMedia: MediaOptionAdding {}

extension VLCMedia {
    /// The one place a `VLCMedia` is built for a player. Every assignment goes through here so the
    /// reuse, handshake-recovery, and fresh-player paths cannot drift apart.
    /// addOption only records the option on the media; unlike the audio volume setter it writes no
    /// libvlc config, so it is safe on the reuse path (P50).
    static func forPlayback(url: URL, site: MediaAssignmentSite) -> VLCMedia {
        let media = VLCMedia(url: url)
        AV1DecoderPreference.apply(to: media)
        NSLog("[dwb-playback] %@", AV1DecoderPreference.requestLogLine(site: site, mediaName: url.lastPathComponent))
        return media
    }
}
