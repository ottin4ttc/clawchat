import Foundation

enum StreamingTypewriter {
    static let charactersPerTick = 2
    static let tickIntervalMilliseconds = 40
    static let followScrollDelayMilliseconds = 12
    static let tickInterval: Duration = .milliseconds(tickIntervalMilliseconds)
    static let followScrollDelay: Duration = .milliseconds(followScrollDelayMilliseconds)

    static func nextDisplayText(
        current: String,
        target: String,
        charactersPerTick: Int = charactersPerTick
    ) -> String {
        guard !target.isEmpty else { return "" }
        guard current != target else { return target }
        guard charactersPerTick > 0 else { return current }

        // The relay/client state is authoritative. If our UI buffer drifted, snap back.
        guard target.hasPrefix(current) else { return target }

        let nextCount = min(target.count, current.count + charactersPerTick)
        return String(target.prefix(nextCount))
    }
}
