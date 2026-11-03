import SwiftUI

extension Finish {
    var detail:String {
        switch self {
        case .white: return "Вирівнює освітлення й помірно підсилює тонкі штрихи. Не відновлює втрачений фокус."
        case .natural: return "Залишає кольори й освітлення оригіналу."
        case .clean: return "Легке підсилення контрасту й деталей тексту."
        case .mono: return "Чорно-білий вигляд для текстових сторінок."
        }
    }
}
struct DocumentStyleSheet:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let documentID:UUID
    var pageIDs:Set<UUID>?=nil
    private var targetCount:Int {store.document(documentID)?.pages.filter {pageIDs?.contains($0.id) ?? true}.count ?? 0}
    @State private var selected=Finish.white
    @State private var applying=false
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Finish.allCases,id:\.self) {style in
                        Button {selected=style} label:{
                            HStack(alignment:.top,spacing:12) {
                                VStack(alignment:.leading,spacing:5) {
                                    Text(style.rawValue).font(.headline).foregroundStyle(.primary)
                                    Text(style.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength:4)
                                Image(systemName:selected==style ? "checkmark.circle.fill":"circle").foregroundStyle(Color.accent)
                            }.padding(.vertical,5)
                        }.disabled(applying)
                    }
                } header:{Text(pageIDs==nil ? "Стиль усього документа":"Стиль вибраних сторінок")} footer:{Text(pageIDs==nil ? "Обробка з оригіналів. Нові сторінки отримають цей стиль.":"Зміняться лише вибрані сторінки. Стиль нових сторінок не змінюється.")}
                if applying {
                    Section {
                        HStack {ProgressView();Text(store.status)}
                        Button("Зупинити після сторінки"){store.cancel()}
                    }
                } else {
                    Section {
                        Button("Застосувати · \(targetCount) стор.") {
                            applying=true
                            Task {
                                let completed=await store.applyStyle(selected,to:documentID,pageIDs:pageIDs)
                                applying=false
                                if completed {dismiss()}
                            }
                        }.disabled(store.busy || store.savingPhotos>0)
                    }
                }
            }.navigationTitle("Стиль PDF").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction){Button("Закрити"){dismiss()}.disabled(applying)}}
            .interactiveDismissDisabled(applying)
            .onAppear {selected=store.document(documentID)?.preferredFinish ?? .white}
        }
    }
}
