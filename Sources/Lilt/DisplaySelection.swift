import Foundation

struct DisplayCandidate: Equatable {
    let id: String
    let name: String
    let hasNotch: Bool
    let isMain: Bool
}

struct DisplaySelection: Equatable {
    let display: DisplayCandidate
    let preferredUnavailable: Bool

    static func resolve(_ displays: [DisplayCandidate], preferredID: String?) -> DisplaySelection? {
        guard !displays.isEmpty else { return nil }
        if let preferredID, !preferredID.isEmpty {
            let matches = displays.filter { $0.id == preferredID }
            if matches.count == 1, let display = matches.first {
                return DisplaySelection(display: display, preferredUnavailable: false)
            }
        }
        let fallback = displays.first(where: { $0.hasNotch })
            ?? displays.first(where: { $0.isMain })
            ?? displays[0]
        return DisplaySelection(display: fallback, preferredUnavailable: preferredID?.isEmpty == false)
    }
}
