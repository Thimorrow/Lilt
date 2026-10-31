import AppKit
import CoreServices
import ImageIO
import XCTest
@testable import Lilt

final class DirectMusicControllerTests: XCTestCase {
    private func code(_ value: String) -> OSType { value.utf8.reduce(0) { ($0 << 8) | OSType($1) } }

    private var definition: MusicScriptingDefinition {
        get throws {
            try MusicScriptingDefinition(data: Data("""
            <dictionary><suite name="Music"><class name="track">
              <property name="name" code="pnam"/><property name="id" code="ID  "/>
              <property name="artist" code="pArt"/><property name="album" code="pAlb"/>
              <property name="duration" code="pDur"/>
            </class><command name="play" code="hookPlay"/><command name="next track" code="hookNext"/></suite></dictionary>
            """.utf8))
        }
    }

    private func properties(duration: Double = 210_000, title: String = "Song") -> NSAppleEventDescriptor {
        let descriptor = NSAppleEventDescriptor.record()
        for (key, value) in [("pnam", title), ("ID  ", "track-1"), ("pArt", "Artist"), ("pAlb", "Album")] {
            descriptor.setDescriptor(NSAppleEventDescriptor(string: value), forKeyword: code(key))
        }
        descriptor.setDescriptor(NSAppleEventDescriptor(double: duration), forKeyword: code("pDur"))
        return descriptor
    }

    func testScriptingDefinitionUsesAppProvidedCodesAndRejectsCorruptXML() throws {
        let parsed = try definition
        XCTAssertEqual(parsed.properties["duration"], code("pDur"))
        XCTAssertEqual(parsed.commands["play"]?.0, code("hook"))
        XCTAssertEqual(parsed.commands["next track"]?.1, code("Next"))
        XCTAssertThrowsError(try MusicScriptingDefinition(data: Data("<dictionary>".utf8)))
    }

    func testSpotifyMillisecondsAndAppleMusicSecondsHaveSameNormalizedResult() throws {
        let spotify = try AppleEventMusicTransport.reading(source: .spotify, properties: properties(), definition: definition, state: code("kPSP"), position: 25)
        let apple = try AppleEventMusicTransport.reading(source: .appleMusic, properties: properties(duration: 210), definition: definition, state: code("kPSp"), position: 25)
        XCTAssertEqual(spotify.duration, 210)
        XCTAssertEqual(apple.duration, 210)
        XCTAssertEqual(spotify.title, "Song")
        XCTAssertEqual(spotify.artist, "Artist")
        XCTAssertEqual(spotify.album, "Album")
        XCTAssertTrue(spotify.playing)
        XCTAssertFalse(apple.playing)
        XCTAssertNotEqual(spotify.id, apple.id)
        XCTAssertNil(spotify.cover)
    }

    func testEmptyMetadataAndNonFinitePositionsCannotInventPlayback() throws {
        let empty = try AppleEventMusicTransport.reading(source: .appleMusic, properties: properties(title: "  "), definition: definition, state: code("kPSP"), position: 1)
        XCTAssertEqual(empty.availability, .empty)
        XCTAssertFalse(empty.playing)
        XCTAssertThrowsError(try AppleEventMusicTransport.reading(source: .spotify, properties: properties(), definition: definition, state: code("kPSP"), position: .nan))
        let clamped = try AppleEventMusicTransport.reading(source: .spotify, properties: properties(), definition: definition, state: code("kPSp"), position: 500)
        XCTAssertEqual(clamped.elapsed, 210)
    }

    func testArtworkRejectsOversizedOrNonImageData() {
        XCTAssertNil(AppleEventMusicTransport.thumbnail(Data("https://example.com/artwork".utf8)))
        XCTAssertNil(AppleEventMusicTransport.thumbnail(Data(repeating: 0, count: 4_000_001)))
    }

