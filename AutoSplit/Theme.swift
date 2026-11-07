import SwiftUI
import UIKit

#if !compiler(>=6.2)
#error("ScanFlow needs Xcode 26+. Upload .github/workflows/build.yml from this update and start a NEW Run workflow.")
#endif

enum ScanTheme: String {
    case system, light, dark, monochrome

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .monochrome: return .dark
        }
    }
}

private struct ScanThemeKey: EnvironmentKey {
    static let defaultValue = ScanTheme.system
}

extension EnvironmentValues {
    var scanTheme: ScanTheme {
        get { self[ScanThemeKey.self] }
        set { self[ScanThemeKey.self] = newValue }
    }
}

extension Color {
    static let canvas=Color(uiColor:UIColor {trait in trait.userInterfaceStyle == .dark ? UIColor(red:0.055,green:0.065,blue:0.080,alpha:1):UIColor(red:0.970,green:0.956,blue:0.936,alpha:1)})
    static let card=Color(uiColor:UIColor {trait in trait.userInterfaceStyle == .dark ? UIColor(red:0.105,green:0.122,blue:0.145,alpha:1):.white})
    static var accent:Color {Color.accentColor}
    static var scanAction:Color {Color.accentColor}
    static let scanSuccess=Color(uiColor:UIColor {trait in trait.userInterfaceStyle == .dark ? UIColor(red:0.38,green:0.85,blue:0.66,alpha:1):UIColor(red:0.04,green:0.41,blue:0.25,alpha:1)})
    static let scanOutline=Color.primary.opacity(0.09)
}
struct ScanBackdrop:View {
    @Environment(\.scanTheme) private var theme
    var body: some View {
        background.ignoresSafeArea().allowsHitTesting(false)
    }

    @ViewBuilder private var background: some View {
        switch theme {
        case .system:
            Color.canvas.overlay(RadialGradient(colors: [Color.accent.opacity(0.10), .clear],
                                                center: .topTrailing, startRadius: 0, endRadius: 330))
        case .dark:
            LinearGradient(colors: [Color(white: 0.10), Color(white: 0.045)], startPoint: .top, endPoint: .bottom)
        case .light:
            LinearGradient(colors: [Color(red: 0.98, green: 0.97, blue: 0.96), Color(white: 0.94)],
                           startPoint: .top, endPoint: .bottom)
        case .monochrome:
            LinearGradient(colors: [Color(white: 0.34), Color(white: 0.19)], startPoint: .top, endPoint: .bottom)
        }
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
    @Environment(\.scanTheme) private var theme
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.subheadline.weight(.semibold)).padding(.horizontal,16).frame(minHeight:44)
            .foregroundStyle(prominent && theme == .system ? Color.white : (prominent ? Color.canvas : Color.primary))
            .background(prominent ? Color.scanAction:Color.card,in:Capsule())
            .overlay(Capsule().stroke(prominent ? Color.white.opacity(0.18):Color.scanOutline,lineWidth:1))
            .opacity(enabled ? (configuration.isPressed ? 0.75:1):0.4)
    }
}
struct ScanButtonModifier:ViewModifier {
    let prominent:Bool
    @Environment(\.scanTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @ViewBuilder func body(content:Content)->some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0,*),!reduced {
            if prominent && theme == .system {content.buttonStyle(.glassProminent).buttonBorderShape(.capsule).tint(Color.scanAction).foregroundStyle(.white).controlSize(.regular)}
            else {content.buttonStyle(.glass).buttonBorderShape(.capsule).tint(theme == .system ? Color.scanAction : Color.primary).controlSize(.regular)}
        } else {content.buttonStyle(ScanPillStyle(prominent:prominent))}
        #else
        content.buttonStyle(ScanPillStyle(prominent:prominent))
        #endif
    }
}
struct ScanControls<Content:View>:View {
    @Environment(\.accessibilityReduceTransparency) private var reduced
    let content:Content
    init(@ViewBuilder content:()->Content) {self.content=content()}
    @ViewBuilder var body:some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0,*), !reduced {GlassEffectContainer(spacing:12) {content}}
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
    @AppStorage("scanflow.accent") private var accentID="coral"
    @AppStorage("scanflow.studio") private var studio = true
    @AppStorage("scanflow.studio.palette") private var palette = "automatic"
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
                    Toggle("Новий вигляд ScanFlow", isOn: $studio)
                    Picker("Тема класичного вигляду",selection:$appearance) {
                        Text("Як в iPhone").tag("system")
                        Text("Світла · теплий папір").tag("light")
                        Text("Темна · графіт").tag("dark")
                        Text("Монохром · срібло").tag("monochrome")
                    }.pickerStyle(.inline).disabled(studio)
                }
                if studio {
                    Section("Колір простору") {
                        Picker("Градієнт", selection: $palette) {
                            ForEach(StudioColor.allCases) { color in
                                Label { Text(color.title) } icon: {
                                    Image(systemName: "circle.fill").foregroundStyle(color.color)
                                }.tag(color.rawValue)
                            }
                        }.pickerStyle(.inline)
                        Text("Автоматичний колір залишається однаковим для комплекту та змінюється при переході до іншого. Колір сканованих сторінок не змінюється.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !studio && appearance == "system" {
                    Section("Акцентний колір") {
                        Picker("Колір кнопок",selection:$accentID) {
                            ForEach(ScanAccent.allCases) {accent in
                                Label {Text(accent.title)} icon:{Image(systemName:"circle.fill").foregroundStyle(accent.color)}.tag(accent.rawValue)
                            }
                        }.pickerStyle(.inline)
                    }
                }
                Section("Ефект панелей") {
                    Label(effect,systemImage:"circle.lefthalf.filled")
                    Text("Документ не покривається склом. Пониження прозорості в налаштуваннях iPhone вимикає прозорі ефекти.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Версія") {
                    let info = Bundle.main.infoDictionary
                    let version = info?["CFBundleShortVersionString"] as? String ?? ""
                    let build = info?["CFBundleVersion"] as? String ?? ""
                    Text("ScanFlow \(version) · \(build)")
                }
            }.navigationTitle("Вигляд").navigationBarTitleDisplayMode(.inline)
                .toolbar {ToolbarItem(placement:.confirmationAction) {Button("Готово") {dismiss()}}}
        }.tint(.accent)
    }
}
