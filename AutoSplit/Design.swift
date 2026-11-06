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
                    .modifier(ScanSpectralRim(strength: 0.55))
            } else {
                content.background(.regularMaterial, in: Capsule())
                    .modifier(ScanSpectralRim(strength: 0.55))
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
                    arc(Color(red: 0.72, green: 0.53, blue: 1), start: 0, peak: 0.10, end: 0.25)
                        .offset(x: -0.45)
                    arc(Color(red: 0.32, green: 0.83, blue: 0.93), start: 0.40, peak: 0.52, end: 0.66)
                        .offset(x: 0.45)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }

    private func arc(_ color: Color, start: CGFloat, peak: CGFloat, end: CGFloat) -> some View {
        Capsule().strokeBorder(
            AngularGradient(stops: [
                .init(color: .clear, location: start),
                .init(color: color.opacity(intensity), location: peak),
                .init(color: .clear, location: end)
            ], center: .center),
            lineWidth: 1.1
        )
    }

    private var intensity: Double { strength * (scheme == .dark ? 0.65 : 0.48) }
}

struct LibraryRowSurface: ViewModifier {
    let selected: Bool
    @Environment(\.scanTheme) private var theme

    @ViewBuilder func body(content: Content) -> some View {
        if theme == .system {
            content.scanCard(radius: 24)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(selected ? Color.accent : .clear, lineWidth: 2))
        } else {
            content
                .background(selected ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .bottom) { Divider().allowsHitTesting(false) }
        }
    }
}
