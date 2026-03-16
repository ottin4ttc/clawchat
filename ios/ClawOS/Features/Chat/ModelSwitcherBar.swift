import SwiftUI

struct ModelSwitcherBar: View {
    @Binding var selectedModel: String
    @Binding var showModelPicker: Bool

    var body: some View {
        Button { showModelPicker = true } label: {
            HStack(spacing: 4) {
                Text(selectedModel)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}
