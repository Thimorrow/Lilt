import Foundation

struct TabSwipeGesture {
    enum Phase { case began, changed, ended, cancelled }
    private var active = false
    private var decided = false
    private var horizontalLocked = false
    private var verticalLocked = false
    private var x: Double = 0
    private var y: Double = 0

    mutating func reset() {
        active = false
        decided = false
        horizontalLocked = false
        verticalLocked = false
        x = 0
        y = 0
    }

    var completionDirection: Int? {
        guard active, horizontalLocked, !verticalLocked, abs(x) >= 40 else { return nil }
        return x < 0 ? 1 : -1
    }

    mutating func update(phase: Phase, deltaX: Double, deltaY: Double, precise: Bool, momentum: Bool, blocked: Bool) -> Int? {
        if momentum || blocked || !precise || !deltaX.isFinite || !deltaY.isFinite {
            reset()
            return nil
        }
        switch phase {
        case .began:
            reset()
            active = true
        case .ended, .cancelled:
            reset()
            return nil
        case .changed:
            guard active else { return nil }
        }
        x += deltaX
        y += deltaY
        if !horizontalLocked && !verticalLocked {
            if abs(y) >= 10 && abs(y) >= abs(x) { verticalLocked = true }
            else if abs(x) >= 10 && abs(x) >= abs(y) * 1.6 { horizontalLocked = true }
        }
        guard !decided, let direction = completionDirection else { return nil }
        decided = true
        return direction
    }
}
