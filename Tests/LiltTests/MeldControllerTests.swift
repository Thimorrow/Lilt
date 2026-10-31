import XCTest
@testable import Lilt

final class MeldControllerTests: XCTestCase {
    private func ready(playing: Bool = false, id: String = "one", elapsed: Double = 5) -> MeldReading {
        MeldReading(availability: .ready, id: id, title: "Song", artist: "Artist", queueID: id, duration: 120, elapsed: elapsed, playing: playing, canPlay: true, canPause: true, canNext: true, canPrevious: true)
    }

    func testDecoderRequiresMeldAndNormalizesUnknownDuration() throws {
        var payload = ready().payload
        payload["package"] = "com.meld.app"
        payload["duration"] = -1
        payload["cover"] = "https://example.com/cover.jpg"
        let decoded = try MeldReading.decode(JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.duration, 0)
        XCTAssertNil(decoded.cover)
        payload["package"] = "com.other.player"
        XCTAssertThrowsError(try MeldReading.decode(JSONSerialization.data(withJSONObject: payload)))
        payload["package"] = "com.meld.app"
        payload["playing"] = "yes"
        XCTAssertThrowsError(try MeldReading.decode(JSONSerialization.data(withJSONObject: payload)))
    }

    func testDecoderTreatsEmptySessionAsEmptyAndRejectsBridgeFailure() throws {
        XCTAssertEqual(try MeldReading.decode(Data(#"{"availability":"empty"}"#.utf8)).availability, .empty)
        XCTAssertThrowsError(try MeldReading.decode(Data(#"{"availability":"unavailable","code":"ambiguousSession"}"#.utf8))) { error in
            XCTAssertEqual((error as? MeldControlError)?.code, "ambiguousSession")
        }
    }

    func testCommandsWaitForConfirmationAndDuplicateClicksAreIgnored() {
        let player = HeldMeld()
        let music = MusicCoordinator(player: player)
        music.recheck()
        player.reads.removeFirst()(.success(ready()))
        music.request(.play)
        music.request(.play)
        XCTAssertEqual(player.commands.count, 1)
        XCTAssertFalse(music.reading.playing)
        XCTAssertEqual(music.pending, .play)
        player.commands.removeFirst().1(.success(ready(playing: true)))
        XCTAssertTrue(music.reading.playing)
        XCTAssertNil(music.pending)
        XCTAssertNil(music.error)
    }

    func testReadStartedBeforeUserActionCannotOverwriteItsResult() {
        let player = HeldMeld()
        let music = MusicCoordinator(player: player)
        music.recheck()
        player.reads.removeFirst()(.success(ready()))
        music.recheck()
        music.request(.play)
        XCTAssertEqual(player.commands.count, 0)
        player.reads.removeFirst()(.success(ready(id: "stale")))
        XCTAssertEqual(player.commands.count, 1)
        XCTAssertEqual(music.reading.id, "one")
        player.commands.removeFirst().1(.success(ready(playing: true)))
        XCTAssertTrue(music.reading.playing)
        XCTAssertEqual(music.reading.id, "one")
    }

    func testUnconfirmedCommandNeverClaimsPlayingAndReadOnlyPollRecovers() {
        let player = HeldMeld()
        let music = MusicCoordinator(player: player)
        music.recheck()
        player.reads.removeFirst()(.success(ready()))
        music.request(.play)
        player.commands.removeFirst().1(.success(ready()))
        XCTAssertEqual(music.error, .timeout)
        XCTAssertFalse(music.reading.playing)
        XCTAssertEqual(music.reading.availability, .unavailable)
        music.recheck()
        player.reads.removeFirst()(.success(ready(playing: true)))
        XCTAssertTrue(music.reading.playing)
        XCTAssertEqual(music.error, .timeout)
        XCTAssertTrue(player.commands.isEmpty)
    }

    func testStoppedCoordinatorIgnoresLateReplies() {
        let player = HeldMeld()
        let music = MusicCoordinator(player: player)
        music.recheck()
        music.stop()
        player.reads.removeFirst()(.success(ready(playing: true)))
        XCTAssertEqual(music.reading.availability, .checking)
        XCTAssertFalse(music.reading.playing)
    }

    func testOfflineAndUnsupportedActionsNeverDispatch() {
        let player = HeldMeld()
        let music = MusicCoordinator(player: player)
        music.recheck()
        player.reads.removeFirst()(.failure(.offline))
        music.request(.play)
        XCTAssertEqual(music.reading.availability, .offline)
        XCTAssertTrue(player.commands.isEmpty)
    }

    func testHelperConfirmationUsesTheFreshStateRatherThanAStalePoll() {
        var after = ready(elapsed: 0)
        after.confirmedCommand = .previous
        XCTAssertTrue(after.confirms(.previous, before: ready(elapsed: 0)))
        XCTAssertFalse(after.confirms(.next, before: ready(elapsed: 0)))
    }

    func testSkippingRequiresChangedTrackOrAConfirmedPreviousRestart() {
        let before = ready(elapsed: 12)
        XCTAssertFalse(ready().confirms(.next, before: before))
        XCTAssertTrue(ready(id: "two").confirms(.next, before: before))
        XCTAssertTrue(ready(elapsed: 0).confirms(.previous, before: before))
        XCTAssertFalse(ready(elapsed: 0).confirms(.previous, before: ready(elapsed: 0)))
    }

    func testSourceSwitchDiscardsOldReadsAndClearsPreviousMetadata() {
        let old = HeldMeld()
        let replacement = HeldMeld()
        let music = MusicCoordinator(player: old)
        music.recheck()
        let lateReply = old.reads.removeFirst()
        XCTAssertTrue(music.select(player: replacement))
        replacement.reads.removeFirst()(.success(ready(id: "new-source")))
        lateReply(.success(ready(playing: true, id: "old-source")))
        XCTAssertEqual(music.reading.id, "new-source")
        XCTAssertFalse(music.reading.playing)
        music.request(.play)
        XCTAssertTrue(old.commands.isEmpty)
        XCTAssertEqual(replacement.commands.count, 1)
    }

    func testSourceSwitchIsRefusedUntilPendingCommandFinishes() {
        let old = HeldMeld()
        let replacement = HeldMeld()
        let music = MusicCoordinator(player: old)
        music.recheck()
        old.reads.removeFirst()(.success(ready()))
        music.recheck()
        music.request(.play)
        XCTAssertFalse(music.select(player: replacement))
        old.reads.removeFirst()(.success(ready()))
        XCTAssertEqual(old.commands.count, 1)
        XCTAssertTrue(replacement.reads.isEmpty)
        old.commands.removeFirst().1(.success(ready(playing: true)))
        XCTAssertTrue(music.select(player: replacement))
        XCTAssertEqual(music.reading.availability, .checking)
        XCTAssertTrue(music.reading.title.isEmpty)
        XCTAssertFalse(music.reading.playing)
    }

    func testProviderSpecificOfflineErrorsRemainOffline() {
        let player = HeldMeld()
        let music = MusicCoordinator(player: player)
        music.recheck()
        player.reads.removeFirst()(.failure(MusicSource.spotify.error("offline")))
        XCTAssertEqual(music.reading.availability, .offline)
        XCTAssertTrue(music.error?.message.contains("Spotify") == true)
    }

    func testDisconnectedPlayerClearsOldMetadataArtworkAndCapabilities() {
        let player = HeldMeld()
        let music = MusicCoordinator(player: player)
        music.recheck()
        var connected = ready(playing: true)
        connected.cover = "data:image/jpeg;base64,AA=="
        player.reads.removeFirst()(.success(connected))
        music.recheck()
        player.reads.removeFirst()(.failure(MusicSource.appleMusic.error("offline")))
        XCTAssertEqual(music.reading.availability, .offline)
        XCTAssertTrue(music.reading.title.isEmpty)
        XCTAssertTrue(music.reading.id.isEmpty)
        XCTAssertNil(music.reading.cover)
        XCTAssertFalse(music.reading.canPlay)
        XCTAssertFalse(music.reading.canNext)
        XCTAssertFalse(music.reading.playing)
    }
}

private final class HeldMeld: MeldControlling {
    var reads: [(Result<MeldReading, MeldControlError>) -> Void] = []
    var commands: [(MeldCommand, (Result<MeldReading, MeldControlError>) -> Void)] = []
    func inspect(completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) { reads.append(completion) }
    func perform(_ command: MeldCommand, completion: @escaping (Result<MeldReading, MeldControlError>) -> Void) { commands.append((command, completion)) }
}
