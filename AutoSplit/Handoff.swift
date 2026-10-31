import SwiftUI

struct HandoffView:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let ids:Set<UUID>
    @State private var selected:Set<String>=["Розділити комплект"]
    @State private var extra=""
    @State private var share=false
    @State private var copied=false
    let actions=["Розділити комплект","Назвати за загиблим і спорідненістю","Витягти банківські реквізити","Створити TXT з даними","Перевірити поворот і краї"]
    var task:String {
        let rules:[String:String]=[
            "Розділити комплект":"Розділи комплекти на окремі багатосторінкові PDF за типом документа. Паспорт з витягом з реєстру територіальної громади зберігай разом, РНОКПП — окремо. Протокол ВЛК/РВЛК і свідоцтво про хворобу зберігай окремо; згадка свідоцтва всередині протоколу не є початком іншого документа. Кожен витяг з рішення експертної команди — окремий PDF. Не вважай згадки документів у заяві окремими заголовками.",
            "Назвати за загиблим і спорідненістю":"Визнач ФІО загиблого військовослужбовця. Для комплекту зі свідоцтвом про смерть використай Прізвище_ІП_ПКМУ168; для заяв родичів додай мати, батько, дружина, дочка_Ім'я або син_Ім'я за змістом. Створи папку з повним ФІО військовослужбовця.",
            "Витягти банківські реквізити":"Витягни всі банківські реквізити родичів, які звернулися за ОГД, у TXT. Для кожного вкажи ФІО отримувача, спорідненість, IBAN і наявні поля банку/РНОКПП. Не приписуй реквізити іншій людині. Нерозбірливі значення познач для перевірки, не вигадуй цифри.",
            "Створити TXT з даними":"Створи TXT з основними даними, які чітко підтверджуються документами, та окремим переліком нерозбірливих або відсутніх полів.",
            "Перевірити поворот і краї":"Перевір напрям тексту, оберни бокові й перевернуті сторінки. Прибери видимий стіл за межами аркуша без втрати тексту, печаток і підписів. Не відновлюй вигаданий вміст документа."
        ]
        let instructions=actions.filter{selected.contains($0)}.compactMap{rules[$0]}.joined(separator:"\n\n")
        return "Оброби прикріплені скани.\n\n"+instructions+"\n\nДодатково: "+extra+"\n\nЗбережи результати у файли. Невизначені ФІО, межі й реквізити познач явно."
    }
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    Label("Вибрано сканів: \(ids.count)",systemImage:"doc.on.doc")
                    Text("Програма готує PDF і текст завдання. Надсилання в чат виконуєте ви — файли не передаються автоматично.").font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Що зробити з документами") {
                    ForEach(actions,id:\.self) { action in
                        Toggle(action,isOn:Binding(get:{selected.contains(action)},set:{if $0{selected.insert(action)}else{selected.remove(action)}}))
                    }
                    TextField("Додаткові побажання",text:$extra,axis:.vertical).lineLimit(3...6)
                }
                Section {
                    Button{UIPasteboard.general.string=task;copied=true}label:{Label(copied ? "Завдання скопійовано" : "Копіювати завдання",systemImage:copied ? "checkmark" : "doc.on.clipboard")}
                    Button{Task{await store.export(ids,task:task);share = !store.shareURLs.isEmpty}}label:{Label("Підготувати й поділитися файлами",systemImage:"square.and.arrow.up")}.disabled(store.busy || selected.isEmpty)
                    Button{openURL(URL(string:"https://chatgpt.com")!)}label:{Label("Відкрити ChatGPT",systemImage:"arrow.up.forward.app")}
                    if store.busy {HStack{ProgressView();Text(store.status)}}
                } footer:{Text("У меню «Поділитися» виберіть ChatGPT, якщо він доступний. Інакше збережіть PDF у «Файли», відкрийте потрібний чат, прикріпіть PDF і вставте скопійоване завдання. Великий комплект може потребувати кількох повідомлень через обмеження чату.")}
            }.navigationTitle("Для ChatGPT").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.confirmationAction){Button("Готово"){dismiss()}}}
            .sheet(isPresented:$share){ShareSheet(urls:store.shareURLs)}
        }
    }
}
