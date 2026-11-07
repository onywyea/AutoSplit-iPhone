import SwiftUI
import UniformTypeIdentifiers

@main
struct ScanFlowApp:App {
    @StateObject private var store=ScannerStore()
    @AppStorage("scanflow.appearance") private var appearance="system"
    @AppStorage("scanflow.accent") private var accentID="coral"
    @AppStorage("scanflow.studio") private var studio = true
    private var theme: ScanTheme { ScanTheme(rawValue: appearance) ?? .system }
    private var tint: Color {
        theme == .system ? (ScanAccent(rawValue: accentID) ?? .coral).color : .primary
    }
    var body: some Scene {
        WindowGroup {
            appRoot
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "uk_UA"))
                .environment(\.scanTheme, theme)
                .tint(tint)
                .accentColor(tint)
                .preferredColorScheme(studio ? .dark : theme.scheme)
        }
    }
    @ViewBuilder private var appRoot: some View {
        if studio { StudioTabs() } else { LibraryView() }
    }

}
struct LibraryView:View {
    @EnvironmentObject var store:ScannerStore
    @State private var path:[UUID]=[]
    @State private var search=""
    @AppStorage("scanflow.studio") private var studio = true
    @State private var studioTab: StudioTab
    var shellSelection: Binding<StudioTab>?
    var captureFolder: Binding<String>?
    @State private var scannerStarted = false
    @State private var heroIndex = 0
    @ScaledMetric(relativeTo: .title) private var heroHeight = 470

