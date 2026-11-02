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
        ZStack {
            RoundedRectangle(cornerRadius:13).fill(LinearGradient(colors:[Color(red:0.30,green:0.85,blue:0.73),Color.accent],startPoint:.topLeading,endPoint:.bottomTrailing))
            RoundedRectangle(cornerRadius:13).stroke(.white.opacity(0.35),lineWidth:1)
            Image(systemName:"doc.viewfinder").font(.system(size:25,weight:.medium)).foregroundStyle(.white).shadow(color:.black.opacity(0.18),radius:1,y:2)
        }.frame(width:44,height:44).accessibilityHidden(true)
    }
}
extension Leaf {
    // Status describes actual metadata, not an invented scan-quality score.
    var reviewReason:String? {
        if sourceKind=="camera" && cropVerified != true {return "Уточніть межі"}
        if reviewed==true {return nil}
        let lower=note.lowercased()
        if lower.contains("напрям") || lower.contains("поворот") && lower.contains("перевір") {return "Перевірте поворот"}
        if lower.contains("невпев") {return "Перевірте текст"}
        if !ocrReady {return "Розпізнавання очікує"}
        return nil
    }
}
struct PageReviewBadge:View {
    let page:Leaf
    var body:some View {
        Label(page.reviewReason ?? (page.reviewed==true ? "Перевірено вами":"Перевірки завершено"),systemImage:page.reviewReason == nil ? "checkmark.circle":"exclamationmark.circle")
            .font(.caption).foregroundStyle(page.reviewReason == nil ? Color.accent:Color.orange)
    }
}