    func testArtworkIsScaledBeforeItEntersTheWebView() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 320, bitsPerSample: 8,
                                                  samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let thumbnail = try XCTUnwrap(AppleEventMusicTransport.thumbnail(data))
        XCTAssertTrue(thumbnail.hasPrefix("data:image/jpeg;base64,"))
        let jpeg = try XCTUnwrap(Data(base64Encoded: String(thumbnail.dropFirst(23))))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertLessThanOrEqual(try XCTUnwrap(properties[kCGImagePropertyPixelWidth] as? Int), 160)
        XCTAssertLessThanOrEqual(jpeg.count, 65_000)
    }

    func testMissingOrClosedPlayerDoesNotReadSendOrRequestPermission() {
        for installed in [false, true] {
            let transport = FakeTransport()
            transport.applicationURL = installed ? URL(fileURLWithPath: "/fixture/Spotify.app") : nil
            transport.isRunning = false
            let player = DirectMusicController(source: .spotify, transport: transport)
            let finished = expectation(description: "closed player")
            player.inspect { result in
                guard case .failure(let error) = result else { XCTFail("Expected unavailable player"); finished.fulfill(); return }
                XCTAssertEqual(error.code, installed ? "offline" : "notInstalled")
                XCTAssertTrue(error.message.contains("Spotify"))
                finished.fulfill()
            }
            wait(for: [finished], timeout: 2)
            XCTAssertTrue(transport.permissionRequests.isEmpty)
            XCTAssertEqual(transport.readCount, 0)
            XCTAssertTrue(transport.commands.isEmpty)
        }
    }

    func testPollingNeverAsksForPermissionAndExplicitConnectionNeverPlays() {
        let transport = FakeTransport()
        transport.permissionStatus = OSStatus(errAEEventWouldRequireUserConsent)
        let player = DirectMusicController(source: .appleMusic, transport: transport)
        let denied = expectation(description: "nonprompting poll")
        player.inspect { result in
            guard case .failure(let error) = result else { XCTFail("Expected consent state"); denied.fulfill(); return }
            XCTAssertEqual(error.code, "permissionRequired")
            denied.fulfill()
        }
        wait(for: [denied], timeout: 2)
        XCTAssertEqual(transport.permissionRequests, [false])
        XCTAssertEqual(transport.readCount, 0)
        transport.permissionStatus = noErr
        let connected = expectation(description: "explicit connect")
        player.connect { result in
            if case .failure = result { XCTFail("Connection should succeed") }
            connected.fulfill()
        }
        wait(for: [connected], timeout: 2)
        XCTAssertEqual(transport.permissionRequests, [false, true])
        XCTAssertEqual(transport.readCount, 0)
        XCTAssertTrue(transport.commands.isEmpty)
    }

    func testCommandUsesFreshBeforeAndAfterSnapshotsAndConfirmsResult() {
        let transport = FakeTransport()
        transport.readings = [.success(ready(id: "fresh-before")), .success(ready(id: "fresh-after", playing: true))]
        let player = DirectMusicController(source: .spotify, transport: transport)
        let finished = expectation(description: "confirmed next")
        player.perform(.next) { result in
            guard case .success(let reading) = result else { XCTFail("Expected confirmed track"); finished.fulfill(); return }
            XCTAssertEqual(reading.id, "fresh-after")
            XCTAssertEqual(reading.confirmedCommand, .next)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
        XCTAssertEqual(transport.commands, [.next])
        XCTAssertEqual(transport.readCount, 2)
        XCTAssertEqual(transport.permissionRequests, [false, false])
    }

    func testEmptyTrackDoesNotSendPlayAndDeniedPermissionDoesNotSendAnything() {
        let transport = FakeTransport()
        transport.readings = [.success(MeldReading(availability: .empty))]
        let player = DirectMusicController(source: .spotify, transport: transport)
        let empty = expectation(description: "no track")
        player.perform(.play) { result in
            guard case .failure(let error) = result else { XCTFail("Expected failure"); empty.fulfill(); return }
            XCTAssertEqual(error.code, "unsupportedAction")
            empty.fulfill()
        }
        wait(for: [empty], timeout: 2)
        XCTAssertTrue(transport.commands.isEmpty)
        transport.permissionStatus = OSStatus(errAEEventNotPermitted)
        let denied = expectation(description: "denied permission")
        player.perform(.play) { result in
            guard case .failure(let error) = result else { XCTFail("Expected failure"); denied.fulfill(); return }
            XCTAssertEqual(error.code, "permission")
            denied.fulfill()
        }
        wait(for: [denied], timeout: 2)
        XCTAssertEqual(transport.readCount, 1)
        XCTAssertTrue(transport.commands.isEmpty)
        XCTAssertFalse(transport.permissionRequests.contains(true))
    }

    func testReadFailureAfterACommandCannotClaimSuccess() {
        let transport = FakeTransport()
        transport.readings = [.success(ready()), .failure(MusicSource.spotify.error("unavailable"))]
        let player = DirectMusicController(source: .spotify, transport: transport)
        let finished = expectation(description: "command result unknown")
        player.perform(.play) { result in
            guard case .failure = result else { XCTFail("Expected failure"); finished.fulfill(); return }
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
        XCTAssertEqual(transport.commands, [.play])
        XCTAssertEqual(transport.readCount, 2)
    }

    func testUnchangedPlayerStateDoesNotConfirmOrRepeatTheCommand() {
        let transport = FakeTransport()
        transport.readings = [.success(ready()), .success(ready()), .failure(MusicSource.spotify.error("notConfirmed"))]
        let player = DirectMusicController(source: .spotify, transport: transport)
        let finished = expectation(description: "unconfirmed play")
        player.perform(.play) { result in
            guard case .failure(let error) = result else { XCTFail("Unchanged playback must not confirm Play"); finished.fulfill(); return }
            XCTAssertEqual(error.code, "notConfirmed")
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
        XCTAssertEqual(transport.commands, [.play])
        XCTAssertEqual(transport.readCount, 3)
    }

    func testAllowedPollingOnlyReadsActualPlayerState() {
        let transport = FakeTransport()
        transport.readings = [.success(ready(id: "actual-player-track", playing: true))]
        let player = DirectMusicController(source: .spotify, transport: transport)
        let finished = expectation(description: "read-only snapshot")
        player.inspect { result in
            guard case .success(let reading) = result else { XCTFail("Expected state"); finished.fulfill(); return }
            XCTAssertEqual(reading.id, "actual-player-track")
            XCTAssertTrue(reading.playing)
            XCTAssertNil(reading.confirmedCommand)
            finished.fulfill()
        }
        wait(for: [finished], timeout: 2)
        XCTAssertEqual(transport.readCount, 1)
        XCTAssertEqual(transport.permissionRequests, [false])
        XCTAssertTrue(transport.commands.isEmpty)
    }

    func testAppleMusicInstalledDictionaryMatchesExpectedPlaybackCommands() throws {
        let file = URL(fileURLWithPath: "/System/Applications/Music.app/Contents/Resources/com.apple.Music.sdef")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Apple Music not installed on this test host") }
        let parsed = try MusicScriptingDefinition(data: Data(contentsOf: file))
        XCTAssertEqual(parsed.properties["player state"], code("pPlS"))
        XCTAssertEqual(parsed.properties["current track"], code("pTrk"))
        XCTAssertEqual(parsed.commands["play"]?.1, code("Play"))
        XCTAssertEqual(parsed.commands["pause"]?.1, code("Paus"))
        XCTAssertEqual(parsed.commands["next track"]?.1, code("Next"))
        XCTAssertEqual(parsed.commands["previous track"]?.1, code("Prev"))
    }

    private func ready(id: String = "one", playing: Bool = false) -> MeldReading {
        MeldReading(availability: .ready, id: id, title: "Song", queueID: id, duration: 120, elapsed: 5, playing: playing,
                    canPlay: true, canPause: true, canNext: true, canPrevious: true)
    }

    private final class FakeTransport: DirectMusicTransport {
        var applicationURL: URL? = URL(fileURLWithPath: "/fixture/Player.app")
        var isRunning = true
        var permissionStatus: OSStatus = noErr
        var permissionRequests: [Bool] = []
        var readCount = 0
        var commands: [MeldCommand] = []
        var readings: [Result<MeldReading, MeldControlError>] = []
        func permission(ask: Bool) -> OSStatus { permissionRequests.append(ask); return permissionStatus }
        func read(deadline: Date) throws -> MeldReading {
            readCount += 1
            return try readings.removeFirst().get()
        }
        func send(_ command: MeldCommand, deadline: Date) throws { commands.append(command) }
    }
}
