import SwiftUI
import UIKit

enum ScanAppIcon: String, CaseIterable, Identifiable {
    case prism, stack, lens, ribbon, portal, folio, orbit, wave, archive, facet
    case art201, art202, art203, art204, art205, art206, art207, art208, art209, art210
    case art301, art302, art303, art304, art305, art306, art307, art308, art309, art310
    case glass, pearl, graphite, classic
    var id: String { rawValue }
    var name: String? {
        switch self {
        case .prism: return "ScanFlowPrism"
        case .stack: return "ScanFlowStack"
        case .lens: return "ScanFlowLens"
        case .ribbon: return "ScanFlowRibbon"
        case .portal: return "ScanFlowPortal"
        case .folio: return "ScanFlowFolio"
        case .orbit: return "ScanFlowOrbit"
        case .wave: return "ScanFlowWave"
        case .archive: return "ScanFlowArchive"
        case .facet: return "ScanFlowFacet"
        case .art201: return "ScanFlowArt201"
        case .art202: return "ScanFlowArt202"
        case .art203: return "ScanFlowArt203"
        case .art204: return "ScanFlowArt204"
        case .art205: return "ScanFlowArt205"
        case .art206: return "ScanFlowArt206"
        case .art207: return "ScanFlowArt207"
        case .art208: return "ScanFlowArt208"
        case .art209: return "ScanFlowArt209"
        case .art210: return "ScanFlowArt210"
        case .art301: return "ScanFlowArt301"
        case .art302: return "ScanFlowArt302"
        case .art303: return "ScanFlowArt303"
        case .art304: return "ScanFlowArt304"
        case .art305: return "ScanFlowArt305"
        case .art306: return "ScanFlowArt306"
        case .art307: return "ScanFlowArt307"
        case .art308: return "ScanFlowArt308"
        case .art309: return "ScanFlowArt309"
        case .art310: return "ScanFlowArt310"
        case .glass: return nil
        case .pearl: return "ScanFlowPearl"
        case .graphite: return "ScanFlowGraphite"
        case .classic: return "ScanFlowClassic"
        }
    }
    var title: String {
        switch self {
        case .prism: return "Перламутрові аркуші"
        case .stack: return "Перлинний сканер"
        case .lens: return "Перламутрова S"
        case .ribbon: return "Конверт"
        case .portal: return "Скляне фоліо"
        case .folio: return "Лупа"
        case .orbit: return "Органайзер"
        case .wave: return "Вигнутий аркуш"
        case .archive: return "Кришталева скріпка"
        case .facet: return "Кришталевий архів"
        case .art201: return "Блакитні аркуші"
        case .art202: return "Спектр"
        case .art203: return "Фіолетові панелі"
        case .art204: return "Зелений скан"
        case .art205: return "Бурштинова папка"
        case .art206: return "Коралова S"
        case .art207: return "Кольорові аркуші"
        case .art208: return "Блакитний сканер"
        case .art209: return "Лілова скріпка"
        case .art210: return "Кольорова лінза"
        case .art301: return "М’ятний сканер"
        case .art302: return "Бурштинова скріпка"
        case .art303: return "Розгорнуте фоліо"
        case .art304: return "Фіолетовий потік"
        case .art305: return "Зелений органайзер"
        case .art306: return "Сапфіровий об’єктив"
        case .art307: return "Рожева папка"
        case .art308: return "Кольорові кути"
        case .art309: return "Яскравий комплект"
        case .art310: return "Блакитна печатка"
        case .glass: return "Бірюзове скло"
        case .pearl: return "Хрусталь"
        case .graphite: return "Графіт"
        case .classic: return "Сканер"
        }
    }
    static let collections: [(title: String, icons: [Self])] = [
        ("Перламутр · 01–10", [.prism, .stack, .lens, .ribbon, .portal, .folio, .orbit, .wave, .archive, .facet]),
        ("Кольорове скло · 11–20", [.art201, .art202, .art203, .art204, .art205, .art206, .art207, .art208, .art209, .art210]),
        ("Нова колекція · 21–30", [.art301, .art302, .art303, .art304, .art305, .art306, .art307, .art308, .art309, .art310]),
    ]
    static let previous: [Self] = [.glass, .pearl, .graphite, .classic]
    static var current: Self {
        allCases.first { $0.name == UIApplication.shared.alternateIconName } ?? .glass
    }
}

