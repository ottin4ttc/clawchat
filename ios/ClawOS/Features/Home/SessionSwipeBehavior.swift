import CoreGraphics

enum SessionSwipeStage: Equatable {
    case closed
    case actionsRevealed
    case deleteDominant
    case armedForDelete
}

enum SessionSwipeSettleTarget: Equatable {
    case closed
    case revealed
    case armedForDelete
}

struct SessionSwipeMetrics: Equatable {
    let stage: SessionSwipeStage
    let railWidth: CGFloat
    let pinWidth: CGFloat
    let deleteWidth: CGFloat
    let deleteIconScale: CGFloat
    let deleteEmphasis: CGFloat
}

enum SessionSwipeBehavior {
    static let revealWidth: CGFloat = 160
    static let dominantThreshold: CGFloat = 260
    static let confirmThreshold: CGFloat = 340
    static let armedLockWidth: CGFloat = confirmThreshold

    static let pinBaseWidth: CGFloat = 78
    static let deleteBaseWidth: CGFloat = 82
    static let overshootDamping: CGFloat = 0.12

    static let openVelocityThreshold: CGFloat = -520
    static let armedVelocityThreshold: CGFloat = -1400
    static let closeVelocityThreshold: CGFloat = 320

    static func interactiveOffset(initialOffset: CGFloat, translation: CGFloat) -> CGFloat {
        let proposedOffset = initialOffset + translation
        if proposedOffset >= 0 {
            return 0
        }

        let travel = -proposedOffset
        guard travel > confirmThreshold else {
            return proposedOffset
        }

        let extraTravel = travel - confirmThreshold
        return -(confirmThreshold + extraTravel * overshootDamping)
    }

    static func stage(for offset: CGFloat) -> SessionSwipeStage {
        let travel = max(0, -offset)

        switch travel {
        case ..<8:
            return .closed
        case ..<dominantThreshold:
            return .actionsRevealed
        case ..<confirmThreshold:
            return .deleteDominant
        default:
            return .armedForDelete
        }
    }

    static func metrics(for offset: CGFloat) -> SessionSwipeMetrics {
        let travel = max(0, -offset)
        let railWidth = min(max(travel, 0), armedLockWidth)
        let takeoverProgress = clampedProgress(
            value: railWidth,
            lower: revealWidth,
            upper: dominantThreshold
        )
        let armedProgress = clampedProgress(
            value: railWidth,
            lower: dominantThreshold,
            upper: confirmThreshold
        )

        let pinWidth = max(0, pinBaseWidth * (1 - takeoverProgress) * (1 - armedProgress * 0.9))
        let targetDeleteWidth = max(deleteBaseWidth, railWidth - pinWidth)
        let deleteWidth = min(armedLockWidth, max(deleteBaseWidth, targetDeleteWidth))

        return SessionSwipeMetrics(
            stage: stage(for: offset),
            railWidth: railWidth,
            pinWidth: pinWidth,
            deleteWidth: deleteWidth,
            deleteIconScale: 1 + takeoverProgress * 0.08 + armedProgress * 0.18,
            deleteEmphasis: takeoverProgress * 0.7 + armedProgress * 0.3
        )
    }

    static func settleTarget(
        currentOffset: CGFloat,
        predictedEndOffset: CGFloat,
        velocity: CGFloat
    ) -> SessionSwipeSettleTarget {
        let currentTravel = max(0, -currentOffset)
        let predictedTravel = max(0, -predictedEndOffset)

        if currentTravel >= confirmThreshold * 0.88 || velocity <= armedVelocityThreshold {
            return .armedForDelete
        }

        if velocity >= closeVelocityThreshold {
            return .closed
        }

        let decisionTravel = max(currentTravel, predictedTravel)
        if decisionTravel >= revealWidth * 0.72 || velocity <= openVelocityThreshold {
            return .revealed
        }

        return .closed
    }

    static func targetOffset(for target: SessionSwipeSettleTarget) -> CGFloat {
        switch target {
        case .closed:
            return 0
        case .revealed:
            return -revealWidth
        case .armedForDelete:
            return -armedLockWidth
        }
    }

    private static func clampedProgress(value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper > lower else { return 0 }
        return min(1, max(0, (value - lower) / (upper - lower)))
    }
}
