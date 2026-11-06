import SwiftUI

/// Renders one display's dock from the shared model plus that panel's hover state.
struct DockView: View {
    let model: DockModel
    let state: PanelState
    let layoutFor: (CGSize) -> DockLayout

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutFor(proxy.size)
            let orientation = model.settings.orientation
            TimelineView(.animation(paused: model.bounces.isEmpty)) { timeline in
                ZStack {
                    DockShelf(layout: layout, orientation: orientation, size: proxy.size)
                    ForEach(Array(zip(model.items, layout.slots)), id: \.0.id) { item, slot in
                        DockTileView(item: item, slot: slot, layout: layout, orientation: orientation,
                                     size: proxy.size, isTrashFull: model.isTrashFull,
                                     showsIndicator: model.settings.showIndicators,
                                     isPressed: state.pressedIndex == slot.index,
                                     bounce: bounceOffset(for: item, metrics: layout.metrics, at: timeline.date))
                    }
                    if let index = state.hoveredIndex, state.openIndex != index,
                       index < model.items.count, !model.items[index].label.isEmpty {
                        DockLabel(text: model.items[index].label, slot: layout.slots[index], layout: layout,
                                  orientation: orientation, size: proxy.size)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .ignoresSafeArea()
    }

    private func bounceOffset(for item: DockItem, metrics: DockMetrics, at date: Date) -> CGFloat {
        guard let started = model.bounces[item.id] else { return 0 }
        let elapsed = date.timeIntervalSince(started)
        guard elapsed < DockModel.bounceTimeout else { return 0 }
        let period = 0.62
        let phase = elapsed.truncatingRemainder(dividingBy: period) / period
        return metrics.bounceHeight * CGFloat(sin(phase * .pi))
    }
}

private struct DockShelf: View {
    let layout: DockLayout
    let orientation: DockOrientation
    let size: CGSize

    var body: some View {
        let metrics = layout.metrics
        let length = layout.shelf.upperBound - layout.shelf.lowerBound
        let center = orientation.point(along: (layout.shelf.lowerBound + layout.shelf.upperBound) / 2,
                                       cross: metrics.edgeGap + metrics.shelfThickness / 2, in: size)
        let shape = RoundedRectangle(cornerRadius: min(metrics.shelfThickness * 0.42, 22), style: .continuous)
        Color.clear
            .frame(width: orientation.isVertical ? metrics.shelfThickness : length,
                   height: orientation.isVertical ? length : metrics.shelfThickness)
            .glassEffect(.regular, in: shape)
            .position(center)
    }
}

private struct DockTileView: View {
    let item: DockItem
    let slot: DockLayout.Slot
    let layout: DockLayout
    let orientation: DockOrientation
    let size: CGSize
    let isTrashFull: Bool
    let showsIndicator: Bool
    let isPressed: Bool
    let bounce: CGFloat

    var body: some View {
        let metrics = layout.metrics
        switch item.kind {
        case .separator:
            Rectangle()
                .fill(.primary.opacity(0.25))
                .frame(width: orientation.isVertical ? metrics.tileSize * 0.8 : 1,
                       height: orientation.isVertical ? 1 : metrics.tileSize * 0.8)
                .position(orientation.point(along: slot.center, cross: metrics.iconBaseline + metrics.tileSize / 2,
                                            in: size))
        case .spacer:
            EmptyView()
        default:
            let drawn = slot.iconSize * (1 - metrics.iconInset * 2)
            if let image = IconProvider.shared.icon(for: item, trashFull: isTrashFull) {
                IconImage(image: image, size: drawn)
                    .brightness(isPressed ? -0.35 : 0)
                    .position(orientation.point(along: slot.center,
                                                cross: metrics.iconBaseline + slot.iconSize / 2 + bounce, in: size))
            }
            if showsIndicator, item.isRunning {
                let diameter: CGFloat = metrics.tileSize < 28 ? 3 : 4
                Circle()
                    .fill(.primary.opacity(0.75))
                    .frame(width: diameter, height: diameter)
                    .position(orientation.point(along: slot.center,
                                                cross: metrics.edgeGap + metrics.crossPadding / 2, in: size))
            }
        }
    }
}

private struct DockLabel: View {
    let text: String
    let slot: DockLayout.Slot
    let layout: DockLayout
    let orientation: DockOrientation
    let size: CGSize

    private static let labelWidth = DockMetrics.sideLabelWidth

    var body: some View {
        let metrics = layout.metrics
        let crossGap = metrics.iconBaseline + slot.iconSize + 10
        let bubble = Text(text)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular, in: Capsule())
            .fixedSize()

        switch orientation {
        case .bottom:
            bubble.position(orientation.point(along: slot.center, cross: crossGap + 11, in: size))
        case .left, .right:
            // Labels sit beside the icon; a wide fixed frame lets the bubble align to the icon's side.
            bubble
                .frame(width: Self.labelWidth, alignment: orientation == .left ? .leading : .trailing)
                .position(orientation.point(along: slot.center, cross: crossGap + Self.labelWidth / 2, in: size))
        }
    }
}

/// App/file icon. macOS serves different icon variants per requested size, and at small sizes it
/// often returns the light variant even in dark mode (magnified icons were correct, resting ones
/// weren't). Rasterising at a fixed large size and scaling down keeps the variant consistent.
struct IconImage: View {
    let image: NSImage
    let size: CGFloat

    static let renderSize: CGFloat = 64

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: Self.renderSize, height: Self.renderSize)
            .scaleEffect(size / Self.renderSize)
            .frame(width: size, height: size)
    }
}
