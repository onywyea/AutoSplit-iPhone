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
    var body:some Scene { WindowGroup { LibraryView().environmentObject(store).tint(.accent) } }
}
struct LibraryView:View {
    @EnvironmentObject var store:ScannerStore
    @State private var path:[UUID]=[]
    @State private var search=""
    @State private var selecting=false
    @State private var selected:Set<UUID>=[]
    @State private var handingOff=false
    var filtered:[ScanDocument] { store.documents.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }
    var body:some View {
        NavigationStack(path:$path) {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:6) {
                            Text("SCANFLOW").font(.caption.weight(.bold)).tracking(3).foregroundStyle(Color.accent)
                            Text("Ваші скани").font(.system(size:34,weight:.bold,design:.rounded))
                            Text("Чисті сторінки. Один готовий PDF.").font(.subheadline).foregroundStyle(.secondary)
                        };Spacer()
                        Button(selecting ? "Готово" : "Вибрати") { selecting.toggle();selected=[] }.font(.subheadline.weight(.semibold)).disabled(store.busy)
                    }
                    HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("Знайти документ",text:$search) }
                        .padding(15).background(Color.card,in:RoundedRectangle(cornerRadius:16))
                    if filtered.isEmpty {
                        VStack(spacing:20) {
                            Image(systemName:"doc.viewfinder").font(.system(size:54,weight:.ultraLight)).foregroundStyle(Color.accent).padding(28).background(Color.accent.opacity(0.08),in:RoundedRectangle(cornerRadius:28))
                            Text("Перший скан — за кілька секунд").font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                            Text("Знімайте сторінки підряд. Кути, поворот і назву можна перевірити перед збереженням.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth:.infinity).padding(.vertical,50)
                    }
                    LazyVStack(spacing:12) {
                        ForEach(filtered) { doc in
                            Button {
                                if selecting { if selected.contains(doc.id){selected.remove(doc.id)}else{selected.insert(doc.id)} }
                                else{path.append(doc.id)}
                            } label: {
                                HStack(spacing:16) {
                                    Thumb(file:doc.pages.first?.output).frame(width:66,height:88).clipShape(RoundedRectangle(cornerRadius:10))
                                    VStack(alignment:.leading,spacing:8) {
                                        Text(doc.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                                        Text("\(doc.pages.count) стор. · \(doc.created.formatted(date:.abbreviated,time:.omitted))").font(.caption).foregroundStyle(.secondary)
                                        if !doc.nameConfirmed { Text(doc.candidates.isEmpty ? "Назву можна змінити" : "Знайдено ФІО — перевірте").font(.caption2).foregroundStyle(Color.accent) }
                                    };Spacer(minLength:0)
                                    Image(systemName:selecting ? (selected.contains(doc.id) ? "checkmark.circle.fill" : "circle") : "chevron.right").foregroundStyle(Color.accent)
                                }.padding(14).background(Color.card,in:RoundedRectangle(cornerRadius:22))
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(22)
            }.background(Color.canvas)
            .safeAreaInset(edge:.bottom) {
                VStack(spacing:0) {
                    if selecting {
                        Button { handingOff=true } label: {Label("Підготувати для ChatGPT · \(selected.count)",systemImage:"sparkles").frame(maxWidth:.infinity).padding(18)}.buttonStyle(.borderedProminent).disabled(selected.isEmpty || store.busy)
                    } else {
                        Button { path.append(store.newDocument()) } label: {Label("Новий скан",systemImage:"plus").font(.headline).frame(maxWidth:.infinity).padding(18)}.buttonStyle(.borderedProminent).disabled(store.busy)
                    }
                }.padding(.horizontal,22).padding(.bottom,10).background(Color.canvas.ignoresSafeArea(edges:.bottom))
            }
            .navigationDestination(for:UUID.self){id in DocumentView(documentID:id)}
            .toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$handingOff){HandoffView(ids:selected)}
            .alert("Не вдалося завершити дію",isPresented:Binding(get:{store.error != nil},set:{if !$0{store.error=nil}})){Button("Зрозуміло"){store.error=nil}}message:{Text(store.error ?? "")}
        }
    }
}
struct Thumb:View {
    let file:String?
    var body:some View {
        ZStack {
            Color.white
            if let file,let image=Disk.image(file,limit:300){Image(uiImage:image).resizable().scaledToFit()}
            else{Image(systemName:"doc.text").font(.title2).foregroundStyle(Color.accent.opacity(0.5))}
        }
    }
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
    @State private var deleting=false
    var doc:ScanDocument? {store.document(documentID)}
    var body:some View {
        Group {
            if let doc {
                List {
                    Section {
                        VStack(alignment:.leading,spacing:10) {
                            Text(doc.title).font(.system(size:28,weight:.bold,design:.rounded))
                            HStack {Label("\(doc.pages.count) сторінок",systemImage:"doc.on.doc");Spacer();Button("Змінити назву"){naming=true}}.font(.caption)
                            if !doc.candidates.isEmpty && !doc.nameConfirmed {
                                Button {naming=true} label:{Label("Знайдено ФІО · вибрати назву",systemImage:"person.text.rectangle")}.font(.subheadline)
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
                            NavigationLink {PageEditor(documentID:documentID,leaf:leaf)} label:{
                                HStack(spacing:16) {
                                    Thumb(file:leaf.output).frame(width:74,height:100).clipShape(RoundedRectangle(cornerRadius:9))
                                    VStack(alignment:.leading,spacing:8) {
                                        Text("Сторінка \(n+1)").font(.headline)
                                        if leaf.ocrReady && leaf.note.isEmpty {Label("Готова",systemImage:"checkmark.circle").font(.caption).foregroundStyle(Color.accent)}
                                        else{Text(leaf.note).font(.caption).foregroundStyle(.secondary).lineLimit(3)}
                                        Text("Кути · поворот · колір").font(.caption2).foregroundStyle(Color.accent)
                                    }
                                }.padding(.vertical,6)
                            }
                        }
                        .onDelete { offsets in for n in offsets {store.deletePage(documentID,doc.pages[n].id)} }
                        .onMove {store.movePages(documentID,from:$0,to:$1)}
                    } header: {if !doc.pages.isEmpty{Text("Сторінки")}}
                    if !doc.pages.isEmpty {
                        Section {
                            Button {Task{await store.analyze(documentID)}} label:{Label("Очистити, повернути та визначити ФІО",systemImage:"wand.and.stars")}.disabled(store.busy)
                            Button {handoff=true} label:{Label("Підготувати завдання для ChatGPT",systemImage:"sparkles")}.disabled(store.busy)
                            Button {Task{await store.export([documentID]);sharing = !store.shareURLs.isEmpty}} label:{Label("Зберегти або поділитися PDF",systemImage:"square.and.arrow.up")}.disabled(store.busy)
                        } footer:{Text("Назва за ФІО — пропозиція з OCR. Якщо в документі кілька людей, виберіть потрібну. Перевірте краї й текст перед передачею.")}
                    }
                }
                .scrollContentBackground(.hidden).background(Color.canvas)
                .safeAreaInset(edge:.bottom) {
                    HStack(spacing:12) {
                        Button{importing=true}label:{Image(systemName:"square.and.arrow.down").font(.title3).padding(17)}.buttonStyle(.bordered)
                        Button{capturing=true}label:{Label(doc.pages.isEmpty ? "Сканувати" : "Додати сторінки",systemImage:"camera").font(.headline).frame(maxWidth:.infinity).padding(16)}.buttonStyle(.borderedProminent)
                    }.padding(.horizontal,22).padding(.vertical,10).background(Color.canvas.ignoresSafeArea(edges:.bottom)).disabled(store.busy)
                }
            } else{ContentUnavailableView("Скан недоступний",systemImage:"doc")}
        }
        .navigationTitle("Скан").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing){EditButton().disabled(store.busy)}
            ToolbarItem(placement:.topBarTrailing){Menu{Button("Видалити скан",role:.destructive){deleting=true}}label:{Image(systemName:"ellipsis.circle")}.disabled(store.busy)}
        }
        .fullScreenCover(isPresented:$capturing,onDismiss:{Task{await store.analyze(documentID)}}){CaptureView(documentID:documentID)}
        .fileImporter(isPresented:$importing,allowedContentTypes:[.pdf,.image],allowsMultipleSelection:true){result in
            switch result {
            case .success(let urls):Task{await store.importFiles(urls,to:documentID);await store.analyze(documentID)}
            case .failure(let error):store.error=error.localizedDescription
            }
        }
        .sheet(isPresented:$sharing){ShareSheet(urls:store.shareURLs)}
        .sheet(isPresented:$naming){NameSheet(documentID:documentID)}
        .sheet(isPresented:$handoff){HandoffView(ids:[documentID])}
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
                } header:{Text("Знайдені імена")}footer:{Text("Програма не завжди розрізняє військовослужбовця, заявника й родичів. Відмінок ФІО автоматично не виправляється.")}
            }.navigationTitle("Назва документа").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}};ToolbarItem(placement:.confirmationAction){Button("Зберегти"){store.rename(documentID,name);dismiss()}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)}}
            .onAppear{name=store.document(documentID)?.title ?? ""}
        }
    }
}
