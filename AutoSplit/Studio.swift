import SwiftUI

enum StudioTab: String, CaseIterable {
    case home, scan, sets, archive, search

    var title: String {
        switch self {
        case .home: return "Головна"
        case .scan: return "Сканер"
        case .sets: return "Комплекти"
        case .archive: return "Архів"
        case .search: return "Пошук"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .scan: return "scanner.fill"
        case .sets: return "square.stack.3d.up.fill"
        case .archive: return "archivebox.fill"
        case .search: return "magnifyingglass"
        }
    }
}

enum StudioColor: String, CaseIterable, Identifiable {
    case automatic, teal, green, gold, berry, violet
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "Автоматично · за комплектом"
        case .teal: return "Бірюза"
        case .green: return "Олива"
        case .gold: return "Бурштин"
        case .berry: return "Гранат"
        case .violet: return "Ірис"
        }
    }
    var color: Color {
        switch self {
        case .automatic, .teal: return Color(red: 0, green: 0.54, blue: 0.58)
        case .green: return Color(red: 0.46, green: 0.60, blue: 0.015)
        case .gold: return Color(red: 0.82, green: 0.45, blue: 0)
        case .berry: return Color(red: 0.52, green: 0.12, blue: 0.19)
        case .violet: return Color(red: 0.38, green: 0.25, blue: 0.66)
        }
    }
    static func resolve(_ preference: String, seed: String, fallback: StudioColor) -> StudioColor {
        if let chosen = StudioColor(rawValue: preference), chosen != .automatic { return chosen }
        guard !seed.isEmpty else { return fallback }
        let choices: [StudioColor] = [.teal, .green, .gold, .berry, .violet]
        // Stable across launches; unlike Swift's randomized hashValue.
        let index = seed.utf8.reduce(0) { ($0 * 31 + Int($1)) % choices.count }
        return choices[index]
    }
}

struct StudioBackdrop: View {
    enum Palette { case home, teal, green, reader }
    let palette: Palette
    var seed: String = ""
    @AppStorage("scanflow.studio.palette") private var preference = "automatic"

    var body: some View {
        let tone = StudioColor.resolve(preference, seed: seed,
                                      fallback: palette == .home ? .berry : palette == .green ? .green : .teal).color
        Group {
            if palette == .home {
                // One continuous surface extends behind the navigation and hero.
                LinearGradient(stops: [
                    .init(color: tone.opacity(0.42), location: 0),
                    .init(color: tone.opacity(0.65), location: 0.42),
                    .init(color: .black, location: 0.78),
                    .init(color: .black, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [tone.opacity(palette == .reader ? 0.24 : 1),
                                        tone.opacity(palette == .reader ? 0.10 : 0.42), .black],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .background(.black)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct StudioTabs: View {
    @State private var selection = StudioTab.home
    @State private var captureFolder = "all"

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                modernTabs.tabBarMinimizeBehavior(.onScrollDown)
            } else {
                legacyTabs
            }
        }
        .tint(.white)
    }

    @available(iOS 26.0, *)
    private var modernTabs: some View {
        TabView(selection: $selection) {
            Tab("Головна", systemImage: "house.fill", value: StudioTab.home) {
                LibraryView(initialTab: .home, shellSelection: $selection, captureFolder: $captureFolder)
            }
            Tab("Сканер", systemImage: "scanner.fill", value: StudioTab.scan) {
                LibraryView(initialTab: .scan, shellSelection: $selection, captureFolder: $captureFolder)
            }
            Tab("Комплекти", systemImage: "square.stack.3d.up.fill", value: StudioTab.sets) {
                LibraryView(initialTab: .sets, shellSelection: $selection, captureFolder: $captureFolder)
            }
            Tab("Архів", systemImage: "archivebox.fill", value: StudioTab.archive) {
                LibraryView(initialTab: .archive, shellSelection: $selection, captureFolder: $captureFolder)
            }
            Tab("Пошук", systemImage: "magnifyingglass", value: StudioTab.search, role: .search) {
                LibraryView(initialTab: .search, shellSelection: $selection, captureFolder: $captureFolder)
            }
        }
    }

    private var legacyTabs: some View {
        TabView(selection: $selection) {
            ForEach(StudioTab.allCases, id: \.self) { tab in
                LibraryView(initialTab: tab, shellSelection: $selection, captureFolder: $captureFolder)
                    .tabItem { Label(tab.title, systemImage: tab.icon) }
                    .tag(tab)
            }
        }
    }
}

struct StudioGlassCapsule: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduced

    @ViewBuilder func body(content: Content) -> some View {
        if reduced {
            content.background(Color(white: 0.15), in: Capsule())
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

struct StudioGlassPanel: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @ViewBuilder func body(content: Content) -> some View {
        if reduced {
            content.background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 24))
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

struct StudioHero: View {
    let document: ScanDocument?
    let blocked: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let file = document?.pages.first?.output {
                    Thumb(file: file)
                        .frame(width: 163, height: 209)
                        .background(.white, in: RoundedRectangle(cornerRadius: 6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .rotationEffect(.degrees(-12))
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 10)
                } else {
                    Image(systemName: "doc.viewfinder").font(.system(size: 85, weight: .light))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 225)
            .accessibilityHidden(true)

            Text(document == nil ? "SCANFLOW" : "ОСТАННІЙ КОМПЛЕКТ")
                .font(.caption.weight(.semibold)).tracking(1).foregroundStyle(.white.opacity(0.74))
            Text(document?.title ?? "Скануйте документи")
                .font(.title.bold()).multilineTextAlignment(.center).lineLimit(2)
            if let document {
                Text("\(document.pages.count) стор. · PDF").font(.subheadline).foregroundStyle(.white.opacity(0.75))
            }
            Button(action: action) {
                Text(document == nil ? "Новий скан" : "Продовжити")
                    .font(.headline).frame(maxWidth: 245, minHeight: 48)
                    .modifier(StudioGlassCapsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(blocked).padding(.top, 7)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20)
        .padding(.bottom, 42)
        .frame(maxWidth: .infinity)

    }
}

struct StudioArchive: View {
    @State private var files: [URL] = []

    var body: some View {
        Group {
            if files.isEmpty {
                ContentUnavailableView("Поки немає експортів", systemImage: "archivebox",
                                       description: Text("Тут з’являться PDF та ZIP після експорту."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(files, id: \.self) { file in
                            ShareLink(item: file) {
                                HStack {
                                    Image(systemName: file.pathExtension.lowercased() == "zip" ? "doc.zipper" : "doc")
                                    Text(file.lastPathComponent).lineLimit(2)
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .frame(minHeight: 54)
                                .padding(.horizontal, 14)
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                }
            }
        }.task {
            files = await Task.detached(priority: .utility) {
                let manager = FileManager.default
                guard let root = manager.urls(for: .documentDirectory, in: .userDomainMask).first,
                      let entries = manager.enumerator(at: root.appendingPathComponent("Exports"),
                                                       includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                                                       options: [.skipsHiddenFiles]) else { return [URL]() }
                return entries.compactMap { item -> (URL, Date)? in
                    guard let url = item as? URL, ["pdf", "zip"].contains(url.pathExtension.lowercased()),
                          let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                          values.isRegularFile == true else { return nil }
                    return (url, values.contentModificationDate ?? .distantPast)
                }.sorted { $0.1 > $1.1 }.map { $0.0 }
            }.value
        }
    }
}
