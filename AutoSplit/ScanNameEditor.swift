import SwiftUI
struct NameSheet:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let documentID:UUID
    @State private var name=""
    @State private var suffix=""
    @State private var relation=""
    @State private var childName=""
    @FocusState private var childFocused:Bool
    private var parts:NameSuffixParts {NameSuffixParts(base:suffix,relation:relation,childName:childName)}
    private var preview:String {ScanNaming.compose(name,suffix:parts.value)}
    private var relationBinding:Binding<String> {
        Binding(get:{relation},set:{value in
            if relation != value {childName=""}
            relation=value
            if NameSuffixParts.isChild(value) {DispatchQueue.main.async {childFocused=true}}
        })
    }
    var body:some View {
        NavigationStack {
            Form {
                personSection
                suffixSection
                Section("Назва файлу") {
                    Text(preview.isEmpty ? "Вкажіть ПІБ або назву":preview+".pdf").font(.headline).textSelection(.enabled)
                }
                candidatesSection
            }.navigationTitle("Назва PDF").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}}
                    ToolbarItem(placement:.confirmationAction){Button("Зберегти"){store.rename(documentID,name,suffix:parts.value);dismiss()}.disabled(preview.isEmpty || store.busy)}
                }.onAppear{load()}
        }
    }
    private var personSection:some View {
        Section {
            TextField("Прізвище Ім’я По батькові",text:$name).textInputAutocapitalization(.words).autocorrectionDisabled()
            if let suggestion=store.nameSuggestion(for:documentID) {
                Button {name=suggestion.name} label:{
                    VStack(alignment:.leading,spacing:6) {
                        Label("Використати ПІБ з попереднього скану",systemImage:"arrow.uturn.backward")
                        Text(suggestion.name).font(.headline).foregroundStyle(.primary)
                        Text(suggestion.sourceTitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }.padding(.vertical,4)
                }
            }
        } header:{Text("ПІБ військовослужбовця або власна назва")}
          footer:{Text("ПІБ з минулого пакета додається лише після натискання. Воно може відрізнятися від імен у документах родичів.")}
    }
    private var suffixSection:some View {
        Section {
            TextField("ПКМУ168 або власний суфікс",text:$suffix).textInputAutocapitalization(.never).autocorrectionDisabled()
            HStack {
                Button("ПКМУ168"){suffix="ПКМУ168"}
                Spacer();Button("ПКМУ975"){suffix="ПКМУ975"}
                Spacer();Button("Без"){suffix="";relation="";childName=""}
            }.buttonStyle(.borderless)
            Picker("Родинний зв’язок",selection:relationBinding) {
                Text("Не додавати").tag("")
                ForEach(NameSuffixParts.relations,id:\.self){value in Text(value).tag(value)}
            }.pickerStyle(.menu)
            if NameSuffixParts.isChild(relation) {
                TextField("Ім’я дитини",text:$childName).textInputAutocapitalization(.words).autocorrectionDisabled().focused($childFocused)
            } else if !childName.isEmpty {
                // Preserve a previously typed custom trailing component.
                TextField("Додаток до суфікса",text:$childName).autocorrectionDisabled()
            }
        } header:{Text("Суфікс і родинний зв’язок")}
          footer:{Text("Приклад: Прізвище_ІП_ПКМУ168_дочка_Аліна. Підкреслення додаються автоматично.")}
    }
    private var candidatesSection:some View {
        Section {
            Button("Заново розпізнати ПІБ") {Task {await store.analyze(documentID,force:true);load()}}.disabled(store.busy)
            if store.busy {ProgressView(store.status)}
            ForEach(store.document(documentID)?.candidates ?? []) {candidate in
                Button {name=candidate.name} label:{
                    VStack(alignment:.leading){Text(candidate.name);Text(candidate.evidence).font(.caption).foregroundStyle(.secondary)}
                }
            }
        } header:{Text("Імена, знайдені в цьому скані")}
          footer:{Text("Для назви пакета виберіть військовослужбовця. Ім’я дитини вводиться окремо в суфіксі.")}
    }
    private func load() {
        guard let doc=store.document(documentID) else{return}
        let parsed=NameSuffixParts.parse(doc.nameSuffix ?? "")
        suffix=parsed.base;relation=parsed.relation;childName=parsed.childName
        name=doc.personName ?? doc.title
        let ending="_"+ScanNaming.suffix(doc.nameSuffix ?? "")
        if doc.personName==nil,!(doc.nameSuffix ?? "").isEmpty,name.hasSuffix(ending) {name=String(name.dropLast(ending.count))}
        if name=="Новий скан" {name=""}
    }
}
