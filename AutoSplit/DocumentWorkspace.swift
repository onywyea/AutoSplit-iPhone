import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct DocumentView:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("scanflow.studio") private var studio = true
    let documentID:UUID
    var startCamera=false
    var studioNavigate: ((StudioTab) -> Void)? = nil
    @State private var didStartCamera=false
    @State private var capturing=false
    @State private var importing=false
    @State private var photoPicker=false
    @State private var photoItems:[PhotosPickerItem]=[]
    @State private var importingPhotos=false
    @State private var exporting=false
    @State private var quickSharing=false
    @State private var naming=false
    @State private var handoff=false
    @State private var styling=false
    @State private var originals=false
    @State private var deletingDocument=false
    @State private var deletingPages=false
    @State private var selecting=false
    @State private var selected:Set<UUID>=[]
    @State private var styleTargets:Set<UUID>?
    @State private var filter=0
    @State private var ordering=false
    @State private var removed:[(Int,Leaf)]=[]
    var doc:ScanDocument? {store.document(documentID)}
    var pages:[Leaf] {doc?.pages ?? []}
    var issues:[Leaf] {pages.filter {$0.reviewReason != nil}}
    var shown:[Leaf] {pages.filter {filter==0 || (filter==1 ? $0.reviewReason != nil:$0.reviewReason==nil)}}
    var blocked:Bool {store.busy || store.savingPhotos>0 || importingPhotos}
    // Small opaque view boundaries keep each SwiftUI expression independently typed.
    var body:some View {
        confirmationScreen
            .alert("Не вдалося завершити дію",isPresented:errorPresented) {
                Button("Зрозуміло") {store.error=nil}
            } message:{Text(store.error ?? "")}
    }
    private var errorPresented:Binding<Bool> {
        Binding(get:{store.error != nil && !exporting},set:{if !$0 {store.error=nil}})
    }
    private var confirmationScreen:some View {
        sheetScreen
            .confirmationDialog(deletePagesTitle,isPresented:$deletingPages,titleVisibility:.visible) {
                Button("Видалити сторінки",role:.destructive) {removed=store.deletePages(documentID,ids:selected);selected=[]}
            } message:{Text("Цю дію можна скасувати кнопкою під сторінками.")}
            .confirmationDialog("Видалити весь скан?",isPresented:$deletingDocument,titleVisibility:.visible) {
                Button("Видалити скан",role:.destructive) {store.deleteDocument(documentID);dismiss()}
            }
    }
    private var deletePagesTitle:String {"Видалити вибрані сторінки: \(selected.count)?"}
    private var sheetScreen:some View {
        mediaScreen
            .sheet(isPresented:$exporting) {PDFExportSheet(ids:[documentID])}
            .sheet(isPresented:$quickSharing) {ShareSheet(urls:store.shareURLs)}
            .sheet(isPresented:$naming) {NameSheet(documentID:documentID)}
            .sheet(isPresented:$styling) {DocumentStyleSheet(documentID:documentID,pageIDs:styleTargets)}
            .sheet(isPresented:$handoff) {HandoffView(ids:[documentID])}
            .sheet(isPresented:$originals) {OriginalsExportSheet(documentID:documentID)}
    }
    private var mediaScreen:some View {
        navigationScreen
            .fullScreenCover(isPresented:$capturing,onDismiss:cameraDismissed) {CaptureView(documentID:documentID)}
            .fileImporter(isPresented:$importing,allowedContentTypes:[.pdf,.image],allowsMultipleSelection:true,onCompletion:importFilesResult)
            .photosPicker(isPresented:$photoPicker,selection:$photoItems,selectionBehavior:.ordered,matching:.images)
            .onChange(of:photoItems) {_,items in importSelectedPhotos(items)}
    }
    private var navigationScreen:some View {
        workspaceContent
            .navigationTitle(studio ? (doc?.title ?? "Комплект") : "Документ").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(studio ? .hidden : .automatic, for: .navigationBar)
            .toolbar {workspaceToolbar}
            .task(id:documentID) {await openDocument()}
            .onChange(of:pages.map(\.id)) {_,ids in selected.formIntersection(Set(ids))}
    }
    @ViewBuilder private var workspaceContent:some View {
        if let document=doc {
            VStack(spacing:0) {
                if store.busy {workingBar}
                if ordering {orderList}
                else if studio && !selecting {studioDocument}
                else {pageGrid(document)}
            }.background {
                if studio && !ordering && !selecting {
                    StudioBackdrop(palette: !pages.isEmpty && pages.allSatisfy { $0.reviewed == true } ? .green : .teal)
                } else {
                    ScanBackdrop()
                }
            }.safeAreaInset(edge: .bottom) {
                if studio && !ordering && !selecting && !pages.isEmpty && removed.isEmpty,
                   let studioNavigate {
                    StudioDock(selection: .sets, scanDisabled: blocked, select: studioNavigate)
                } else {
                    actionBar
                }
            }
        } else {ContentUnavailableView("Скан недоступний",systemImage:"doc")}
    }
    @ToolbarContentBuilder private var workspaceToolbar:some ToolbarContent {
        ToolbarItem(placement:.topBarTrailing) {
            if studio && !selecting && !ordering {
                Button("Експорт PDF") {exporting = true}.disabled(blocked || pages.isEmpty)
            } else {
                Button(selecting ? "Готово":"Вибрати") {selecting.toggle();selected=[];ordering=false}.disabled(blocked || pages.isEmpty)
            }
        }
        ToolbarItem(placement:.topBarTrailing) {documentMenu}
    }
    private func openDocument() async {
        if startCamera && !didStartCamera {didStartCamera=true;capturing=true;return}
        await store.ensureOrientation(documentID)
        await store.ensureEdgeProcessing(documentID)
        if pages.contains(where:{!$0.ocrReady}) {await store.analyze(documentID)}
        else {store.refreshNames(documentID)}
    }
    private func cameraDismissed() {Task {await store.analyze(documentID)}}
    private func importFilesResult(_ result:Result<[URL],Error>) {
        switch result {
        case .success(let urls):Task {await store.importFiles(urls,to:documentID);await store.analyze(documentID)}
        case .failure(let error):store.error=error.localizedDescription
        }
    }
    private func importSelectedPhotos(_ items:[PhotosPickerItem]) {
        guard !items.isEmpty else {return}
        importingPhotos=true
        Task {await store.importGallery(items,to:documentID);photoItems=[];importingPhotos=false;await store.analyze(documentID)}
    }
    private var studioDocument: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if pages.isEmpty {
                    ContentUnavailableView("Додайте першу сторінку", systemImage: "doc.viewfinder",
                                           description: Text("Скануйте серією або імпортуйте фото та PDF."))
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(pages) { page in
                                NavigationLink {
                                    PageBrowser(documentID: documentID, initialPageID: page.id)
                                } label: {
                                    studioPageTile(page)
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 18)
                    }.scrollIndicators(.hidden)
                    Text("Відомості про комплект").font(.title2.bold()).padding(.horizontal, 18)
                    studioDetails
                        .padding(.horizontal, 18)
                }
            }.padding(.vertical, 12)
        }.foregroundStyle(.white)
    }

    private func studioPageTile(_ page: Leaf) -> some View {
        VStack(spacing: 9) {
            Thumb(file: page.output)
                .frame(width: 96, height: 132)
                .background(.white, in: RoundedRectangle(cornerRadius: 5))
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text("Сторінка \((pages.firstIndex { $0.id == page.id } ?? 0) + 1)")
                .font(.subheadline.weight(.semibold))
            PageReviewBadge(page: page)
                .lineLimit(2)
                .frame(height: 32)
        }
        .frame(width: 147)
        .padding(.vertical, 13)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.20), lineWidth: 0.7))
    }

    private var studioDetails: some View {
        VStack(alignment: .leading, spacing: 0) {
            studioDetailRow("Сторінок: \(pages.count)", icon: "document.on.document")
            Divider()
            studioDetailRow("Розпізнано: \(pages.filter(\.ocrReady).count) із \(pages.count)", icon: "text.viewfinder")
            Divider()
            studioDetailRow("На перевірку: \(issues.count)", icon: "checkmark.circle")
            Divider()
            Button { exporting = true } label: {
                Label("Експорт PDF", systemImage: "arrow.up.right")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 52)
            }.buttonStyle(.plain).disabled(blocked)
        }
        .padding(.horizontal, 16)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(.white.opacity(0.20), lineWidth: 0.7))
    }

    private func studioDetailRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: icon).font(.title3).frame(width: 30)
            Text(title).font(.subheadline)
        }.frame(minHeight: 52)
    }

    private func pageGrid(_ document:ScanDocument)->some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                VStack(alignment:.leading,spacing:8) {
                    Text(document.title).font(.title2.weight(.semibold)).lineLimit(3)
                    HStack {
                        Text("\(pages.count) збережених стор.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Назва") {naming=true}.font(.subheadline).frame(minHeight:44)
                    }
                }
                if pages.isEmpty {
                    ContentUnavailableView("Додайте першу сторінку",systemImage:"doc.viewfinder",description:Text("Скануйте серією або імпортуйте фото та PDF."))
                } else {
                    WorkspaceFilters(selection:$filter)
                    if !issues.isEmpty && !selecting {
                        NavigationLink {PageBrowser(documentID:documentID,initialPageID:issues[0].id)} label:{
                            Label("Уточнити за бажанням",systemImage:"viewfinder").font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity,minHeight:44)
                        }.scanSecondaryButton()
                    }
                    if selecting {
                        HStack {
                            Text("Вибрано: \(selected.count)").font(.subheadline)
                            Spacer()
                            Button("Видимі") {selected.formUnion(shown.map(\.id))}.frame(minHeight:44)
                        }
                    }
                    if shown.isEmpty {ContentUnavailableView("Немає сторінок у цьому фільтрі",systemImage:"checkmark.circle")}
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:135),spacing:12)],spacing:12) {
                        ForEach(shown) {page in pageCell(page)}
                    }
                }
            }.padding(18)
        }
    }
    @ViewBuilder private func pageCell(_ page:Leaf)->some View {
        if selecting {
            Button {if selected.contains(page.id) {selected.remove(page.id)}else{selected.insert(page.id)}} label:{tile(page)}.buttonStyle(.plain).disabled(blocked)
                .accessibilityLabel("Сторінка \((pages.firstIndex(where:{$0.id==page.id}) ?? 0)+1)")
                .accessibilityValue(selected.contains(page.id) ? "Вибрано":"Не вибрано")
        } else {
            NavigationLink {PageBrowser(documentID:documentID,initialPageID:page.id)} label:{tile(page)}.buttonStyle(.plain)
        }
    }
    private func tile(_ page:Leaf)->some View {
        VStack(alignment:.leading,spacing:9) {
            ZStack(alignment:.topTrailing) {
                Thumb(file:page.output).frame(maxWidth:.infinity).frame(height:175).background(Color(uiColor:.tertiarySystemFill)).clipShape(RoundedRectangle(cornerRadius:9))
                if selecting {Image(systemName:selected.contains(page.id) ? "checkmark.circle.fill":"circle").font(.title2).foregroundStyle(Color.accent).padding(6).background(Color.card,in:Circle()).padding(6)}
            }
            Text("Сторінка \((pages.firstIndex(where:{$0.id==page.id}) ?? 0)+1)").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            PageReviewBadge(page:page).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading)
        }.padding(10).scanCard(radius:22)
            .overlay(RoundedRectangle(cornerRadius:22).stroke(selected.contains(page.id) && selecting ? Color.accent:.clear,lineWidth:2))
    }
    private var orderList:some View {
        List {
            Section("Перетягніть рядки, щоб змінити порядок") {
                ForEach(pages) {page in
                    HStack {Thumb(file:page.output).frame(width:38,height:52);Text("Сторінка \((pages.firstIndex(where:{$0.id==page.id}) ?? 0)+1)")}
                }.onMove {store.movePages(documentID,from:$0,to:$1)}
            }
        }.environment(\.editMode,.constant(.active)).disabled(blocked)
    }
    private var workingBar:some View {
        HStack {ProgressView();Text(store.status).font(.caption).lineLimit(2);Spacer();Button("Стоп") {store.cancel()}.font(.caption).frame(minHeight:44)}.padding(.horizontal,18)
    }
    private var actionBar:some View {
        VStack(spacing:10) {
            if !removed.isEmpty {
                Button {store.restorePages(documentID,removed:removed);removed=[]} label:{Label("Скасувати видалення · \(removed.count)",systemImage:"arrow.uturn.backward").font(.subheadline).frame(minHeight:44)}.disabled(blocked)
            }
            ScanControls {
            HStack(spacing:12) {
                if selecting {
                    Button(role:.destructive) {deletingPages=true} label:{Label("Видалити",systemImage:"trash").foregroundStyle(.red)}.scanSecondaryButton().disabled(selected.isEmpty || blocked)
                    Spacer(minLength:0)
                    Button {styleTargets=selected;styling=true} label:{Label("Стиль · \(selected.count)",systemImage:"slider.horizontal.3")}.scanSecondaryButton().disabled(selected.isEmpty || blocked)
                } else {
                    Button {importing=true} label:{Image(systemName:"square.and.arrow.down").frame(width:44,height:44)}.scanSecondaryButton().accessibilityLabel("Імпорт PDF або фото")
                    Menu {
                        Button {capturing=true} label:{Label("Камера",systemImage:"camera")}
                        Button {photoPicker=true} label:{Label("Фото з галереї",systemImage:"photo.on.rectangle")}
                        Button {importing=true} label:{Label("PDF або фото з Файлів",systemImage:"folder")}
                    } label:{Label("Додати",systemImage:"plus").frame(maxWidth:.infinity,minHeight:44)}.scanPrimaryButton()
                    Button {savePDF()} label:{Image(systemName:"square.and.arrow.up").frame(width:44,height:44)}.scanSecondaryButton().disabled(pages.isEmpty).accessibilityLabel("Експорт PDF")
                }
            }.font(.subheadline.weight(.semibold)).padding(.vertical,6).disabled(blocked)
            }
        }.padding(.horizontal,16).padding(.vertical,8)
    }
    private func savePDF() {
        Task {
            await store.export([documentID])
            if store.error==nil && !store.shareURLs.isEmpty {quickSharing=true}
        }
    }
    private var documentMenu:some View {
        Menu {
            if studio && !selecting && !ordering {
                Menu("Додати сторінки", systemImage: "plus") {
                    Button("Камера", systemImage: "camera") { capturing = true }
                    Button("Фото з галереї", systemImage: "photo.on.rectangle") { photoPicker = true }
                    Button("PDF або фото з Файлів", systemImage: "folder") { importing = true }
                }
                Button("Вибрати сторінки", systemImage: "checkmark.circle") {
                    selecting = true
                    selected = []
                }.disabled(pages.isEmpty)
            }
            Button {exporting=true} label:{Label("Розмір / стиснення PDF",systemImage:"doc.zipper")}
            Button {styleTargets=nil;styling=true} label:{Label("Стиль усіх сторінок",systemImage:"slider.horizontal.3")}
            Button(ordering ? "Завершити порядок":"Змінити порядок",systemImage:"arrow.up.arrow.down") {ordering.toggle();selecting=false;selected=[]}
            Button {naming=true} label:{Label("Перейменувати",systemImage:"pencil")}
            Button {Task{await store.analyze(documentID,force:true)}} label:{Label("Оновити розпізнавання",systemImage:"text.viewfinder")}
            Button {handoff=true} label:{Label("Підготувати для ChatGPT",systemImage:"sparkles")}
            Button("Експорт оригіналів фото") {originals=true}
            Button("Обробити краї всіх сторінок") {Task{await store.ensureEdgeProcessing(documentID,force:true)}}
            Button("Відновити з оригіналів") {Task{await store.rebuildSafely(documentID)}}
            Button("Повторити автоповорот") {Task{await store.rotateAutomatically(documentID)}}
            Button("Видалити весь скан",role:.destructive) {deletingDocument=true}
        } label:{Image(systemName:"ellipsis.circle")}.disabled(blocked).accessibilityLabel("Дії документа")
    }
}