    init(initialTab: StudioTab = .home, shellSelection: Binding<StudioTab>? = nil, captureFolder: Binding<String>? = nil) {
        _studioTab = State(initialValue: initialTab)
        self.shellSelection = shellSelection
        self.captureFolder = captureFolder
    }
    @FocusState private var searchFocused: Bool
    @Environment(\.scanTheme) private var theme
    @State private var selecting=false
    @State private var selected:Set<UUID>=[]
    private struct ExportRequest: Identifiable {
        let id = UUID()
        let ids: Set<UUID>
        let chat: Bool
        let folderName: String?
    }
    @State private var exportRequest: ExportRequest?
    @State private var deleting=false
    @State private var renaming:ScanDocument?
    @State private var folder="all"
    @State private var moveRequest:ScanMoveRequest?
    @State private var managingFolders=false
    @State private var importing=false
    @State private var appearancePresented=false
    @State private var newCapture:UUID?
    @AppStorage("scanflow.lastDocument") private var lastDocument=""
    var resume:ScanDocument? {
        if let previous=store.documents.first(where:{$0.id.uuidString==lastDocument && !$0.pages.isEmpty}) {return previous}
        return store.documents.first {document in
            !document.pages.isEmpty && document.pages.contains(where:{$0.reviewReason != nil})
        }
    }
    var currentFolder:UUID? {UUID(uuidString:folder)}
    var filtered:[ScanDocument] {store.documents.filter{(folder=="all" || (folder=="unfiled" ? $0.folderID==nil:$0.folderID==currentFolder)) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))}}
    var body:some View {
        NavigationStack(path:$path) {
            presentedScreen
                .confirmationDialog("Видалити вибрані скани: \(selected.count)?",isPresented:$deleting,titleVisibility:.visible) {
                    Button("Видалити скани",role:.destructive) {deleteSelected()}
                } message: {
                    Text("Скани зникнуть із бібліотеки застосунку. Раніше експортовані PDF залишаться у «Файлах».")
                }
                .alert("Не вдалося завершити дію",isPresented:errorPresented) {
                    Button("Зрозуміло") {store.error=nil}
                } message: {Text(store.error ?? "")}
        }
        .onAppear {
            if studio && studioTab == .scan && !scannerStarted {
                scannerStarted = true
                startScan()
            }
        }
    }
    // Distinct opaque view boundaries keep Xcode 16's constraint solver from
    // type-checking the complete list, toolbar and presentations as one tree.
    private var presentedScreen:some View {
        libraryScreen
            .fileImporter(isPresented:$importing,allowedContentTypes:[.pdf,.image],allowsMultipleSelection:true, onCompletion:importResult)
            .sheet(item: $exportRequest) { request in
                if request.chat {
                    HandoffView(ids: request.ids, batchName: request.folderName)
                } else {
                    PDFExportSheet(ids: request.ids, batchName: request.folderName)
                }
            }
            .sheet(item:$moveRequest) {request in FolderPicker(request:request,onMoved:{selected=[];selecting=false})}
            .sheet(isPresented:$managingFolders) {FolderManager()}
            .sheet(isPresented:$appearancePresented) {AppearanceSheet()}
            .sheet(item:$renaming) {document in NameSheet(documentID:document.id)}
    }
    private var libraryScreen:some View {
        libraryRoot
            .navigationTitle(studio ? studioTab.title : "ScanFlow")
            .navigationBarTitleDisplayMode(studio ? .large : .inline)
            .toolbarBackground(studio && studioTab != .home ? .automatic : .hidden, for: .navigationBar)
            .toolbar {libraryToolbar}
            .safeAreaInset(edge:.bottom) {bottomBar}
            .navigationDestination(for: UUID.self) { id in
                DocumentView(documentID: id, startCamera: newCapture == id)
            }
            .onChange(of:folder) { _, value in
                selected = []
                if studioTab == .sets { captureFolder?.wrappedValue = value }
            }
            .onChange(of:search) {_,_ in selected=[]}
            .onChange(of:store.folders.map(\.id)) {_,ids in if let id=currentFolder,!ids.contains(id) {folder="all"}}
            .onChange(of:path) {previous,ids in trackPath(previous,ids)}
            .onChange(of:store.documents.map(\.id)) {_,ids in selected.formIntersection(Set(ids))}
    }
    @ViewBuilder private var libraryRoot: some View {
        if studio {
            studioContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StudioBackdrop(palette: studioTab == .home ? .home : .teal, seed: studioBackdropSeed))
                .foregroundStyle(.white)
                .environment(\.scanTheme, .dark)
                .tint(.white)
        } else {
            searchableLibrary.background(ScanBackdrop())
        }
    }

    private var studioBackdropSeed: String {
        if studioTab == .home {
            let recent = Array(store.documents.filter { !$0.pages.isEmpty }.prefix(10))
            let latest = resume ?? recent.first
            let featured = latest.map { first in [first] + Array(recent.filter { $0.id != first.id }.prefix(3)) } ?? []
            return featured.indices.contains(heroIndex) ? featured[heroIndex].id.uuidString : ""
        }
        return folder == "all" ? studioTab.rawValue : folder
    }

    @ViewBuilder private var studioContent: some View {
        switch studioTab {
        case .home: studioHome
        case .archive: StudioArchive()
        case .search:
            libraryList.searchable(text: $search, prompt: "ПІБ або назва документа")
        case .scan:
            VStack(spacing: 18) {
                Image(systemName: "doc.viewfinder").font(.system(size: 64, weight: .light))
                Text("Новий комплект").font(.title2.bold())
                Button("Сканувати", action: startScan).scanPrimaryButton()
                Button("Імпорт PDF або фото") { importing = true }.scanSecondaryButton()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        default: libraryList
        }
    }

    private var studioHome: some View {
        let recent = Array(store.documents.filter { !$0.pages.isEmpty }.prefix(10))
        let latest = resume ?? recent.first
        let featured = latest.map { first in
            [first] + Array(recent.filter { $0.id != first.id }.prefix(3))
        } ?? []
        return ScrollView {
            if featured.isEmpty {
                StudioHero(document: nil, blocked: store.busy || store.savingPhotos > 0, action: startScan)
            } else {
                TabView(selection: $heroIndex) {
                    ForEach(Array(featured.enumerated()), id: \.element.id) { index, document in
                        StudioHero(document: document, blocked: store.busy || store.savingPhotos > 0) {
                            openDocument(document.id)
                        }.tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: featured.count > 1 ? .automatic : .never))
                .frame(height: heroHeight)
                .onChange(of: featured.map(\.id)) { _, _ in heroIndex = 0 }
            }
            VStack(alignment: .leading, spacing: 18) {
                if !recent.isEmpty {
                    Text("Недавні скани").font(.title2.bold()).padding(.horizontal, 18)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(recent) { document in
                                Button { openDocument(document.id) } label: {
                                    VStack(spacing: 7) {
                                        Thumb(file: document.pages.first?.output)
                                            .frame(width: 77, height: 86)
                                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                        Text(document.title).font(.caption).lineLimit(2).frame(width: 77)
                                    }.accessibilityElement(children: .combine)
                                }.buttonStyle(.plain).disabled(store.busy || store.savingPhotos > 0)
                            }
                        }.padding(.horizontal, 18)
                    }.scrollIndicators(.hidden)
                }
                Button { selectTab(.sets) } label: {
                    HStack {
                        Label("Усі комплекти", systemImage: "square.stack.3d.up.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.font(.headline).frame(minHeight: 48)
                }.buttonStyle(.plain).padding(.horizontal, 18)
            }.padding(.bottom, 20)
        }
    }

    private func selectTab(_ tab: StudioTab) {
        if let shellSelection {
            shellSelection.wrappedValue = tab
        } else if tab == .scan {
            startScan()
        } else {
            studioTab = tab
        }
    }

    private var scanFolder: UUID? {
        if studio && studioTab == .scan {
            guard let id = UUID(uuidString: captureFolder?.wrappedValue ?? ""),
                  store.folders.contains(where: { $0.id == id }) else { return nil }
            return id
        }
        return !studio || studioTab == .sets ? currentFolder : nil
    }

    private func startScan() {
        guard !store.busy, store.savingPhotos == 0 else { return }
        let id = store.newDocument(folderID: scanFolder)
        newCapture = id
        path.append(id)
    }

    @ViewBuilder private var searchableLibrary: some View {
        if theme == .system {
            libraryList.searchable(text: $search, prompt: "ПІБ або назва документа")
        } else {
            libraryList
        }
    }

    private var librarySearch: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Пошук документів", text: $search)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("Очистити пошук")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.6).allowsHitTesting(false))
    }

    private var libraryList:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:14) {
            if !studio && !selecting && (search.isEmpty || theme != .system) { LibraryBrandSection() }
            if !studio && theme != .system {
                librarySearch.onAppear { if studio && studioTab == .search { searchFocused = true } }
            }
            if !studio && !selecting && search.isEmpty {
                if folder=="all",let document=resume {
                    LibraryResumeSection(document:document,disabled:store.busy) {path.append(document.id)}
                }
            }
            FolderShelf(selection:$folder,manage:{managingFolders=true})
            if !selecting, let folder = store.folders.first(where: { $0.id == currentFolder }) {
                folderActions(folder)
            }
            documentSection
            }.padding(.horizontal,18).padding(.vertical,12)
        }
    }
    private func folderActions(_ folder: ScanFolder) -> some View {
        let ids = Set(store.documents.filter { $0.folderID == folder.id && !$0.pages.isEmpty }.map(\.id))
        return Menu {
            Button { presentExport(ids, chat: false, folderName: folder.name) } label: {
                Label("Експорт і стиснення PDF", systemImage: "doc.zipper")
            }
            Button { presentExport(ids, chat: true, folderName: folder.name) } label: {
                Label("Завдання для ChatGPT", systemImage: "sparkles")
            }
        } label: {
            Label("Уся папка · \(ids.count)", systemImage: "folder.badge.gearshape")
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
        }.disabled(ids.isEmpty || store.busy || store.savingPhotos > 0)
    }

    private func presentExport(_ ids: Set<UUID>, chat: Bool, folderName: String? = nil) {
        guard !ids.isEmpty, !store.busy, store.savingPhotos == 0 else { return }
        exportRequest = ExportRequest(ids: ids, chat: chat, folderName: folderName)
    }

    @ViewBuilder private var documentSection:some View {
        if filtered.isEmpty {
            LibraryEmptyState(searching:!search.isEmpty)
        } else {
            Text(sectionTitle).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top,8)
            ForEach(filtered) {document in documentButton(document)}
        }
    }
    private var sectionTitle:String {selecting ? "Вибрано: \(selected.count)":"Документів: \(filtered.count)"}
    private func documentButton(_ document:ScanDocument)->some View {
        Button {openDocument(document.id)} label: {
            LibraryDocumentRow(document:document,selecting:selecting,selected:selected.contains(document.id))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(document.title)
        .accessibilityValue(selecting && selected.contains(document.id) ? "Вибрано":"")
        .contextMenu {documentMenu(document)}
        .disabled(store.busy || store.savingPhotos>0)
    }
    @ViewBuilder private func documentMenu(_ document:ScanDocument)->some View {
        Button {beginMove([document.id])} label:{Label("Перемістити в папку",systemImage:"folder")}
        Button {renaming=document} label:{Label("Перейменувати",systemImage:"pencil")}
        Button {presentExport([document.id], chat: false)} label:{Label("Експорт / стиснення PDF",systemImage:"square.and.arrow.up")}
        Button {presentExport([document.id], chat: true)} label:{Label("Завдання для ChatGPT",systemImage:"sparkles")}
        Button(role:.destructive) {selected=[document.id];deleting=true} label:{Label("Видалити скан",systemImage:"trash")}
    }
    @ToolbarContentBuilder private var libraryToolbar:some ToolbarContent {
        ToolbarItem(placement:.topBarTrailing) {
            if studio && studioTab == .home {
                Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                    .accessibilityLabel("Імпорт PDF або фото").disabled(store.busy)
            } else if !studio || studioTab != .archive {
                Button(selecting ? "Готово":"Вибрати") {selecting.toggle();selected=[]}.disabled(store.busy || store.documents.isEmpty)
            }
        }
        ToolbarItem(placement:.topBarLeading) {
            if selecting {Button("Усі") {selected=Set(filtered.map(\.id))}.disabled(store.busy)}
            else {Button {appearancePresented=true} label:{Image(systemName:"paintpalette")}.accessibilityLabel("Вигляд і Liquid Glass")}
        }
    }
    private var errorPresented:Binding<Bool> {
        Binding(get:{store.error != nil && exportRequest == nil && moveRequest==nil},set:{if !$0 {store.error=nil}})
    }
    private func openDocument(_ id:UUID) {
        if selecting {toggle(id)}else{path.append(id)}
    }
    private func deleteSelected() {store.deleteDocuments(selected);selected=[];selecting=false}
    private func trackPath(_ previous:[UUID],_ ids:[UUID]) {
        if let id=ids.last {lastDocument=id.uuidString}else{newCapture=nil}
    }
    private func importResult(_ result:Result<[URL],Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else {return}
            let id=store.newDocument(folderID: scanFolder);path.append(id)
            Task {await store.importFiles(urls,to:id);await store.analyze(id)}
        case .failure(let error):store.error=error.localizedDescription
        }
    }
    private func beginMove(_ ids:Set<UUID>) {moveRequest=store.prepareMove(ids)}
    private var visibleSelection:Set<UUID> {selected.intersection(Set(filtered.map(\.id)))}
    private func toggle(_ id:UUID) {if selected.contains(id){selected.remove(id)}else{selected.insert(id)}}
    private var bottomBar:some View {
        ScanControls {
            VStack(spacing:10) {
                if store.busy {HStack {ProgressView();Text(store.status).font(.caption).lineLimit(1)}}
                if selecting {selectionDock}
                else if !studio {captureDock}
            }.padding(.horizontal, studio && !selecting ? 0 : 18).padding(.vertical, studio && !selecting ? 0 : 10)
        }
    }
    private var captureDock:some View {
        HStack(spacing:12) {
            Button {importing=true} label:{Image(systemName:"square.and.arrow.down").frame(width:34,height:44)}
                .scanSecondaryButton().accessibilityLabel("Імпорт фото або PDF").disabled(store.busy)
            Button(action: startScan) {
                Label("Новий скан",systemImage:"camera.fill").font(.headline).frame(maxWidth:.infinity,minHeight:44)
            }.modifier(ScanCaptureButton()).disabled(store.busy)
        }
    }
    private var selectionDock:some View {
        HStack(spacing:12) {
            Button(role:.destructive) {deleting=true} label:{Label("Видалити",systemImage:"trash").foregroundStyle(.red)}.scanSecondaryButton()
            Spacer(minLength:0)
            Button {beginMove(visibleSelection)} label:{Label("У папку (\(visibleSelection.count))",systemImage:"folder")}.scanSecondaryButton()
            Menu {
                Button {presentExport(visibleSelection, chat: false)} label:{Label("Експорт / стиснення PDF",systemImage:"doc.zipper")}
                Button {presentExport(visibleSelection, chat: true)} label:{Label("Завдання для ChatGPT",systemImage:"sparkles")}
            } label:{Label("Дії",systemImage:"ellipsis.circle").font(.subheadline.weight(.semibold))}.scanSecondaryButton()
        }.disabled(visibleSelection.isEmpty || store.busy || store.savingPhotos>0)
    }

}
struct Thumb:View {
    let file:String?
    var body:some View {CachedScanThumbnail(file:file)}
}
