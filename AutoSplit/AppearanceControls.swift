import SwiftUI

struct AppearanceControls:View {
    @Binding var leaf:Leaf
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            Picker("Стиль",selection:$leaf.finish) {ForEach(Finish.allCases,id:\.self) {Text($0.rawValue).tag($0)}}.pickerStyle(.menu)
            Text("Контраст тексту та печаток").font(.subheadline)
            HStack {
                Slider(value:Binding(get:{leaf.inkStrength ?? ((leaf.finish == .white || leaf.finish == .clean) ? 0.75:0)},set:{leaf.inkStrength=$0}),in:0...1.5,step:0.05)
                Text(String(format:"%.0f%%",(leaf.inkStrength ?? ((leaf.finish == .white || leaf.finish == .clean) ? 0.75:0))*100)).font(.caption.monospacedDigit()).frame(width:52)
            }
            Text("Підсилює чорний текст і колір печаток. 0% — без підсилення. Застосовується до сторінки або всього скану за вашим вибором.").font(.caption).foregroundStyle(.secondary)
            Text("Різкість").font(.subheadline)
            HStack {
                Slider(value:Binding(get:{leaf.sharpness ?? ((leaf.finish == .white || leaf.finish == .clean) ? 0.85:0)},set:{leaf.sharpness=$0}),in:0...1.5,step:0.05)
                Text(String(format:"%.0f%%",(leaf.sharpness ?? ((leaf.finish == .white || leaf.finish == .clean) ? 0.85:0))*100)).font(.caption.monospacedDigit()).frame(width:52)
            }
            Text("0% — без підсилення. Надмірна різкість може підкреслювати зерно копії; втрачений фокус вона не відновлює.").font(.caption).foregroundStyle(.secondary)
            Toggle("Очищати край",isOn:Binding(get:{leaf.edgeFill},set:{leaf.edgeFill=$0;leaf.edgeChoiceExplicit=true})).tint(.accent)
            DisclosureGroup("Налаштування краю") {
                VStack(alignment:.leading,spacing:12) {
                    Text("Запас навколо знайденої межі").font(.subheadline)
                    HStack {
                        Slider(value:Binding(get:{(leaf.edgeReach ?? 0.08)*100},set:{leaf.edgeReach=$0/100}),in:0...24,step:1)
                        Text(String(format:"%.0f px",(leaf.edgeReach ?? 0.08)*100)).font(.caption.monospacedDigit()).frame(width:52)
                    }
                    Text("Плавний перехід на папір").font(.subheadline)
                    HStack {
                        Slider(value:Binding(get:{(leaf.edgeOverlap ?? 0.06)*100},set:{leaf.edgeOverlap=$0/100}),in:2...12,step:0.5)
                        Text(String(format:"%.1f%%",(leaf.edgeOverlap ?? 0.06)*100)).font(.caption.monospacedDigit()).frame(width:52)
                    }
                    Text("Запас розширює знайдену маску фону. Перехід пом’якшує стик на папері зі збереженням тексту. Довгі тонкі залишки на самому краю перевіряються окремо.").font(.caption).foregroundStyle(.secondary)
                }.padding(.top,10).disabled(!leaf.edgeFill)
            }
        }
    }
}
