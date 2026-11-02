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
        store.documents.first(where:{$0.id.uuidString==lastDocument && !$0.pages.isEmpty}) ?? store.documents.first(where:{!$0.pages.isEmpty && $0.pages.contains(where:{$0.reviewReason != nil})})
    }
    var filtered:[ScanDocument] {store.documents.filter{search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)}}
    var body:some View {
        NavigationStack(path:$path) {
            List {
                if !selecting && search.isEmpty {
                    Section {
                        HStack(spacing:12) {ScanMark();VStack(alignment:.leading,spacing:3) {Text("ScanFlow").font(.headline);Text("Скануйте серією. Перевіряйте вибірково.").font(.caption).foregroundStyle(.secondary)}}.padding(.vertical,4)
                    }.listRowBackground(Color.clear)
                    if let doc=resume {
                        Section("Продовжити комплект") {
                            Button {path.append(doc.id)} label:{
                                VStack(alignment:.leading,spacing:9) {
                                    Text(doc.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                    Text("\(doc.pages.count) стор. · \(doc.pages.filter {$0.reviewReason != nil}.count) до перевірки").font(.caption).foregroundStyle(.secondary)
                                    Label("Продовжити перевірку",systemImage:"arrow.right.circle.fill").font(.subheadline.weight(.semibold))
                                }.padding(.vertical,6)
                            }.disabled(store.busy)
                        }
                    }
                }
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
            .navigationTitle("Документи")
            .searchable(text:$search,prompt:"ПІБ або назва документа")
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button(selecting ? "Готово":"Вибрати"){selecting.toggle();selected=[]}.disabled(store.busy || store.documents.isEmpty)
                }
                ToolbarItem(placement:.topBarLeading) {
                    if selecting {Button("Усі"){selected=Set(filtered.map(\.id))}.disabled(store.busy)}
                }
            }
            .safeAreaInset(edge:.bottom) {bottomBar}
            .navigationDestination(for:UUID.self){id in DocumentView(documentID:id,startCamera:newCapture==id)}
            .onChange(of:path){_,ids in if let id=ids.last {lastDocument=id.uuidString}else{newCapture=nil}}
            .fileImporter(isPresented:$importing,allowedContentTypes:[.pdf,.image],allowsMultipleSelection:true) {result in
                switch result {
                case .success(let urls):
                    guard !urls.isEmpty else {return}
                    let id=store.newDocument();path.append(id)
                    Task {await store.importFiles(urls,to:id);await store.analyze(id)}
                case .failure(let error):store.error=error.localizedDescription
                }
            }
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
