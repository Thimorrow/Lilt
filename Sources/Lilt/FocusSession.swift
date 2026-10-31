import Foundation

enum FocusActivity: String, Codable, CaseIterable {
    case deepWork, lightWork
    var title: String { self == .deepWork ? "Deep Work" : "Light Work" }
    var launchLabel: String { "Go to \(title) session" }
}

struct FocusSession: Codable, Equatable {
    enum Phase: String, Codable { case idle, running, paused, completed, uncertain }
    var activity: FocusActivity = .deepWork
    var duration: Int = 1500
    var remaining: TimeInterval = 1500
    var deadline: Date?
    var phase: Phase = .idle
    var owned = false
    var verifiedAt: Date?
    var needsFinish = false
    var brainFMEnabled: Bool?

    func seconds(at now: Date) -> Int {
        Int(ceil(max(0, deadline.map { $0.timeIntervalSince(now) } ?? remaining)))
    }

    mutating func configure(activity: FocusActivity, minutes: Int) {
        guard (1...180).contains(minutes), phase != .running, phase != .uncertain else { return }
        self = FocusSession(activity: activity, duration: minutes * 60, remaining: Double(minutes * 60))
    }

    mutating func confirm(_ playback: BrainFMController.PlaybackState, at now: Date) {
        if playback == .playing {
            if phase != .running {
                if remaining <= 0 { remaining = Double(duration) }
                deadline = now.addingTimeInterval(remaining)
            }
            phase = .running
            owned = true
        } else {
            remaining = Double(seconds(at: now))
            deadline = nil
            phase = remaining == 0 ? .completed : .paused
            if phase == .completed { owned = false }
        }
        verifiedAt = now
    }

    mutating func loseConfirmation(at now: Date) {
        remaining = needsFinish ? 0 : Double(seconds(at: verifiedAt ?? now))
        deadline = nil
        phase = .uncertain
    }

    mutating func reset() {
        self = FocusSession(activity: activity, duration: duration, remaining: Double(duration))
    }
}

protocol BrainFMControlling: AnyObject {
    func perform(_ command: BrainFMController.Command, activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void)
    func inspect(activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void)
}

final class FocusCoordinator {
    enum Action: String { case start, pause, reset, finish }
    struct Pending {
        let id = UUID()
        let action: Action
    }
    private(set) var session: FocusSession
    private(set) var pending: Pending?
    private(set) var error: BrainFMController.ControlError?
    private(set) var retry: Action?
    private(set) var restoring = false
    private(set) var brainFMEnabled: Bool
    var onChange: (() -> Void)?
    private let player: BrainFMControlling
    private let file: URL
    private let now: () -> Date
    private var timer: Timer?
    private var polling = false
    private var lastPoll = Date.distantPast
    private var lastSave = Date.distantPast
    private var lastSecond = -1
    private var commandStarted: UUID?
    private var configurationRevision = 0

    init(player: BrainFMControlling, file: URL, brainFMEnabled: Bool = true, now: @escaping () -> Date = Date.init) {
        self.player = player
        self.file = file
        self.now = now
        self.brainFMEnabled = brainFMEnabled
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode(FocusSession.self, from: data),
           (60...10800).contains(saved.duration), saved.remaining.isFinite,
           saved.remaining >= 0, saved.remaining <= 10800 {
            session = saved
            let savedMode = saved.brainFMEnabled ?? true
            if savedMode != brainFMEnabled, saved.phase != .idle, saved.phase != .completed {
                let reference = savedMode ? saved.verifiedAt ?? now() : now()
                session.remaining = Double(saved.seconds(at: reference))
                session.deadline = nil
                session.phase = session.remaining == 0 ? .completed : .paused
                session.owned = false
                session.needsFinish = false
                error = .init(code: "integration_changed", message: "Die Fokus-Verbindung wurde geändert. Die vorherige Sitzung ist pausiert; Musik wurde nicht verändert.")
                retry = .start
            } else if brainFMEnabled {
                restoring = saved.owned
            } else if saved.phase == .running, saved.seconds(at: now()) == 0 {
                complete()
            }
        } else { session = FocusSession() }
        session.brainFMEnabled = brainFMEnabled
    }

