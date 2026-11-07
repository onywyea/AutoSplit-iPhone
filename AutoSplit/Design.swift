import SwiftUI

// Native Liquid Glass for controls only. Older SDKs/OS and Reduce Transparency
// retain an opaque/material control surface, never a glass document canvas.
struct ScanGlassModifier:ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let radius:CGFloat
    @ViewBuilder func body(content:Content)->some View {
        if reduceTransparency {
            content.background(Color.card,in:RoundedRectangle(cornerRadius:radius))
        } else {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular,in:RoundedRectangle(cornerRadius:radius))
            } else {
                content.background(.regularMaterial,in:RoundedRectangle(cornerRadius:radius))
            }
            #else
            content.background(.regularMaterial,in:RoundedRectangle(cornerRadius:radius))
            #endif
        }
    }
}
extension View {
    func scanGlass(radius:CGFloat=22)->some View {modifier(ScanGlassModifier(radius:radius))}
}
struct ScanMark:View {
    var body:some View {
        Image("BrandMark").resizable().scaledToFit().frame(width:48,height:48)
            .clipShape(RoundedRectangle(cornerRadius:13)).accessibilityHidden(true)
    }
}
extension Leaf {
    // Status describes actual metadata, not an invented scan-quality score.
    var reviewReason:String? {
        if sourceKind=="camera" && cropVerified != true {return "Автокраї не визначені"}
        if reviewed==true {return nil}
        // OCR confidence, an advisory orientation note, and pending OCR do
        // not create a mandatory visual-review queue in the fast workflow.
        let lower=note.lowercased()
        if lower.contains("не вдалося") || lower.contains("не знайдено оригінал") {return "Автообробка не завершена"}
        return nil
    }
}
struct PageReviewBadge:View {
    let page:Leaf
    private var title:String {
        if let reason=page.reviewReason {return reason}
        if page.reviewed==true {return "Перевірено вами"}
        return page.ocrReady ? "Автооброблено":"Збережено"
    }
    var body:some View {
        Label(title,systemImage:page.reviewReason == nil ? "checkmark.circle":"exclamationmark.circle")
            .font(.caption).foregroundStyle(page.reviewReason == nil ? Color.scanSuccess:Color.accent)
    }
}

struct ScanCaptureButton: ViewModifier {
    @Environment(\.scanTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduced

    @ViewBuilder func body(content: Content) -> some View {
        if theme == .system || reduced {
            content.scanPrimaryButton()
        } else if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.capsule)
                .controlSize(.large)
                .modifier(ScanSpectralRim())
        } else {
            content.buttonStyle(.plain)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .modifier(ScanSpectralRim())
        }
    }
}

struct ScanFolderSurface: ViewModifier {
    let active: Bool
    let accent: Color
    @Environment(\.scanTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduced

    @ViewBuilder func body(content: Content) -> some View {
        if theme == .system {
            content.background(accent.opacity(active ? 0.23 : 0.07), in: Capsule())
                .overlay(Capsule().stroke(accent.opacity(active ? 0.8 : 0.22), lineWidth: 1))
        } else if active && !reduced {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                content.background(.regularMaterial, in: Capsule())
            }
        } else {
            content.background(Color.primary.opacity(active ? 0.18 : 0.07), in: Capsule())
        }
    }
}

private struct ScanSpectralRim: ViewModifier {
    var strength: Double = 1
    @Environment(\.scanTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content.overlay {
            if theme != .monochrome && enabled {
                ZStack {
                    Capsule()
                        .strokeBorder(spectrum(shift: 0), lineWidth: 1.6)
                    Capsule()
                        .inset(by: 1.8)
                        .strokeBorder(spectrum(shift: 0.035, reversed: true), lineWidth: 1.05)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func spectrum(shift: CGFloat, reversed: Bool = false) -> AngularGradient {
        let cyan = scheme == .dark ? Color(red: 0.32, green: 0.88, blue: 1) : Color(red: 0.08, green: 0.53, blue: 0.76)
        let violet = scheme == .dark ? Color(red: 0.88, green: 0.56, blue: 1) : Color(red: 0.68, green: 0.29, blue: 0.83)
        let opacity = strength * (reversed ? 0.54 : 0.86)
        let first = reversed ? cyan : violet
        let second = reversed ? violet : cyan
        return AngularGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: first.opacity(opacity), location: 0.12 + shift),
            .init(color: .clear, location: 0.31 + shift),
            .init(color: .clear, location: 0.42 + shift),
            .init(color: second.opacity(opacity), location: 0.58 + shift),
            .init(color: .clear, location: 0.81 + shift),
            .init(color: .clear, location: 1)
        ], center: .center)
    }
}

struct LibraryRowSurface: ViewModifier {
    let selected: Bool
    @Environment(\.scanTheme) private var theme

    @Environment(\.displayScale) private var displayScale

    @ViewBuilder func body(content: Content) -> some View {
        if theme == .system {
            content.scanCard(radius: 24)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(selected ? Color.accent : .clear, lineWidth: 2))
        } else {
            content
                .background(selected ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.10))
                        .frame(maxWidth: .infinity)
                        .frame(height: 1 / displayScale)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        }
    }
}
