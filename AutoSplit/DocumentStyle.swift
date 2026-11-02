import SwiftUI

extension Finish {
    var detail:String {
        switch self {
        case .white: return "Освітлює папір і тіні, зберігає кольорові печатки. Стандартний стиль нових фото."
        case .natural: return "Залишає кольори й освітлення оригіналу."
        case .clean: return "Легке підсилення контрасту."
        case .mono: return "Чорно-білий вигляд для текстових сторінок."
        }
    }
}
struct DocumentStyleSheet:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let documentID:UUID
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
                } header:{Text("Стиль усього документа")} footer:{Text("Обробка виконується з оригіналів. Межі, ручний поворот і порядок сторінок зберігаються. Нові сторінки цього документа отримають вибраний стиль.")}
                if applying {
                    Section {
                        HStack {ProgressView();Text(store.status)}
                        Button("Зупинити після сторінки"){store.cancel()}
                    }
                } else {
                    Section {
                        Button("Застосувати до всіх сторінок · \(store.document(documentID)?.pages.count ?? 0)") {
                            applying=true
                            Task {
                                let completed=await store.applyStyle(selected,to:documentID)
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
