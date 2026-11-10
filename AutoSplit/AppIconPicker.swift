import SwiftUI
import UIKit

enum ScanAppIcon: String, CaseIterable, Identifiable {
    case amber, violet, coral, cyan, pink
    var id: String { rawValue }
    var name: String? {
        switch self {
        case .amber: return nil
        case .violet: return "ScanFlowViolet"
        case .coral: return "ScanFlowCoral"
        case .cyan: return "ScanFlowCyan"
        case .pink: return "ScanFlowPink"
        }
    }
    var title: String {
        switch self {
        case .amber: return "Бурштиновий документ"
        case .violet: return "Фіолетова стрічка"
        case .coral: return "Кораловий сканер"
        case .cyan: return "Блакитний сканер"
        case .pink: return "Рожева папка"
        }
    }
    static let collections: [(title: String, icons: [Self])] = [
        ("Іконки ScanFlow", [.amber, .violet, .coral, .cyan, .pink])
    ]
    static let previous: [Self] = []
    static var current: Self {
        allCases.first { $0.name == UIApplication.shared.alternateIconName } ?? .amber
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
                Text("5 іконок. Оберіть свій варіант.")
                    .foregroundStyle(.secondary)
                ForEach(Array(ScanAppIcon.collections.enumerated()), id: \.offset) { _, collection in
                    VStack(alignment: .leading, spacing: 16) {
                        Text(collection.title).font(.headline)
                        iconGrid(collection.icons)
                    }
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
                try await UIApplication.shared.setAlternateIconName(ScanAppIcon.violet.name)
                current = .current
                report["selected"] = UIApplication.shared.alternateIconName ?? "primary"
                report["result"] = current == .violet ? "passed" : "failed"
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
        let name = icon.name ?? "ScanFlowAmber"
        if let image = UIImage(named: "IconPreview-" + name) {
            Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 22)).accessibilityHidden(true)
        } else {
            Image(systemName: "app").resizable().scaledToFit().padding(16).foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}
