import SwiftUI
import UIKit

enum ScanAppIcon: String, CaseIterable, Identifiable {
    case glass, pearl, graphite, classic
    var id: String { rawValue }
    var name: String? {
        switch self {
        case .glass: return nil
        case .pearl: return "ScanFlowPearl"
        case .graphite: return "ScanFlowGraphite"
        case .classic: return "ScanFlowClassic"
        }
    }
    var title: String {
        switch self {
        case .glass: return "Бірюзове скло"
        case .pearl: return "Хрусталь"
        case .graphite: return "Графіт"
        case .classic: return "Сканер"
        }
    }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Іконка на екрані iPhone").font(.title2.bold())
                Text("Оберіть іконку для головного екрана iPhone.")
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: textSize.isAccessibilitySize ? 260 : 140), spacing: 16)], spacing: 16) {
                    ForEach(ScanAppIcon.allCases) { icon in
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
                        .buttonStyle(.plain).disabled(pending != nil)
                        .accessibilityLabel(icon.title)
                        .accessibilityValue(current == icon ? "Обрано" : "")
                        .accessibilityAddTraits(current == icon ? .isSelected : [])
                    }
                }
                Text("Вигляд скла залежить від світлого, темного або прозорого оформлення іконок у налаштуваннях iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
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

/// Use the actual compiled icon fallback supplied by Xcode, not a separate drawing.
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
