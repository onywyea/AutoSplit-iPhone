import SwiftUI
import UIKit

#if !compiler(>=6.2)
#error("ScanFlow 0.4.5 needs Xcode 26+. Upload .github/workflows/build.yml from this update and start a NEW Run workflow.")
#endif

extension Color {
    static let canvas=Color(uiColor:UIColor {trait in trait.userInterfaceStyle == .dark ? UIColor(red:0.055,green:0.065,blue:0.080,alpha:1):UIColor(red:0.970,green:0.956,blue:0.936,alpha:1)})
    static let card=Color(uiColor:UIColor {trait in trait.userInterfaceStyle == .dark ? UIColor(red:0.105,green:0.122,blue:0.145,alpha:1):.white})
    static let accent=Color(uiColor:UIColor {trait in trait.userInterfaceStyle == .dark ? UIColor(red:1,green:0.63,blue:0.43,alpha:1):UIColor(red:0.71,green:0.22,blue:0.07,alpha:1)})
    static let scanAction=Color(red:0.78,green:0.27,blue:0.10)
    static let scanSuccess=Color(uiColor:UIColor {trait in trait.userInterfaceStyle == .dark ? UIColor(red:0.38,green:0.85,blue:0.66,alpha:1):UIColor(red:0.04,green:0.41,blue:0.25,alpha:1)})
    static let scanOutline=Color.primary.opacity(0.09)
}
struct ScanBackdrop:View {
    var body:some View {
        Color.canvas.overlay(RadialGradient(colors:[Color.accent.opacity(0.10),.clear],center:.topTrailing,startRadius:0,endRadius:330)).ignoresSafeArea().allowsHitTesting(false)
    }
}
struct ScanCard:ViewModifier {
    let radius:CGFloat
    func body(content:Content)->some View {
        content.background(Color.card,in:RoundedRectangle(cornerRadius:radius))
            .overlay(RoundedRectangle(cornerRadius:radius).stroke(Color.scanOutline,lineWidth:0.7))
    }
}
struct ScanPillStyle:ButtonStyle {
    let prominent:Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.subheadline.weight(.semibold)).padding(.horizontal,16).frame(minHeight:50)
            .foregroundStyle(prominent ? Color.white:Color.primary)
            .background(prominent ? Color.scanAction:Color.card,in:Capsule())
            .overlay(Capsule().stroke(prominent ? Color.white.opacity(0.18):Color.scanOutline,lineWidth:1))
            .opacity(enabled ? (configuration.isPressed ? 0.75:1):0.4)
    }
}
struct ScanButtonModifier:ViewModifier {
    let prominent:Bool
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @ViewBuilder func body(content:Content)->some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0,*),!reduced {
            if prominent {content.buttonStyle(.glassProminent).buttonBorderShape(.capsule).tint(Color.scanAction).foregroundStyle(.white).controlSize(.large)}
            else {content.buttonStyle(.glass).buttonBorderShape(.capsule).tint(Color.primary).controlSize(.large)}
        } else {content.buttonStyle(ScanPillStyle(prominent:prominent))}
        #else
        content.buttonStyle(ScanPillStyle(prominent:prominent))
        #endif
    }
}
struct ScanControls<Content:View>:View {
    let content:Content
    init(@ViewBuilder content:()->Content) {self.content=content()}
    @ViewBuilder var body:some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0,*) {GlassEffectContainer(spacing:12) {content}}
        else {content}
        #else
        content
        #endif
    }
}
extension View {
    func scanPrimaryButton()->some View {modifier(ScanButtonModifier(prominent:true))}
    func scanSecondaryButton()->some View {modifier(ScanButtonModifier(prominent:false))}
    func scanCard(radius:CGFloat=22)->some View {modifier(ScanCard(radius:radius))}
}
struct WorkspaceFilters:View {
    @Binding var selection:Int
    var body:some View {
        HStack(spacing:8) {
            chip("Усі",value:0)
            chip("Уточнити",value:1)
            chip("Готові",value:2)
        }.accessibilityElement(children:.contain).accessibilityLabel("Фільтр сторінок")
    }
    private func chip(_ title:String,value:Int)->some View {
        Button {selection=value} label: {
            Text(title).font(.subheadline.weight(.medium)).frame(maxWidth:.infinity,minHeight:44)
                .foregroundStyle(selection==value ? Color.canvas:Color.primary)
                .background(selection==value ? Color.primary:Color.card,in:Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selection==value ? .isSelected:[])
    }
}
struct AppearanceSheet:View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @AppStorage("scanflow.appearance") private var appearance="system"
    private var effect:String {
        if reduced {return "Непрозорий · системна доступність"}
        #if compiler(>=6.2)
        if #available(iOS 26.0,*) {return "Liquid Glass · нативний"}
        #endif
        return "Звичайний матеріал · сумісність"
    }
    var body:some View {
        NavigationStack {
            Form {
                Section("Оформлення") {
                    Picker("Тема",selection:$appearance) {
                        Text("Як в iPhone").tag("system")
                        Text("Світла · теплий папір").tag("light")
                        Text("Темна · графіт").tag("dark")
                    }.pickerStyle(.inline)
                }
                Section("Ефект панелей") {
                    Label(effect,systemImage:"circle.lefthalf.filled")
                    Text("Документ не покривається склом. Пониження прозорості в налаштуваннях iPhone вимикає прозорі ефекти.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Версія") {Text("ScanFlow 0.4.5 · 24")}
            }.navigationTitle("Вигляд").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.confirmationAction) {Button("Готово") {dismiss()}}}
        }.tint(.accent)
    }
}