    var integrationLocked: Bool {
        pending != nil || restoring || (session.phase != .idle && session.phase != .completed)
    }

    @discardableResult
    func setBrainFMEnabled(_ enabled: Bool) -> Bool {
        if brainFMEnabled == enabled { return true }
        guard !integrationLocked else { return false }
        configurationRevision += 1
        brainFMEnabled = enabled
        error = nil; retry = nil
        save(); publish()
        return true
    }

    func startObserving() {
        guard timer == nil else { return }
        timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        if restoring { poll() }
        publish()
    }

    func stop() { timer?.invalidate(); timer = nil; save() }
    func checkpoint() { save(); publish() }

    func configure(activity: FocusActivity, minutes: Int) {
        guard pending == nil, !restoring, (1...180).contains(minutes), session.phase != .running, session.phase != .uncertain else { return }
        configurationRevision += 1
        session.configure(activity: activity, minutes: minutes)
        error = nil; retry = nil
        save(); publish()
    }

    func request(_ action: Action) {
        guard pending == nil, !restoring else { return }
        if !brainFMEnabled {
            applyIndependent(action)
            return
        }
        if action == .reset, !session.owned {
            configurationRevision += 1
            session.reset(); error = nil; retry = nil; save(); publish(); return
        }
        pending = Pending(action: action)
        if action == .finish { session.needsFinish = true; save() }
        error = nil; retry = nil
        publish()
        if !polling { runPending() }
    }

    private func runPending() {
        guard let request = pending, commandStarted != request.id else { return }
        commandStarted = request.id
        player.perform(request.action == .start ? .play : .pause, activity: session.activity) { [weak self] result in
            guard let self, self.pending?.id == request.id else { return }
            self.pending = nil
            self.commandStarted = nil
            switch result {
            case .success(let playback):
                let expected: BrainFMController.PlaybackState = request.action == .start ? .playing : .paused
                guard playback == expected else { self.fail(.timeout, retry: request.action); return }
                if request.action == .reset { self.session.reset() }
                else if request.action == .finish { self.complete() }
                else { self.session.confirm(playback, at: self.now()) }
                self.error = nil; self.retry = nil
            case .failure(let error):
                if request.action == .reset, error == .activity {
                    self.session.reset()
                    self.error = nil; self.retry = nil
                } else {
                    self.error = error
                    self.retry = request.action
                    if self.session.owned { self.session.loseConfirmation(at: self.now()) }
                }
            }
            self.lastPoll = self.now()
            self.save(); self.publish()
        }
    }

    private func applyIndependent(_ action: Action) {
        configurationRevision += 1
        switch action {
        case .start:
            if session.phase != .running { session.confirm(.playing, at: now()) }
        case .pause:
            if session.phase == .running { session.confirm(.paused, at: now()) }
        case .reset: session.reset()
        case .finish: complete()
        }
        error = nil; retry = nil
        save(); publish()
    }

    private func complete() {
        session.deadline = nil
        session.remaining = 0
        session.phase = .completed
        session.owned = false
        session.needsFinish = false
        session.verifiedAt = now()
    }

    func tick() {
        let date = now()
        if !restoring, pending == nil, session.phase == .running, session.seconds(at: date) == 0 {
            request(.finish)
        } else if brainFMEnabled, session.owned, pending == nil, !polling, date.timeIntervalSince(lastPoll) >= 3 {
            poll()
        }
        if date.timeIntervalSince(lastSave) >= 5, session.owned { save() }
        if session.seconds(at: date) != lastSecond { publish() }
    }

    func recheck() {
        if !brainFMEnabled { tick(); return }
        guard session.owned, !polling, pending == nil else { return }
        poll()
    }

