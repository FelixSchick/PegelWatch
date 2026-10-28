import SwiftUI

/// Floating guidance hint that appears at the bottom of a view, reacts to
/// user actions, and dismisses permanently when the user taps ×.
struct GuidanceCard: View {
    let icon: String
    let iconColor: Color
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(iconColor)
                .frame(width: 28, alignment: .center)
                .padding(.top, 1)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Label("Hinweis ausblenden", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    // 44 pt Trefferfläche, optisch bleibt das Symbol klein
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, -12)
            .padding(.trailing, -12)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 12, y: 4)
        .padding(.horizontal, 16)
    }
}
