import CoreGraphics

/// Pure geometry for one dock: where each tile sits along the dock's axis and how large it is,
/// given the pointer position. Used for both rendering and hit testing.
///
/// "Along" is the axis the icons run on (x for a bottom dock, y for a side dock); "cross" is
/// the distance from the screen edge.
struct DockLayout {
    struct Slot {
        let index: Int
        /// Centre along the axis, in panel coordinates.
        let center: CGFloat
        /// Length along the axis (icon size for icons, gap width for separators).
        let length: CGFloat
        /// Icon edge length; equals `length` for icons.
        let iconSize: CGFloat

        var start: CGFloat { center - length / 2 }
        var end: CGFloat { center + length / 2 }
    }

    let slots: [Slot]
    /// Extent of the glass shelf along the axis.
    let shelf: ClosedRange<CGFloat>
    let metrics: DockMetrics

    /// Index of the selectable slot under `along`, if any.
    func slotIndex(at along: CGFloat) -> Int? {
        slots.first { along >= $0.start && along < $0.end }?.index
    }

    static func compute(kinds: [DockItemKind], metrics: DockMetrics, axisLength: CGFloat,
                        pointer: CGFloat?, magnification: Bool) -> DockLayout {
        let base = kinds.map { metrics.baseLength(of: $0) }
        let baseTotal = base.reduce(0, +)
        let baseStart = (axisLength - baseTotal) / 2

        var baseCenters: [CGFloat] = []
        var cursor = baseStart
        for length in base {
            baseCenters.append(cursor + length / 2)
            cursor += length
        }

        // Icons grow with a cosine falloff around the pointer, measured in un-magnified space.
        let lengths: [CGFloat] = kinds.indices.map { index in
            guard magnification, let pointer, kinds[index] != .separator else { return base[index] }
            let distance = abs(baseCenters[index] - pointer)
            guard distance < metrics.influence else { return base[index] }
            let weight = (cos(distance / metrics.influence * .pi) + 1) / 2
            return base[index] + (metrics.largeSize - metrics.tileSize) * weight
        }

        // Lay out magnified tiles, then shift so the point under the pointer stays put (as the real
        // Dock does); without a pointer this is the centred base layout.
        var starts: [CGFloat] = []
        cursor = baseStart
        for length in lengths {
            starts.append(cursor)
            cursor += length
        }
        var shift: CGFloat = 0
        if magnification, let pointer {
            var hovered: Int?
            for index in base.indices {
                let baseStartOfSlot: CGFloat = baseCenters[index] - base[index] / 2
                if pointer >= baseStartOfSlot && pointer < baseStartOfSlot + base[index] {
                    hovered = index
                    break
                }
            }
            if let hovered {
                let slotStart: CGFloat = baseCenters[hovered] - base[hovered] / 2
                let fraction: CGFloat = (pointer - slotStart) / base[hovered]
                shift = pointer - (starts[hovered] + fraction * lengths[hovered])
            } else {
                let magnifiedTotal: CGFloat = lengths.reduce(0, +)
                shift = (baseTotal - magnifiedTotal) / 2
            }
        }

        let slots = kinds.indices.map { index in
            let length = lengths[index]
            let iconSize: CGFloat = if case .separator = kinds[index] { 0 } else { length }
            return Slot(index: index, center: starts[index] + shift + length / 2, length: length, iconSize: iconSize)
        }
        let first = slots.first?.start ?? axisLength / 2
        let last = slots.last?.end ?? axisLength / 2
        return DockLayout(slots: slots, shelf: (first - metrics.shelfPadding)...(last + metrics.shelfPadding),
                          metrics: metrics)
    }
}

/// Size constants derived from the real Dock's tile size.
struct DockMetrics {
    let tileSize: CGFloat
    let largeSize: CGFloat

    init(settings: DockSettings) {
        tileSize = settings.tileSize
        largeSize = settings.magnification ? settings.largeSize : settings.tileSize
    }

    var edgeGap: CGFloat { 4 }
    var crossPadding: CGFloat { max(4, (tileSize * 0.14).rounded()) }
    var shelfPadding: CGFloat { max(6, tileSize * 0.2) }
    var shelfThickness: CGFloat { tileSize + crossPadding * 2 }
    var influence: CGFloat { max(tileSize, largeSize) * 2.4 }
    var bounceHeight: CGFloat { (tileSize * 0.9).rounded() }
    var labelSpace: CGFloat { 34 }
    var iconInset: CGFloat { 0.06 }

    /// Distance from the screen edge to the icon's near edge.
    var iconBaseline: CGFloat { edgeGap + crossPadding }

    /// Side docks put the hover label beside the icon rather than above it.
    static let sideLabelWidth: CGFloat = 220

    /// Full panel thickness: room for magnified icons, the bounce and the hover label.
    func panelThickness(for orientation: DockOrientation) -> CGFloat {
        iconBaseline + max(largeSize, tileSize + bounceHeight) + (orientation.isVertical ? Self.sideLabelWidth : labelSpace)
    }

    /// Space windows should leave free on screens where our dock is shown.
    var reservedThickness: CGFloat { edgeGap + shelfThickness }

    func baseLength(of kind: DockItemKind) -> CGFloat {
        switch kind {
        case .separator: max(8, tileSize * 0.4)
        case .spacer(let small): small ? tileSize / 2 : tileSize
        default: tileSize
        }
    }
}
