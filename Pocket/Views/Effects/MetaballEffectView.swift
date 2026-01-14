import SwiftUI

/// Creates a "gooey" metaball effect between the Dynamic Island and dragged items
/// Uses blur + contrast threshold technique to simulate liquid merging
struct MetaballEffectView: View {

    // MARK: - Properties

    /// Position of the dragged item relative to the island center
    let dragPosition: CGPoint?

    /// Size of the dragged item indicator
    let itemSize: CGFloat

    /// Size of the island
    let islandSize: CGSize

    /// How close the item is to the island (0 = far, 1 = touching)
    let proximity: CGFloat

    /// Whether the effect is active
    let isActive: Bool

    // MARK: - Constants

    private enum Constants {
        static let blurRadius: CGFloat = 20
        static let contrastMultiplier: CGFloat = 20
        static let brightnessAdjust: CGFloat = -0.5
        static let maxBulgeDistance: CGFloat = 30
        static let tentacleThickness: CGFloat = 8
    }

    // MARK: - Body

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            // Draw the main island shape
            let islandRect = CGRect(
                x: center.x - islandSize.width / 2,
                y: center.y - islandSize.height / 2,
                width: islandSize.width,
                height: islandSize.height
            )
            let islandPath = RoundedRectangle(cornerRadius: 44, style: .continuous)
                .path(in: islandRect)

            context.fill(islandPath, with: .color(.white))

            // Draw the dragged item blob if active
            if isActive, let dragPos = dragPosition {
                // Calculate the actual position relative to canvas center
                let itemCenter = CGPoint(
                    x: center.x + dragPos.x,
                    y: center.y + dragPos.y
                )

                // Draw connecting tentacle when close
                if proximity > 0.3 {
                    drawTentacle(
                        context: &context,
                        from: center,
                        to: itemCenter,
                        islandSize: islandSize,
                        proximity: proximity
                    )
                }

                // Draw the item blob
                let blobSize = itemSize * (0.8 + proximity * 0.4) // Grows as it gets closer
                let blobRect = CGRect(
                    x: itemCenter.x - blobSize / 2,
                    y: itemCenter.y - blobSize / 2,
                    width: blobSize,
                    height: blobSize
                )
                let blobPath = Circle().path(in: blobRect)
                context.fill(blobPath, with: .color(.white))

                // Add bulge on island toward the item
                if proximity > 0.2 {
                    drawBulge(
                        context: &context,
                        center: center,
                        toward: itemCenter,
                        islandSize: islandSize,
                        proximity: proximity
                    )
                }
            }
        }
        .blur(radius: Constants.blurRadius)
        .contrast(Constants.contrastMultiplier)
        .brightness(Constants.brightnessAdjust)
        .blendMode(.destinationOut)
        .allowsHitTesting(false)
    }

    // MARK: - Drawing Helpers

    /// Draws a connecting tentacle between island and item
    private func drawTentacle(
        context: inout GraphicsContext,
        from islandCenter: CGPoint,
        to itemCenter: CGPoint,
        islandSize: CGSize,
        proximity: CGFloat
    ) {
        let direction = CGPoint(
            x: itemCenter.x - islandCenter.x,
            y: itemCenter.y - islandCenter.y
        )
        let distance = sqrt(direction.x * direction.x + direction.y * direction.y)
        guard distance > 0 else { return }

        let normalized = CGPoint(x: direction.x / distance, y: direction.y / distance)

        // Start point on island edge
        let startOffset = min(islandSize.width, islandSize.height) / 2
        let start = CGPoint(
            x: islandCenter.x + normalized.x * startOffset,
            y: islandCenter.y + normalized.y * startOffset
        )

        // Tentacle thickness varies with proximity
        let thickness = Constants.tentacleThickness * (0.5 + proximity * 0.5)

        // Draw multiple circles along the path for smooth tentacle
        let steps = Int(distance / 10)
        for i in 0..<steps {
            let t = CGFloat(i) / CGFloat(steps)
            let pos = CGPoint(
                x: start.x + (itemCenter.x - start.x) * t,
                y: start.y + (itemCenter.y - start.y) * t
            )
            // Tentacle is thicker in the middle
            let segmentSize = thickness * (1 - abs(t - 0.5) * 1.5)
            let rect = CGRect(
                x: pos.x - segmentSize / 2,
                y: pos.y - segmentSize / 2,
                width: segmentSize,
                height: segmentSize
            )
            context.fill(Circle().path(in: rect), with: .color(.white))
        }
    }

    /// Draws a bulge on the island toward the approaching item
    private func drawBulge(
        context: inout GraphicsContext,
        center: CGPoint,
        toward itemCenter: CGPoint,
        islandSize: CGSize,
        proximity: CGFloat
    ) {
        let direction = CGPoint(
            x: itemCenter.x - center.x,
            y: itemCenter.y - center.y
        )
        let distance = sqrt(direction.x * direction.x + direction.y * direction.y)
        guard distance > 0 else { return }

        let normalized = CGPoint(x: direction.x / distance, y: direction.y / distance)

        // Bulge extends from island edge
        let edgeOffset = min(islandSize.width, islandSize.height) / 2
        let bulgeDistance = Constants.maxBulgeDistance * proximity

        let bulgeCenter = CGPoint(
            x: center.x + normalized.x * (edgeOffset + bulgeDistance * 0.5),
            y: center.y + normalized.y * (edgeOffset + bulgeDistance * 0.5)
        )

        // Bulge size grows with proximity
        let bulgeSize = 20 + proximity * 25
        let bulgeRect = CGRect(
            x: bulgeCenter.x - bulgeSize / 2,
            y: bulgeCenter.y - bulgeSize / 2,
            width: bulgeSize,
            height: bulgeSize
        )

        context.fill(Circle().path(in: bulgeRect), with: .color(.white))
    }
}

