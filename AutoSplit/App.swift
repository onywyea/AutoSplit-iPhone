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
    var filtered:[ScanDocument] {store.documents.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)}}
    var body:some View {
        NavigationStack(path:$path) {
            List {
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "Поки немає сканів":"Нічого не знайдено",systemImage:search.isEmpty ? "doc.viewfinder":"magnifyingglass",description:Text(search.isEmpty ? "Скануйте камерою або імпортуйте PDF і фото.":"Спробуйте іншу назву."))
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(filtered) { doc in
                            Button {
                                if selecting {toggle(doc.id)}else{path.append(doc.id)}
                            } label:{row(doc)}
                            .buttonStyle(.plain)
                            .accessibilityLabel(doc.title)
                            .accessibilityValue(selecting && selected.contains(doc.id) ? "Вибрано":"")
                            .contextMenu {
                                Button{renaming=doc}label:{Label("Перейменувати",systemImage:"pencil")}
                                Button{selected=[doc.id];exporting=true}label:{Label("Експорт / стиснення PDF",systemImage:"square.and.arrow.up")}
                                Button{selected=[doc.id];handingOff=true}label:{Label("Завдання для ChatGPT",systemImage:"sparkles")}
                                Button(role:.destructive){selected=[doc.id];deleting=true}label:{Label("Видалити скан",systemImage:"trash")}
                            }.disabled(store.busy || store.savingPhotos>0)
                        }
                    } header:{Text(selecting ? "Вибрано: \(selected.count)":"Документів: \(filtered.count)")}
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Color.canvas)
            .navigationTitle("Скани")
            .searchable(text:$search,prompt:"Назва документа")
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button(selecting ? "Готово":"Вибрати"){selecting.toggle();selected=[]}.disabled(store.busy || store.documents.isEmpty)
                }
                ToolbarItem(placement:.topBarLeading) {
                    if selecting {Button("Усі"){selected=Set(filtered.map(\.id))}.disabled(store.busy)}
                }
            }
            .safeAreaInset(edge:.bottom) {bottomBar}
            .navigationDestination(for:UUID.self){id in DocumentView(documentID:id)}
            .sheet(isPresented:$handingOff){HandoffView(ids:selected)}
            .sheet(isPresented:$exporting){PDFExportSheet(ids:selected)}
            .sheet(item:$renaming){doc in NameSheet(documentID:doc.id)}
            .confirmationDialog("Видалити вибрані скани: \(selected.count)?",isPresented:$deleting,titleVisibility:.visible) {
                Button("Видалити скани",role:.destructive){store.deleteDocuments(selected);selected=[];selecting=false}
            } message:{Text("Скани зникнуть із бібліотеки застосунку. Раніше експортовані PDF залишаться у «Файлах».")}
            .onChange(of:store.documents.map(\.id)){_,ids in selected.formIntersection(Set(ids))}
            .alert("Не вдалося завершити дію",isPresented:Binding(get:{store.error != nil && !exporting},set:{if !$0{store.error=nil}})){Button("Зрозуміло"){store.error=nil}}message:{Text(store.error ?? "")}
        }
    }
    private func toggle(_ id:UUID) {if selected.contains(id){selected.remove(id)}else{selected.insert(id)}}
    private func row(_ doc:ScanDocument)->some View {
        HStack(spacing:12) {
            if selecting {Image(systemName:selected.contains(doc.id) ? "checkmark.circle.fill":"circle").font(.title3).foregroundStyle(Color.accent)}
            Thumb(file:doc.pages.first?.output).frame(width:52,height:70).clipShape(RoundedRectangle(cornerRadius:6))
            VStack(alignment:.leading,spacing:5) {
                Text(doc.title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Text("\(doc.pages.count) стор. · \(doc.created.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier:"uk_UA"))))")
                    .font(.caption).foregroundStyle(.secondary)
                if !doc.nameConfirmed && !doc.candidates.isEmpty {Text("ПІБ знайдено · перевірте назву").font(.caption2).foregroundStyle(Color.accent)}
            }
            Spacer(minLength:0)
            if !selecting {Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)}
        }.padding(.vertical,5).contentShape(Rectangle())
    }
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
                Button{path.append(store.newDocument())}label:{Label("Новий скан",systemImage:"plus").font(.headline).frame(maxWidth:.infinity,minHeight:44)}
                    .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius:16)).disabled(store.busy)
            }
        }.padding(.horizontal,20).padding(.vertical,8).background(Color.canvas.ignoresSafeArea(edges:.bottom))
    }
}
struct Thumb:View {
    let file:String?
    var body:some View {CachedScanThumbnail(file:file)}
}
struct DocumentView:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let documentID:UUID
    @State private var capturing=false
    @State private var importing=false
    @State private var sharing=false
    @State private var naming=false
    @State private var handoff=false
    @State private var styling=false
    @State private var originals=false
    @State private var deleting=false
    @State private var editMode:EditMode = .inactive
    var doc:ScanDocument? {store.document(documentID)}
    var body:some View {
        Group {
            if let doc {
                List {
                    Section {
                        VStack(alignment:.leading,spacing:10) {
                            Text(doc.title).font(.title2.weight(.bold))
                            HStack {Label("\(doc.pages.count) сторінок",systemImage:"doc.on.doc");Spacer();Button("Змінити назву"){naming=true}}.font(.caption)
                            if !doc.candidates.isEmpty && !doc.nameConfirmed {
                                Button {naming=true} label:{Label("Знайдено ПІБ · вибрати назву",systemImage:"person.text.rectangle")}.font(.subheadline)
                            }
                        }.padding(.vertical,12)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:0,leading:0,bottom:0,trailing:0))
                    if store.busy {
                        Section { HStack{ProgressView();Text(store.status).font(.subheadline)};Button("Зупинити після сторінки"){store.cancel()} }
                    }
                    if doc.pages.isEmpty {
                        Section {
                            VStack(spacing:14){Image(systemName:"viewfinder").font(.system(size:48,weight:.ultraLight)).foregroundStyle(Color.accent);Text("Додайте першу сторінку").font(.headline);Text("Камера зберігає кожну сторінку окремо. Кількість сторінок не обмежена налаштуваннями програми.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)}.frame(maxWidth:.infinity).padding(.vertical,32)
                        }
                    }
                    Section {
                        ForEach(Array(doc.pages.enumerated()),id:\.element.id) { n,leaf in
                            NavigationLink {PageBrowser(documentID:documentID,initialPageID:leaf.id)} label:{
                                HStack(spacing:16) {
                                    Thumb(file:leaf.output).frame(width:56,height:76).clipShape(RoundedRectangle(cornerRadius:9))
                                    VStack(alignment:.leading,spacing:8) {
                                        Text("Сторінка \(n+1)").font(.headline)
                                        if leaf.ocrReady && leaf.note.isEmpty {Label("Готова",systemImage:"checkmark.circle").font(.caption).foregroundStyle(Color.accent)}
                                        else{Text(leaf.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)}
                                        
                                    }
                                }.padding(.vertical,6)
                            }
                        }
                        .onDelete { offsets in for n in offsets {store.deletePage(documentID,doc.pages[n].id)} }
                        .onMove {store.movePages(documentID,from:$0,to:$1)}
                    } header: {if !doc.pages.isEmpty{Text("Сторінки")}}
                    if !doc.pages.isEmpty {
                        Section {
                            Button {styling=true} label:{Label("Стиль усіх сторінок",systemImage:"slider.horizontal.3")}.disabled(store.busy)
                            Button {Task{await store.analyze(documentID,force:true)}} label:{Label("Очистити, повернути та визначити ПІБ",systemImage:"wand.and.stars")}.disabled(store.busy)
                            Button {handoff=true} label:{Label("Підготувати завдання для ChatGPT",systemImage:"sparkles")}.disabled(store.busy)
                            Button {sharing=true} label:{Label("Зберегти або поділитися PDF",systemImage:"square.and.arrow.up")}.disabled(store.busy)
                        } footer:{Text("Назва за ПІБ — пропозиція з OCR. Якщо в документі кілька людей, виберіть потрібну. Перевірте краї й текст перед передачею.")}
                    }
                }
                .scrollContentBackground(.hidden).background(Color.canvas)
                .safeAreaInset(edge:.bottom) {
                    HStack(spacing:12) {
                        Button{importing=true}label:{Image(systemName:"square.and.arrow.down").font(.title3).frame(width:44,height:44)}.buttonStyle(.bordered)
                        Button{capturing=true}label:{Label(doc.pages.isEmpty ? "Сканувати" : "Додати сторінки",systemImage:"camera").font(.headline).frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(.borderedProminent)
                    }.padding(.horizontal,22).padding(.vertical,10).background(Color.canvas.ignoresSafeArea(edges:.bottom)).disabled(store.busy)
                }
            } else{ContentUnavailableView("Скан недоступний",systemImage:"doc")}
        }
        .task(id:documentID) {Task {await store.ensureEdgeProcessing(documentID)}}
        .onChange(of:store.busy) {_,busy in
            if !busy && store.error==nil && !store.status.hasPrefix("Зуп") {Task {await store.ensureEdgeProcessing(documentID)}}
        }
        .environment(\.editMode,$editMode)
        .navigationTitle("Документ").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing){
                Button(editMode == .active ? "Готово":"Порядок"){withAnimation{editMode = editMode == .active ? .inactive:.active}}.disabled(store.busy || (doc?.pages.isEmpty ?? true))
            }
            ToolbarItem(placement:.topBarTrailing){Button{sharing=true}label:{Image(systemName:"square.and.arrow.up")}.disabled(store.busy || (doc?.pages.isEmpty ?? true)).accessibilityLabel("Експорт і стиснення PDF")}
            ToolbarItem(placement:.topBarTrailing){Menu{Button("Експорт оригіналів фото"){originals=true};Button("Обробити краї всіх сторінок"){Task{await store.ensureEdgeProcessing(documentID,force:true)}};Button("Відновити з оригіналів і обробити заново"){Task{await store.rebuildSafely(documentID)}};Button("Повторити автоповорот усіх сторінок"){Task{await store.rotateAutomatically(documentID)}};Button("Видалити скан",role:.destructive){deleting=true}}label:{Image(systemName:"ellipsis.circle")}.disabled(store.busy)}
        }
        .fullScreenCover(isPresented:$capturing,onDismiss:{Task{await store.analyze(documentID)}}){CaptureView(documentID:documentID)}
        .fileImporter(isPresented:$importing,allowedContentTypes:[.pdf,.image],allowsMultipleSelection:true){result in
            switch result {
            case .success(let urls):Task{await store.importFiles(urls,to:documentID);await store.analyze(documentID)}
            case .failure(let error):store.error=error.localizedDescription
            }
        }
        .sheet(isPresented:$sharing){PDFExportSheet(ids:[documentID])}
        .sheet(isPresented:$naming){NameSheet(documentID:documentID)}
        .sheet(isPresented:$handoff){HandoffView(ids:[documentID])}
        .sheet(isPresented:$styling){DocumentStyleSheet(documentID:documentID)}
        .sheet(isPresented:$originals){OriginalsExportSheet(documentID:documentID)}
        .confirmationDialog("Видалити скан зі списку?",isPresented:$deleting,titleVisibility:.visible){Button("Видалити",role:.destructive){store.deleteDocument(documentID);dismiss()}}
    }
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