    private func poll() {
        guard brainFMEnabled, !polling else { return }
        polling = true
        let activity = session.activity
        let revision = configurationRevision
        player.inspect(activity: activity) { [weak self] result in
            guard let self else { return }
            self.polling = false
            self.lastPoll = self.now()
            if self.pending != nil { self.runPending(); return }
            guard self.configurationRevision == revision else { return }
            let wasRestoring = self.restoring
            self.restoring = false
            var shouldFinish = false
            switch result {
            case .success(let playback):
                if wasRestoring, playback == .paused, self.session.deadline != nil {
                    self.session.remaining = Double(self.session.seconds(at: self.session.verifiedAt ?? self.now()))
                    self.session.deadline = nil
                    self.session.phase = .paused
                }
                if self.session.needsFinish {
                    if playback == .paused {
                        self.session.deadline = nil
                        self.session.remaining = 0
                        self.session.phase = .completed
                        self.session.owned = false
                        self.session.needsFinish = false
                        self.error = nil; self.retry = nil
                    } else if wasRestoring { shouldFinish = true }
                } else {
                    self.session.confirm(playback, at: self.now())
                    self.error = nil; self.retry = nil
                    shouldFinish = self.session.phase == .running && self.session.seconds(at: self.now()) == 0
                }
            case .failure(let error):
                self.session.loseConfirmation(at: self.now())
                self.error = error
                if self.retry == nil { self.retry = self.session.needsFinish ? .finish : .start }
            }
            self.save(); self.publish()
            if shouldFinish { self.request(.finish) }
        }
    }

    private func fail(_ error: BrainFMController.ControlError, retry: Action) {
        self.error = error; self.retry = retry
        if session.owned { session.loseConfirmation(at: now()) }
        save(); publish()
    }

    private func save() {
        session.brainFMEnabled = brainFMEnabled
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(session)
            try data.write(to: file, options: .atomic)
            lastSave = now()
        } catch {
            self.error = .init(code: "storage", message: "Die Fokus-Sitzung konnte nicht gespeichert werden. Prüfe den freien Speicherplatz.")
        }
    }

    private func publish() { lastSecond = session.seconds(at: now()); onChange?() }

    var snapshot: [String: Any] {
        ["activity": session.activity.rawValue, "duration": session.duration,
         "remaining": session.seconds(at: now()), "deadline": session.deadline.map { $0.timeIntervalSince1970 * 1000 } as Any? ?? NSNull(),
         "phase": restoring ? "checking" : session.phase.rawValue, "owned": session.owned, "restoring": restoring,
         "brainFMEnabled": brainFMEnabled, "integrationLocked": integrationLocked,
         "pending": pending.map { ["id": $0.id.uuidString, "action": $0.action.rawValue] } as Any? ?? NSNull(),
         "error": error.map { ["code": $0.code, "message": $0.message, "action": retry?.rawValue ?? "start"] } as Any? ?? NSNull()]
    }

    func setDiagnosticRemaining(_ seconds: Int) {
        guard seconds >= 0, seconds <= 10800 else { return }
        session.remaining = Double(seconds)
        if session.phase == .running { session.deadline = now().addingTimeInterval(Double(seconds)) }
        save(); publish()
    }
}

final class SimulatedBrainFM: BrainFMControlling {
    var playback: BrainFMController.PlaybackState = .paused
    var activity: FocusActivity = .deepWork
    var failure: BrainFMController.ControlError?
    var delay: TimeInterval = 0.1

    func perform(_ command: BrainFMController.Command, activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            if let failure { self.failure = nil; completion(.failure(failure)); return }
            if command == .pause, self.activity != activity { completion(.failure(.activity)); return }
            self.activity = activity
            playback = command == .play ? .playing : .paused
            completion(.success(playback))
        }
    }

    func inspect(activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            if let failure { completion(.failure(failure)); return }
            completion(self.activity == activity ? .success(playback) : .failure(.activity))
        }
    }
}

final class DisabledBrainFM: BrainFMControlling {
    func perform(_ command: BrainFMController.Command, activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
        completion(.failure(.init(code: "test_mode", message: "Brain.fm control is disabled in this test run.")))
    }
    func inspect(activity: FocusActivity, completion: @escaping (Result<BrainFMController.PlaybackState, BrainFMController.ControlError>) -> Void) {
        completion(.success(.paused))
    }
}
