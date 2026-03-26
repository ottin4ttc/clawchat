import CoreGraphics

enum MomentDismissAxis: Equatable {
    case horizontal
    case vertical
}

enum MomentDismissGestureBehavior {
    static let edgeActivationWidth: CGFloat = 72
    static let edgeHorizontalDistance: CGFloat = 8
    static let edgeHorizontalDominance: CGFloat = 0.75

    static let contentHorizontalActivationWidthRatio: CGFloat = 0.5
    static let contentHorizontalDistance: CGFloat = 32
    static let contentHorizontalDominance: CGFloat = 1.4

    static let verticalDistance: CGFloat = 18
    static let verticalDominance: CGFloat = 1.05

    static let crossAxisDamping: CGFloat = 0.18

    static let horizontalDismissDistance: CGFloat = 88
    static let verticalDismissDistance: CGFloat = 140
    static let horizontalVelocityThreshold: CGFloat = 380
    static let verticalVelocityThreshold: CGFloat = 500

    static let horizontalProgressDistance: CGFloat = 220
    static let verticalProgressDistance: CGFloat = 300

    static func beginAxis(
        startLocation: CGPoint,
        translation: CGSize,
        allowsContentHorizontalDismiss: Bool,
        requiresEdgeStart: Bool = false,
        contentHorizontalStartLimitX: CGFloat? = nil
    ) -> MomentDismissAxis? {
        let dx = translation.width
        let dy = translation.height
        let absDy = abs(dy)
        let startsFromEdge = startLocation.x <= edgeActivationWidth
        let startsWithinContentActivationRegion = contentHorizontalStartLimitX.map { startLocation.x <= $0 } ?? true

        if startsFromEdge,
           dx > edgeHorizontalDistance,
           dx > absDy * edgeHorizontalDominance {
            return .horizontal
        }

        if requiresEdgeStart {
            return nil
        }

        if allowsContentHorizontalDismiss,
           startsWithinContentActivationRegion,
           dx > contentHorizontalDistance,
           dx > absDy * contentHorizontalDominance {
            return .horizontal
        }

        return nil
    }

    static func contentHorizontalStartLimitX(for containerWidth: CGFloat) -> CGFloat {
        containerWidth * contentHorizontalActivationWidthRatio
    }

    static func resolvedOffset(for translation: CGSize, axis: MomentDismissAxis) -> CGSize {
        switch axis {
        case .horizontal:
            return CGSize(
                width: max(0, translation.width),
                height: translation.height * crossAxisDamping
            )
        case .vertical:
            return CGSize(
                width: translation.width * crossAxisDamping,
                height: max(0, translation.height)
            )
        }
    }

    static func dismissProgress(for offset: CGSize, axis: MomentDismissAxis?) -> CGFloat {
        let resolvedAxis = axis ?? inferredAxis(for: offset)

        switch resolvedAxis {
        case .horizontal:
            return min(1, max(0, offset.width) / horizontalProgressDistance)
        case .vertical:
            return min(1, max(0, offset.height) / verticalProgressDistance)
        }
    }

    static func shouldDismiss(
        translation: CGSize,
        velocity: CGSize,
        axis: MomentDismissAxis
    ) -> Bool {
        switch axis {
        case .horizontal:
            return max(0, translation.width) > horizontalDismissDistance
                || max(0, velocity.width) > horizontalVelocityThreshold
        case .vertical:
            return max(0, translation.height) > verticalDismissDistance
                || max(0, velocity.height) > verticalVelocityThreshold
        }
    }

    private static func inferredAxis(for offset: CGSize) -> MomentDismissAxis {
        abs(offset.width) >= abs(offset.height) ? .horizontal : .vertical
    }
}
