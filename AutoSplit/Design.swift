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
