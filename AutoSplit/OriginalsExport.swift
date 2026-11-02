import SwiftUI

struct OriginalsExportSheet:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let documentID:UUID
    var pageID:UUID?=nil
    @State private var allPages=false
    @State private var preparing=false
    @State private var sharing=false
    @State private var urls:[URL]=[]
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    if pageID != nil {
                        Toggle("Усі сторінки документа",isOn:$allPages).disabled(preparing)
                    }
                    Text(pageID==nil || allPages ? "Буде підготовлено всі збережені оригінали цього скану.":"Буде підготовлено оригінал відкритої сторінки.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } footer:{Text("Це фото, збережені до обробки ScanFlow. Вони вже могли бути зменшені та збережені в JPEG під час зйомки. Експорт копіює файли без повторного стиснення й фільтрів.")}
                Section {
                    Button {
                        preparing=true;urls=[]
                        Task {
                            urls=await store.exportOriginals(documentID,pageID:allPages ? nil:pageID)
                            preparing=false
                            if !urls.isEmpty {sharing=true}
                        }
                    } label:{
                        HStack {
                            if preparing {ProgressView()}
                            Label(preparing ? "Підготовка…":"Зберегти або поділитися оригіналами",systemImage:"square.and.arrow.up")
                        }
                    }.disabled(preparing || store.busy || store.savingPhotos>0)
                    if let error=store.error {Text(error).font(.footnote).foregroundStyle(.red)}
                }
            }.navigationTitle("Оригінали").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction){Button("Готово"){dismiss()}.disabled(preparing)}}
            .interactiveDismissDisabled(preparing)
            .sheet(isPresented:$sharing){ShareSheet(urls:urls)}
        }
    }
}
