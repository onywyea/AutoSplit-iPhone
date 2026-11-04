import SwiftUI
struct NameSheet:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let documentID:UUID
    @State private var name=""
    @State private var suffix=""
    private var preview:String {ScanNaming.compose(name,suffix:suffix)}
    var body:some View {
        NavigationStack {
            Form {
                Section("Ім’я або власна назва") {TextField("Прізвище Ім’я По батькові",text:$name)}
                Section("Суфікс") {
                    TextField("ПКМУ168_мати",text:$suffix).textInputAutocapitalization(.never).autocorrectionDisabled()
                    HStack {Button("ПКМУ168"){suffix="ПКМУ168"};Spacer();Button("ПКМУ975"){suffix="ПКМУ975"};Spacer();Button("Без"){suffix=""}}.buttonStyle(.borderless)
                    Menu("Додати родинний зв’язок") {
                        ForEach(["мати","батько","дружина","чоловік","дочка","син","сестра","брат"],id:\.self) {relation in
                            Button(relation){suffix=ScanNaming.suffix(suffix)+"_"+relation}
                        }
                    }
                }
                Section("Назва файлу") {Text(preview+".pdf").font(.headline).textSelection(.enabled)}
                Section {
                    Button("Заново розпізнати ПІБ") {Task {await store.analyze(documentID,force:true);load()}}.disabled(store.busy)
                    if store.busy {ProgressView(store.status)}
                    ForEach(store.document(documentID)?.candidates ?? []) {candidate in
                        Button {name=candidate.name} label:{VStack(alignment:.leading){Text(candidate.name);Text(candidate.evidence).font(.caption).foregroundStyle(.secondary)}}
                    }
                } header:{Text("Знайдені імена")} footer:{Text("ПІБ скорочується до прізвища та ініціалів. Суфікс можна ввести довільно; частини з’єднуються підкресленням.")}
            }.navigationTitle("Назва документа").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}}
                    ToolbarItem(placement:.confirmationAction){Button("Зберегти"){store.rename(documentID,name,suffix:suffix);dismiss()}.disabled(preview.isEmpty || store.busy)}
                }.onAppear{load()}
        }
    }
    private func load() {
        guard let doc=store.document(documentID) else{return}
        suffix=doc.nameSuffix ?? ""
        name=doc.personName ?? doc.title
        let ending="_"+ScanNaming.suffix(suffix)
        if doc.personName==nil,!suffix.isEmpty,name.hasSuffix(ending) {name=String(name.dropLast(ending.count))}
    }
}
