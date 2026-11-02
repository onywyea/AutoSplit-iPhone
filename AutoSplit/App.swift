import SwiftUI
import UniformTypeIdentifiers

extension Color {
    static let canvas=Color(uiColor:.systemGroupedBackground)
    static let card=Color(uiColor:.secondarySystemGroupedBackground)
    static let accent=Color(red:0.09,green:0.55,blue:0.49)
}
@main
struct ScanFlowApp:App {
    @StateObject private var store=ScannerStore()
    var body:some Scene { WindowGroup { LibraryView().environmentObject(store).environment(\.locale,Locale(identifier:"uk_UA")).tint(.accent) } }
}
struct LibraryView:View {
    @EnvironmentObject var store:ScannerStore
    @State private var path:[UUID]=[]
    @State private var search=""
    @State private var selecting=false
    @State private var selected:Set<UUID>=[]
    @State private var handingOff=false
    @State private var exporting=false
    @State private var deleting=false
    @State private var renaming:ScanDocument?
    @State private var importing=false
    @State private var newCapture:UUID?
    @AppStorage("scanflow.lastDocument") private var lastDocument=""
    var resume:ScanDocument? {
        if let previous=store.documents.first(where:{$0.id.uuidString==lastDocument && !$0.pages.isEmpty}) {return previous}
        return store.documents.first {document in
            !document.pages.isEmpty && document.pages.contains(where:{$0.reviewReason != nil})
        }
    }
    var filtered:[ScanDocument] {store.documents.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)}}
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
            .sheet(isPresented:$handingOff) {HandoffView(ids:selected)}
            .sheet(isPresented:$exporting) {PDFExportSheet(ids:selected)}
            .sheet(item:$renaming) {document in NameSheet(documentID:document.id)}
    }
    private var libraryScreen:some View {
        libraryList
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.canvas)
            .navigationTitle("Документи")
            .searchable(text:$search,prompt:"ПІБ або назва документа")
            .toolbar {libraryToolbar}
            .safeAreaInset(edge:.bottom) {bottomBar}
            .navigationDestination(for:UUID.self) {id in DocumentView(documentID:id,startCamera:newCapture==id)}
            .onChange(of:path) {previous,ids in trackPath(previous,ids)}
            .onChange(of:store.documents.map(\.id)) {_,ids in selected.formIntersection(Set(ids))}
    }
    private var libraryList:some View {
        List {
            if !selecting && search.isEmpty {
                LibraryBrandSection()
                if let document=resume {
                    LibraryResumeSection(document:document,disabled:store.busy) {path.append(document.id)}
                }
            }
            documentSection
        }
    }
    @ViewBuilder private var documentSection:some View {
        if filtered.isEmpty {
            LibraryEmptyState(searching:!search.isEmpty)
        } else {
            Section {
                ForEach(filtered) {document in documentButton(document)}
            } header: {Text(sectionTitle)}
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
        Button {renaming=document} label:{Label("Перейменувати",systemImage:"pencil")}
        Button {selected=[document.id];exporting=true} label:{Label("Експорт / стиснення PDF",systemImage:"square.and.arrow.up")}
        Button {selected=[document.id];handingOff=true} label:{Label("Завдання для ChatGPT",systemImage:"sparkles")}
        Button(role:.destructive) {selected=[document.id];deleting=true} label:{Label("Видалити скан",systemImage:"trash")}
    }
    @ToolbarContentBuilder private var libraryToolbar:some ToolbarContent {
        ToolbarItem(placement:.topBarTrailing) {
            Button(selecting ? "Готово":"Вибрати") {selecting.toggle();selected=[]}.disabled(store.busy || store.documents.isEmpty)
        }
        ToolbarItem(placement:.topBarLeading) {
            if selecting {Button("Усі") {selected=Set(filtered.map(\.id))}.disabled(store.busy)}
        }
    }
    private var errorPresented:Binding<Bool> {
        Binding(get:{store.error != nil && !exporting},set:{if !$0 {store.error=nil}})
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
            let id=store.newDocument();path.append(id)
            Task {await store.importFiles(urls,to:id);await store.analyze(id)}
        case .failure(let error):store.error=error.localizedDescription
        }
    }
    private func toggle(_ id:UUID) {if selected.contains(id){selected.remove(id)}else{selected.insert(id)}}
    private var bottomBar:some View {
        VStack(spacing:10) {
            if store.busy {HStack{ProgressView();Text(store.status).font(.caption).lineLimit(1)}}
            if selecting {
                HStack {
                    Button(role:.destructive){deleting=true}label:{Label("Видалити",systemImage:"trash").font(.subheadline)}
                    Spacer()
                    Menu {
                        Button{exporting=true}label:{Label("Експорт / стиснення PDF",systemImage:"doc.zipper")}
                        Button{handingOff=true}label:{Label("Завдання для ChatGPT",systemImage:"sparkles")}
                    } label:{Label("Експорт",systemImage:"square.and.arrow.up").font(.subheadline.weight(.semibold))}
                }.frame(minHeight:44).disabled(selected.isEmpty || store.busy)
            } else {
                HStack(spacing:12) {
                Button {importing=true} label:{Image(systemName:"square.and.arrow.down").frame(width:44,height:44)}.accessibilityLabel("Імпорт фото або PDF").disabled(store.busy)
                Button{let id=store.newDocument();newCapture=id;path.append(id)}label:{Label("Новий скан",systemImage:"camera").font(.headline).frame(maxWidth:.infinity,minHeight:44)}
                    .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius:16)).disabled(store.busy)
                }
            }
        }.padding(12).scanGlass().padding(.horizontal,16).padding(.vertical,8)
    }
}
struct Thumb:View {
    let file:String?
    var body:some View {CachedScanThumbnail(file:file)}
}
struct NameSheet:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let documentID:UUID
    @State private var name=""
    var body:some View {
        NavigationStack {
            Form {
                Section("Назва PDF"){TextField("Прізвище Ім’я По батькові",text:$name)}
                Section {
                    ForEach(store.document(documentID)?.candidates ?? []) { candidate in
                        Button{name=candidate.name}label:{VStack(alignment:.leading,spacing:6){Text(candidate.name).foregroundStyle(.primary);Text(candidate.evidence).font(.caption).foregroundStyle(.secondary)}}
                    }
                } header:{Text("Знайдені імена")}footer:{Text("Програма не завжди розрізняє військовослужбовця, заявника й родичів. Відмінок ПІБ автоматично не виправляється.")}
            }.navigationTitle("Назва документа").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Зберегти"){store.rename(documentID,name);dismiss()}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}
            .onAppear{name=store.document(documentID)?.title ?? ""}
        }
    }
}
