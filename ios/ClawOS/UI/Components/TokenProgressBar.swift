import SwiftUI

struct TokenProgressBar: View {
    let label: String
    let value: String
    let progress: Double
    var tint: Color = Color(.label)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            ProgressView(value: progress)
                .tint(tint)
        }
    }
}
