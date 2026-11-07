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
    @Environment(\.dynamicTypeSize) private var typeSize

    private var label: StudioDocumentText {
        StudioDocumentText(title: document?.title ?? "Скануйте документи",
                           personName: document?.personName, suffix: document?.nameSuffix)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioPageFan(files: Array((document?.pages ?? []).prefix(3).map(\.output)))
                .padding(.bottom, 4)
            Text(document == nil ? "SCANFLOW" : "ОСТАННІЙ КОМПЛЕКТ")
                .font(.caption.weight(.medium)).tracking(1.5)
                .foregroundStyle(.white.opacity(0.72))
            Text(label.title)
                .font(.title.bold()).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if !label.detail.isEmpty {
                Text(label.detail).font(.title3).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let document {
                Text("\(document.pages.count) стор. · PDF")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
            Button(action: action) {
                HStack(spacing: 14) {
                    Text(document == nil ? "Новий скан" : "Продовжити")
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "arrow.right")
                }
                .font(.headline).padding(.horizontal, 20).padding(.vertical, 10)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : 260, minHeight: 50)
                .modifier(StudioGlassCapsule()).contentShape(Capsule())
            }
            .buttonStyle(.plain).disabled(blocked).padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)

    }
}

struct StudioPageFan: View {
    let files: [String]
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.82, 300)
            let pageWidth = width * 0.43
            let pageHeight = pageWidth * 1.4142
            ZStack {
                if files.count > 1 {
                    paper(files[1], width: pageWidth * 0.96, height: pageHeight * 0.96)
                        .rotationEffect(.degrees(reducedMotion ? 0 : -9))
                        .offset(x: -width * (files.count > 2 ? 0.22 : 0.12), y: 3)
                }
                if files.count > 2 {
                    paper(files[2], width: pageWidth * 0.96, height: pageHeight * 0.96)
                        .rotationEffect(.degrees(reducedMotion ? 0 : 9))
                        .offset(x: width * 0.22, y: 3)
                }
                if let first = files.first {
                    paper(first, width: pageWidth, height: pageHeight)
                        .offset(x: files.count == 2 ? width * 0.10 : 0)
                } else {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 72, weight: .light)).foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .frame(height: 192)
        .accessibilityHidden(true)
    }

    private func paper(_ file: String, width: CGFloat, height: CGFloat) -> some View {
        CachedScanThumbnail(file: file, limit: 720)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: .black.opacity(0.24), radius: 9, y: 7)
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
