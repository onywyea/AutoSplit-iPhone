import SwiftUI

// The small circular wordmark is UI text with a native SF Symbol at its center.
// It stays sharp at every display scale and doesn't carry a background tile.
struct StudioAppearanceSeal: View {
    var body: some View {
        ZStack {
            sealText("ВИГЛЯД", from: -155, to: -25, lower: false)
            sealText("SCANFLOW", from: 155, to: 25, lower: true)
            Image(systemName: "paintpalette.fill")
                .font(.system(size: 19, weight: .semibold))
            Circle().frame(width: 2.2, height: 2.2).offset(x: -24)
            Circle().frame(width: 2.2, height: 2.2).offset(x: 24)
        }
        .foregroundStyle(.white)
        .frame(width: 56, height: 56)
        .contentShape(Circle())
        .accessibilityHidden(true)
    }

    private func sealText(_ text: String, from start: Double, to end: Double, lower: Bool) -> some View {
        let letters = Array(text)
        return ZStack {
            ForEach(letters.indices, id: \.self) { index in
                let angle = start + (end - start) * Double(index) / Double(max(1, letters.count - 1))
                Text(String(letters[index]))
                    .font(.system(size: lower ? 6.1 : 6.7, weight: .heavy, design: .rounded))
                    .rotationEffect(.degrees(angle + (lower ? -90 : 90)))
                    .offset(x: CGFloat(22 * cos(angle * .pi / 180)), y: CGFloat(22 * sin(angle * .pi / 180)))
            }
        }
    }
}
