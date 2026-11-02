import Foundation

struct ShelfDragGesture {
    struct Payload {
        let urls: [URL]
        let ids: [String]
        let origin: CGPoint
    }
    private var origin: CGPoint?
    private var prepared: Payload?

    mutating func mouseDown(at point: CGPoint) {
        origin = point
        prepared = nil
    }

    mutating func prepare(urls: [URL], ids: [String], frame: CGRect) {
        guard let origin, !urls.isEmpty, urls.count == ids.count, frame.contains(origin) else { return }
        prepared = Payload(urls: urls, ids: ids, origin: origin)
    }

    mutating func drag(at point: CGPoint) -> Payload? {
        guard let payload = prepared, hypot(point.x - payload.origin.x, point.y - payload.origin.y) >= 4 else { return nil }
        reset()
        return payload
    }

    mutating func reset() { origin = nil; prepared = nil }
}
