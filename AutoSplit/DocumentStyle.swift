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
    @State private var appearance=Leaf(original:"",output:"")
    @State private var applying=false

    var body:some View {
        NavigationStack {
            Form {
                Section {
                    AppearanceControls(leaf:$appearance).disabled(applying)
                } header:{Text(pageIDs==nil ? "Весь документ":"Вибрані сторінки")} footer:{Text(pageIDs==nil ? "Стиль, різкість і очищення краю застосуються до всіх сторінок та нових фото. Кути, поворот і пензель кожної сторінки зберігаються.":"Стиль, різкість і край зміняться лише на вибраних сторінках.")}
                if let error=store.error {Section {Text(error).font(.caption).foregroundStyle(.red)}}
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
                                let completed=await store.applyAppearance(appearance,to:documentID,pageIDs:pageIDs)
                                applying=false
                                if completed {dismiss()}
                            }
                        }.disabled(store.busy || store.savingPhotos>0)
                    }
                }
            }.navigationTitle("Стиль PDF").navigationBarTitleDisplayMode(.inline)
            .toolbar {ToolbarItem(placement:.cancellationAction){Button("Закрити"){dismiss()}.disabled(applying)}}
            .interactiveDismissDisabled(applying)
            .onAppear {
                guard let doc=store.document(documentID) else {return}
                if let sample=doc.pages.first(where:{pageIDs?.contains($0.id) ?? true}) {appearance=sample}
                else {appearance.finish=doc.preferredFinish ?? .white;appearance.sharpness=doc.preferredSharpness;appearance.inkStrength=doc.preferredInkStrength;appearance.edgeFill=doc.preferredEdgeFill ?? true;appearance.edgeOverlap=doc.preferredEdgeOverlap;appearance.edgeReach=doc.preferredEdgeReach}
            }
        }
    }
}
