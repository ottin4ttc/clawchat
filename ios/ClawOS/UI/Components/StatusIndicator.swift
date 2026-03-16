import SwiftUI

struct StatusIndicator: View {
    let status: AgentStatus
    var size: CGFloat = 14
    var borderWidth: CGFloat = 2.5

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(.background, lineWidth: borderWidth)
            )
    }
}
