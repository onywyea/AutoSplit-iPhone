import SwiftUI

struct HandoffView: View {
    @EnvironmentObject var store: ScannerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let ids: Set<UUID>
    let batchName: String?
    @State private var command: ChatGPTCommand
    @State private var compression: PDFCompression = .balanced
    @State private var archive = true
    @State private var extra = ""
    @State private var share = false
    @State private var copied = false

    init(ids: Set<UUID>, batchName: String? = nil) {
        self.ids = ids
        self.batchName = batchName
        _command = State(initialValue: batchName?.lowercased() == "загиблі" ? .bankDetails : .package975)
    }

    var task: String {
        var text = command.rawValue + "\n\n" + command.instructions
        if let batchName { text += "\n\nПапка джерела: " + batchName }
        let note = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { text += "\n\nДодатково: " + note }
        return text
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let batchName { Label(batchName, systemImage: "folder") }
                    Label("Сканів: \(ids.count)", systemImage: "doc.on.doc")
                    Picker("Команда", selection: $command) {
                        ForEach(ChatGPTCommand.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Додаткові побажання", text: $extra, axis: .vertical).lineLimit(2...5)
                }.disabled(store.busy)
                Section {
                    Picker("Якість PDF", selection: $compression) {
                        ForEach(PDFCompression.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Запакувати в ZIP", isOn: $archive)
                } footer: {
                    Text("ZIP містить PDF і TXT команди. Великі пакети діляться на ZIP до 100 МБ. Для обробки прикріпіть усі частини та актуальний Excel, якщо він потрібен для команди.")
                }.disabled(store.busy)
                Section {
                    Button {
                        UIPasteboard.general.string = task
                        copied = true
                    } label: {
                        Label(copied ? "Завдання скопійовано" : "Копіювати завдання", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        Task {
                            await store.export(ids, task: task, compression: compression, archive: archive, batchName: batchName)
                            share = !store.shareURLs.isEmpty
                        }
                    } label: {
                        Label("Підготувати й поділитися", systemImage: "square.and.arrow.up")
                    }.disabled(store.busy || ids.isEmpty)
                    Button {
                        if let url = URL(string: "https://chatgpt.com") { openURL(url) }
                    } label: { Label("Відкрити ChatGPT", systemImage: "arrow.up.forward.app") }
                    if store.busy { HStack { ProgressView(); Text(store.status) } }
                    if !store.shareURLs.isEmpty {
                        Button("Поділитися готовими файлами") { share = true }.disabled(store.busy)
                    }
                    if let error = store.error { Text(error).font(.footnote).foregroundStyle(.red) }
                } footer: {
                    Text("Файли зберігаються в Exports. Відкрийте потрібний чат, прикріпіть ZIP або PDF і вставте команду.")
                }
            }
            .navigationTitle("Для ChatGPT").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() }.disabled(store.busy) } }
            .sheet(isPresented: $share) { ShareSheet(urls: store.shareURLs) }
            .onAppear { store.shareURLs = []; store.error = nil }
            .onChange(of: command) { _, _ in copied = false; store.shareURLs = [] }
            .onChange(of: extra) { _, _ in copied = false; store.shareURLs = [] }
            .onChange(of: archive) { _, _ in store.shareURLs = [] }
            .onChange(of: compression) { _, _ in store.shareURLs = [] }
            .interactiveDismissDisabled(store.busy)
        }
    }
}
