import SwiftUI
import UniformTypeIdentifiers

@main
struct ScanFlowApp:App {
    @StateObject private var store=ScannerStore()
    @AppStorage("scanflow.appearance") private var appearance="system"
    @AppStorage("scanflow.accent") private var accentID="coral"
    var body:some Scene { WindowGroup { LibraryView().environmentObject(store).environment(\.locale,Locale(identifier:"uk_UA")).tint(ScanAccent(rawValue:accentID)?.color ?? ScanAccent.coral.color).accentColor(ScanAccent(rawValue:accentID)?.color ?? ScanAccent.coral.color).preferredColorScheme(appearance=="dark" ? .dark:(appearance=="light" ? .light:nil)) } }
}
struct LibraryView:View {
    @EnvironmentObject var store:ScannerStore
    @State private var path:[UUID]=[]
    @State private var search=""
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
        libraryList
            .background(ScanBackdrop())
            .navigationTitle("ScanFlow")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden,for:.navigationBar)
            .searchable(text:$search,prompt:"ПІБ або назва документа")
            .toolbar {libraryToolbar}
            .safeAreaInset(edge:.bottom) {bottomBar}
            .navigationDestination(for:UUID.self) {id in DocumentView(documentID:id,startCamera:newCapture==id)}
            .onChange(of:folder) {_,_ in selected=[]}
            .onChange(of:search) {_,_ in selected=[]}
            .onChange(of:store.folders.map(\.id)) {_,ids in if let id=currentFolder,!ids.contains(id) {folder="all"}}
            .onChange(of:path) {previous,ids in trackPath(previous,ids)}
            .onChange(of:store.documents.map(\.id)) {_,ids in selected.formIntersection(Set(ids))}
    }
    private var libraryList:some View {
        ScrollView {
            LazyVStack(alignment:.leading,spacing:14) {
            if !selecting && search.isEmpty {
                LibraryBrandSection()
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
            Button(selecting ? "Готово":"Вибрати") {selecting.toggle();selected=[]}.disabled(store.busy || store.documents.isEmpty)
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
            let id=store.newDocument(folderID:currentFolder);path.append(id)
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
                if selecting {selectionDock}else{captureDock}
            }.padding(.horizontal,18).padding(.vertical,10)
        }
    }
    private var captureDock:some View {
        HStack(spacing:12) {
            Button {importing=true} label:{Image(systemName:"square.and.arrow.down").frame(width:34,height:44)}
                .scanSecondaryButton().accessibilityLabel("Імпорт фото або PDF").disabled(store.busy)
            Button {let id=store.newDocument(folderID:currentFolder);newCapture=id;path.append(id)} label:{
                Label("Новий скан",systemImage:"camera.fill").font(.headline).frame(maxWidth:.infinity,minHeight:44)
            }.scanPrimaryButton().disabled(store.busy)
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
