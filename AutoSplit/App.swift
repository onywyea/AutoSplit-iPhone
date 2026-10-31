import SwiftUI
import VisionKit
import UniformTypeIdentifiers

@main
struct AutoSplitApp: App {
    @StateObject private var store = CaseStore()
    var body: some Scene { WindowGroup { MainView().environmentObject(store) } }
}
struct MainView: View {
    @EnvironmentObject var store: CaseStore
    @State private var scanner = false
    @State private var importer = false
    @State private var share = false
    @State private var reset = false
    @State private var regroup = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("ФІО військовослужбовця", text: $store.data.person)
                    TextField("Назва: Карпачов_РВ_ПКМУ168", text: $store.data.caseName)
                    TextField("Примітки / поля для заповнення", text: $store.data.notes, axis: .vertical)
                } header: { Text("Комплект") } footer: {
                    Text("Версія 0.1. ФІО та спорідненість заповнюються вручну. Дані зберігаються на пристрої.")
                }
                .disabled(store.busy)
                Section {
                    Button { scanner = true } label: { Label("Сканувати документи", systemImage: "doc.viewfinder") }
                        .disabled(store.busy || !VNDocumentCameraViewController.isSupported)
                    Button { importer = true } label: { Label("Імпорт PDF або фото", systemImage: "square.and.arrow.down") }.disabled(store.busy)
                    Button { Task { await store.analyze() } } label: { Label("Розпізнати та розділити", systemImage: "wand.and.stars") }
                        .disabled(store.busy || store.data.pages.isEmpty)
                    if store.busy {
                        HStack { ProgressView(); Text(store.status).font(.subheadline) }
                        Button("Зупинити", role: .cancel) { store.cancel() }
                    } else { Text(store.status).font(.footnote).foregroundStyle(.secondary) }
                }
                if !store.data.pages.isEmpty {
                    Section("Сторінки · \(store.data.pages.count)") {
                        NavigationLink { PagesView() } label: { Label("Переглянути та змінити межі", systemImage: "square.grid.2x2") }
                        Button("Побудувати розділи за поточними межами") { regroup = true }.disabled(store.busy)
                    }
                }
                if !store.data.sections.isEmpty {
                    Section("Розділи · \(store.data.sections.count)") {
                        ForEach(store.data.sections) { section in
                            NavigationLink { SectionEditor(sectionID: section.id) } label: {
                                HStack {
                                    Image(systemName: section.reviewed ? "checkmark.circle.fill" : "exclamationmark.circle")
                                        .foregroundStyle(section.reviewed ? .green : .orange)
                                    VStack(alignment: .leading) {
                                        Text(section.title)
                                        Text("\(section.pageIDs.count) стор. · \(section.relation)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Button { store.export(); if !store.exports.isEmpty { share = true } } label: {
                            Label("Експортувати PDF і TXT", systemImage: "square.and.arrow.up")
                        }.disabled(store.busy)
                    }
                }
                Section {
                    Button("Новий комплект", role: .destructive) { reset = true }.disabled(store.busy)
                } footer: {
                    Text("Перед експортом перевірте кожен розділ. Розпізнавання може помилятися. Оригінали сторінок зберігаються окремо від оброблених копій.")
                }
            }
            .navigationTitle("AutoSplit")
            .onChange(of: store.data.person) { _, _ in store.save() }
            .onChange(of: store.data.caseName) { _, _ in store.save() }
            .onChange(of: store.data.notes) { _, _ in store.save() }
            .sheet(isPresented: $scanner) {
                Scanner(completed: { store.add($0) }, failed: { store.error = $0 }).ignoresSafeArea()
            }
            .sheet(isPresented: $share) { ShareSheet(urls: store.exports) }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): Task { await store.importFiles(urls) }
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .alert("Помилка", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("Зрозуміло") { store.error = nil }
            } message: { Text(store.error ?? "") }
            .confirmationDialog("Почати новий комплект? Спочатку експортуйте поточний. Поточна розмітка буде замінена.", isPresented: $reset, titleVisibility: .visible) {
                Button("Новий комплект", role: .destructive) { store.data = CaseData(); store.exports = []; store.save() }
            }
            .confirmationDialog("Побудова розділів скине їхні назви, отримувачів і підтвердження. Продовжити?", isPresented: $regroup, titleVisibility: .visible) {
                Button("Побудувати розділи", role: .destructive) { store.regroup() }
            }
        }
    }
}
struct PagesView: View {
    @EnvironmentObject var store: CaseStore
    @State private var pendingBoundary: UUID?
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                ForEach(Array(store.data.pages.enumerated()), id: \.element.id) { index, page in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Сторінка \(index + 1) · \(page.kind)").font(.headline)
                        PageImage(page: page)
                        if let warning = page.warning, !warning.isEmpty { Text(warning).font(.caption).foregroundStyle(.orange) }
                        Toggle("Початок нового документа", isOn: Binding(get: { page.starts }, set: { _ in pendingBoundary = page.id }))
                        HStack {
                            Button { store.rotate(page.id) } label: { Image(systemName: "rotate.right") }.accessibilityLabel("Повернути")
                            Button { store.move(page.id, offset: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                            Button { store.move(page.id, offset: 1) } label: { Image(systemName: "arrow.down") }.disabled(index + 1 == store.data.pages.count)
                            Spacer()
                            Menu {
                                Button("Відновити оригінал") { store.restore(page.id) }
                                Button("Видалити сторінку", role: .destructive) { store.remove(page.id) }
                            } label: { Image(systemName: "ellipsis.circle") }
                        }.buttonStyle(.bordered)
                        NavigationLink("Розпізнаний текст") { TextEditorView(pageID: page.id) }
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }.padding().disabled(store.busy)
        }
        .navigationTitle("Сторінки")
        .confirmationDialog("Зміна межі перебудує всі розділи та скине їхні назви й підтвердження.", isPresented: Binding(get: { pendingBoundary != nil }, set: { if !$0 { pendingBoundary = nil } }), titleVisibility: .visible) {
            Button("Змінити межу", role: .destructive) { if let id = pendingBoundary { store.toggleStart(id) }; pendingBoundary = nil }
        }
    }
}
struct PageImage: View {
    let page: ScanPage
    var body: some View {
        if let image = Storage.image(page) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).background(.white).clipShape(RoundedRectangle(cornerRadius: 8))
        } else { Label("Зображення відсутнє", systemImage: "exclamationmark.triangle") }
    }
}
struct SectionEditor: View {
    @EnvironmentObject var store: CaseStore
    let sectionID: UUID
    var body: some View {
        if let index = store.data.sections.firstIndex(where: { $0.id == sectionID }) {
            Form {
                Section("Назва та отримувач") {
                    TextField("Тип документа / назва", text: $store.data.sections[index].title)
                    Menu("Вибрати тип документа") {
                        ForEach(Rules.types, id: \.self) { kind in
                            Button(kind) { store.data.sections[index].title = kind; store.data.sections[index].reviewed = false; store.save() }
                        }
                    }
                    TextField("ФІО отримувача реквізитів", text: $store.data.sections[index].recipient)
                    TextField("мати / батько / дружина / дочка_Аліна", text: $store.data.sections[index].relation)
                }
                Section("Усі сторінки розділу") {
                    ForEach(store.data.sections[index].pageIDs, id: \.self) { id in
                        if let page = store.data.pages.first(where: { $0.id == id }) {
                            PageImage(page: page)
                            if let warning = page.warning, !warning.isEmpty { Text(warning).font(.caption).foregroundStyle(.orange) }
                            NavigationLink("Текст сторінки") { TextEditorView(pageID: page.id) }
                        }
                    }
                }
                Section {
                    Toggle("Межі, назву та сторінки перевірено", isOn: $store.data.sections[index].reviewed)
                } footer: { Text("Якщо паспорт і РНОКПП на одному аркуші, ця версія ще не розділяє їх на фрагменти.") }
            }
            .disabled(store.busy)
            .navigationTitle("Перевірка розділу")
            .onDisappear { store.save() }
            .onChange(of: store.data.sections[index].title) { _, _ in store.data.sections[index].reviewed = false; store.save() }
            .onChange(of: store.data.sections[index].recipient) { _, _ in store.data.sections[index].reviewed = false; store.save() }
            .onChange(of: store.data.sections[index].relation) { _, _ in store.data.sections[index].reviewed = false; store.save() }
        } else { ContentUnavailableView("Розділ перебудовано", systemImage: "doc") }
    }
}
struct TextEditorView: View {
    @EnvironmentObject var store: CaseStore
    let pageID: UUID
    var body: some View {
        if let index = store.data.pages.firstIndex(where: { $0.id == pageID }) {
            VStack(alignment: .leading) {
                Text("Виправлення тут впливають на TXT та IBAN. Для зміни меж скористайтесь списком сторінок.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                TextEditor(text: $store.data.pages[index].text).padding()
            }
            .navigationTitle("Розпізнаний текст").disabled(store.busy)
            .onDisappear { store.save() }
            .onChange(of: store.data.pages[index].text) { _, _ in
                for s in store.data.sections.indices where store.data.sections[s].pageIDs.contains(pageID) { store.data.sections[s].reviewed = false }
            }
        }
    }
}