// MARK: - Metaball Container

/// Container view that applies the gooey effect as a mask
struct GooeyIslandContainer<Content: View>: View {

    let islandSize: CGSize
    let dragPosition: CGPoint?
    let itemSize: CGFloat
    let proximity: CGFloat
    let isActive: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            // The actual content (island)
            content()

            // Metaball overlay effect
            if isActive && proximity > 0.1 {
                MetaballEffectView(
                    dragPosition: dragPosition,
                    itemSize: itemSize,
                    islandSize: islandSize,
                    proximity: proximity,
                    isActive: isActive
                )
                .frame(width: islandSize.width + 200, height: islandSize.height + 200)
            }
        }
    }
}

// MARK: - Simpler Gooey Approach (Alternative)

/// A simpler gooey effect using overlapping blurred circles
struct SimpleGooeyEffect: View {

    let islandWidth: CGFloat
    let islandHeight: CGFloat
    let dragOffset: CGPoint
    let proximity: CGFloat  // 0 to 1
    let isActive: Bool

    private let blurAmount: CGFloat = 15

    var body: some View {
        ZStack {
            // Island base shape
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(.black)
                .frame(width: islandWidth, height: islandHeight)

            // Reaching tendril toward item
            if isActive && proximity > 0.2 {
                reachingTendril
            }
        }
        .blur(radius: blurAmount)
        .overlay(
            // Sharp mask
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(.black)
                .frame(width: islandWidth, height: islandHeight)
                .blur(radius: blurAmount)
                .contrast(50)
        )
        .compositingGroup()
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: proximity)
    }

    private var reachingTendril: some View {
        let tendrilLength = 20 + (proximity * 30)
        let direction = normalizedDirection

        return Circle()
            .fill(.black)
            .frame(width: 30 * proximity, height: 30 * proximity)
            .offset(
                x: direction.x * (islandWidth / 2 + tendrilLength),
                y: direction.y * (islandHeight / 2 + tendrilLength * 0.3)
            )
    }

    private var normalizedDirection: CGPoint {
        let length = sqrt(dragOffset.x * dragOffset.x + dragOffset.y * dragOffset.y)
        guard length > 0 else { return .zero }
        return CGPoint(x: dragOffset.x / length, y: dragOffset.y / length)
    }
}

// MARK: - Preview

#Preview("Metaball Effect") {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()

        VStack(spacing: 50) {
            // Static preview
            MetaballEffectView(
                dragPosition: CGPoint(x: 80, y: -30),
                itemSize: 50,
                islandSize: CGSize(width: 200, height: 60),
                proximity: 0.7,
                isActive: true
            )
            .frame(width: 400, height: 200)
            .background(Color.black.opacity(0.1))

            // Simple gooey preview
            SimpleGooeyEffect(
                islandWidth: 200,
                islandHeight: 60,
                dragOffset: CGPoint(x: 1, y: -0.5),
                proximity: 0.8,
                isActive: true
            )
            .frame(width: 400, height: 200)
        }
    }
}
