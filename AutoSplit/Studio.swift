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

struct StudioBackdrop: View {
    enum Palette { case home, teal, green, reader }
    let palette: Palette

    private var colors: [Color] {
        switch palette {
        case .home: return [.black, .black]
        case .reader: return [Color(red: 0.035, green: 0.14, blue: 0.17), Color(red: 0.02, green: 0.06, blue: 0.08)]
        case .teal: return [Color(red: 0, green: 0.60, blue: 0.64), Color(red: 0.01, green: 0.17, blue: 0.19), Color(red: 0, green: 0.08, blue: 0.09)]
        case .green: return [Color(red: 0.48, green: 0.63, blue: 0.02), Color(red: 0.23, green: 0.34, blue: 0.01), Color(red: 0.08, green: 0.15, blue: 0)]
        }
    }

    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct StudioTabs: View {
    @State private var selection = StudioTab.home

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
                LibraryView(initialTab: .home, shellSelection: $selection)
            }
            Tab("Сканер", systemImage: "scanner.fill", value: StudioTab.scan) {
                LibraryView(initialTab: .scan, shellSelection: $selection)
            }
            Tab("Комплекти", systemImage: "square.stack.3d.up.fill", value: StudioTab.sets) {
                LibraryView(initialTab: .sets, shellSelection: $selection)
            }
            Tab("Архів", systemImage: "archivebox.fill", value: StudioTab.archive) {
                LibraryView(initialTab: .archive, shellSelection: $selection)
            }
            Tab("Пошук", systemImage: "magnifyingglass", value: StudioTab.search, role: .search) {
                LibraryView(initialTab: .search, shellSelection: $selection)
            }
        }
    }

    private var legacyTabs: some View {
        TabView(selection: $selection) {
            ForEach(StudioTab.allCases, id: \.self) { tab in
                LibraryView(initialTab: tab, shellSelection: $selection)
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
        .background {
            LinearGradient(stops: [
                .init(color: Color(white: 0.15), location: 0),
                .init(color: Color(white: 0.12), location: 0.38),
                .init(color: Color(red: 0.33, green: 0.10, blue: 0.12), location: 0.72),
                .init(color: .black, location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
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
