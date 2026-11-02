import Foundation

struct DotLayout: Equatable {
    /// New indicators stay hidden until the user opts in, so an upgrade never changes the menu bar.
    static let defaultHidden: Set<StatusGlyph> = [.lowPowerMode, .microphone, .thermal, .powerAdapter]
    static let version = 2
    var order: [StatusGlyph] = StatusGlyph.allCases
    var hidden: Set<StatusGlyph> = DotLayout.defaultHidden
    var visible: [StatusGlyph] { order.filter { !hidden.contains($0) } }

    init(order: [StatusGlyph] = StatusGlyph.allCases, hidden: Set<StatusGlyph> = DotLayout.defaultHidden) {
        var unique: [StatusGlyph] = []
        for item in order + StatusGlyph.allCases where !unique.contains(item) { unique.append(item) }
        self.order = unique
        self.hidden = hidden
    }

    mutating func move(_ glyph: StatusGlyph, by offset: Int) {
        guard let index = order.firstIndex(of: glyph), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
    }
}

final class DotPreferences {
    private let defaults: UserDefaults
    private(set) var layout: DotLayout
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedOrder = (defaults.stringArray(forKey: "dotOrder") ?? []).compactMap(StatusGlyph.init(rawValue:))
        var hidden: Set<StatusGlyph>
        if defaults.object(forKey: "hiddenDots") == nil {
            hidden = DotLayout.defaultHidden
        } else {
            hidden = Set((defaults.stringArray(forKey: "hiddenDots") ?? []).compactMap(StatusGlyph.init(rawValue:)))
            // An older archive only lists what the user hid; new indicators must not appear on upgrade.
            if (defaults.object(forKey: "dotsVersion") as? Int ?? 1) < DotLayout.version {
                hidden.formUnion(DotLayout.defaultHidden)
            }
        }
        layout = DotLayout(order: storedOrder, hidden: hidden)
        if (defaults.object(forKey: "dotsVersion") as? Int ?? 0) != DotLayout.version {
            defaults.set(DotLayout.version, forKey: "dotsVersion")
            save()
        }
    }
    func setVisible(_ visible: Bool, for glyph: StatusGlyph) {
        if visible { layout.hidden.remove(glyph) } else { layout.hidden.insert(glyph) }
        save()
    }
    func move(_ glyph: StatusGlyph, by offset: Int) { layout.move(glyph, by: offset); save() }
    private func save() {
        defaults.set(layout.order.map(\.rawValue), forKey: "dotOrder")
        defaults.set(StatusGlyph.allCases.filter { layout.hidden.contains($0) }.map(\.rawValue), forKey: "hiddenDots")
        onChange?()
    }
}