struct AppIconPicker: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var current = ScanAppIcon.current
    @State private var pending: ScanAppIcon?
    @State private var errorMessage: String?

    var body: some View {
        ScrollViewReader { reader in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Іконка на екрані iPhone").font(.title2.bold())
                Text("30 іконок у трьох колекціях. Оберіть свій варіант.")
                    .foregroundStyle(.secondary)
                ForEach(Array(ScanAppIcon.collections.enumerated()), id: \.offset) { _, collection in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(collection.title).font(.headline)
                        iconGrid(collection.icons)
                    }
                }
                DisclosureGroup("Попередні іконки") {
                    iconGrid(ScanAppIcon.previous).padding(.top, 16)
                }
                Text("Для оригінальних кольорів оберіть стандартне оформлення іконок iPhone. Тонування системи може змінювати їхні кольори.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }
        .task {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--preview-icon-scroll"), index + 1 < args.count {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                reader.scrollTo(args[index + 1], anchor: .top)
            }
            #endif
        }
        }
        .navigationTitle("Іконка застосунку").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            current = .current
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verify-icon-switch") {
                verifyNativeSwitch()
            }
            #endif
        }
        .onChange(of: scenePhase) { _, value in if value == .active { current = .current } }
        .alert("Не вдалося змінити іконку", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Гаразд", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func iconGrid(_ icons: [ScanAppIcon]) -> some View {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 260 : 140), spacing: 16)], spacing: 16) {
                    ForEach(icons) { icon in
                        Button { change(to: icon) } label: {
                            VStack(spacing: 12) {
                                AppIconPreview(icon: icon).frame(width: 96, height: 96)
                                Text(icon.title).font(.body.weight(.semibold)).multilineTextAlignment(.center)
                                HStack(spacing: 6) {
                                    if pending == icon { ProgressView() }
                                    else { Image(systemName: current == icon ? "checkmark.circle.fill" : "circle").foregroundStyle(current == icon ? Color.accentColor : .secondary) }
                                    Text(pending == icon ? "Змінюю…" : (current == icon ? "Обрано" : "Обрати")).font(.caption)
                                }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 20).padding(.horizontal, 8)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
                            .contentShape(RoundedRectangle(cornerRadius: 24))
                        }
                        .id(icon.id)
                        .buttonStyle(.plain).disabled(pending != nil)
                        .accessibilityLabel(icon.title)
                        .accessibilityValue(current == icon ? "Обрано" : "")
                        .accessibilityAddTraits(current == icon ? .isSelected : [])
                    }
                }
    }

    #if DEBUG
    @MainActor private func verifyNativeSwitch() {
        Task { @MainActor in
            var report: [String: String] = ["supported": String(UIApplication.shared.supportsAlternateIcons)]
            for _ in 0..<30 {
                if UIApplication.shared.applicationState == .active { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            report["applicationActive"] = String(UIApplication.shared.applicationState == .active)
            do {
                try await UIApplication.shared.setAlternateIconName(ScanAppIcon.pearl.name)
                current = .current
                report["selected"] = UIApplication.shared.alternateIconName ?? "primary"
                report["result"] = current == .pearl ? "passed" : "failed"
            } catch {
                report["result"] = "simulator-error"
                report["error"] = error.localizedDescription
            }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
               let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                try? data.write(to: root.appendingPathComponent("icon-switch-verification.json"), options: .atomic)
            }
        }
    }
    #endif

    @MainActor private func change(to icon: ScanAppIcon) {
        guard pending == nil, current != icon else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "Система зараз не дозволяє змінити іконку. Спробуйте ще раз після перезапуску застосунку."
            return
        }
        pending = icon
        UIApplication.shared.setAlternateIconName(icon.name) { error in
            DispatchQueue.main.async {
                pending = nil
                current = .current
                if let error { errorMessage = error.localizedDescription }
            }
        }
    }
}

/// The approved artwork for illustrated icons; compiled fallback for legacy icons.
struct AppIconPreview: View {
    let icon: ScanAppIcon
    var body: some View {
        let name = icon.name ?? "ScanFlowIcon"
        if let image = UIImage(named: "IconPreview-" + name) {
            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 22)).accessibilityHidden(true)
        } else {
            Image(systemName: "app").resizable().scaledToFit().padding(16).foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}
