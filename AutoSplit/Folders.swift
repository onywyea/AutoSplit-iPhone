import SwiftUI
struct FolderShelf:View {
    @EnvironmentObject var store:ScannerStore
    @Binding var selection:String
    var manage:()->Void
    var body:some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                chip("Усі",id:"all");chip("Без папки",id:"unfiled")
                ForEach(store.folders) {folder in chip(folder.name,id:folder.id.uuidString)}
                Button(action:manage){Image(systemName:"folder.badge.gearshape").padding(12)}.accessibilityLabel("Керувати папками")
            }
        }
    }
    private func chip(_ name:String,id:String)->some View {
        Button {selection=id} label:{Text(name).font(.subheadline.weight(.medium)).padding(.horizontal,14).padding(.vertical,10).background(selection==id ? Color.accent.opacity(0.22):Color.secondary.opacity(0.10),in:Capsule())}.buttonStyle(.plain)
    }
}
struct FolderPicker:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let ids:Set<UUID>
    @State private var name=""
    var body:some View {
        NavigationStack {
            Form {
                Section("Перемістити скани: \(ids.count)") {
                    Button("Без папки"){move(nil)}
                    ForEach(store.folders) {folder in Button(folder.name){move(folder.id)}}
                }
                Section("Нова папка") {
                    TextField("Назва папки",text:$name)
                    Button("Створити та перемістити") {if let id=store.createFolder(name){move(id)}}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            }.navigationTitle("Папки").toolbar{ToolbarItem(placement:.confirmationAction){Button("Готово"){dismiss()}}}
        }
    }
    private func move(_ id:UUID?) {store.moveDocuments(ids,to:id);dismiss()}
}
struct FolderManager:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var editing:ScanFolder?
    @State private var deleting:ScanFolder?
    @State private var editName=""
    var body:some View {
        NavigationStack {
            Form {
                Section("Нова папка") {
                    TextField("Назва папки",text:$name)
                    Button("Створити") {if store.createFolder(name) != nil {name=""}}.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
                Section("Ваші папки") {
                    ForEach(store.folders) {folder in
                        HStack {
                            Label(folder.name,systemImage:"folder")
                            Spacer()
                            Menu {Button("Перейменувати"){editName=folder.name;editing=folder};Button("Видалити папку",role:.destructive){deleting=folder}} label:{Image(systemName:"ellipsis.circle")}
                        }
                    }
                }
            }.disabled(store.busy || store.savingPhotos>0)
                .navigationTitle("Папки").toolbar{ToolbarItem(placement:.confirmationAction){Button("Готово"){dismiss()}}}
                .alert("Перейменувати папку",isPresented:Binding(get:{editing != nil},set:{if !$0 {editing=nil}})) {
                    TextField("Назва",text:$editName)
                    Button("Зберегти"){if let id=editing?.id {store.renameFolder(id,editName)};editing=nil}
                    Button("Скасувати",role:.cancel){editing=nil}
                }
                .confirmationDialog("Видалити папку? Скани залишаться в «Без папки».",isPresented:Binding(get:{deleting != nil},set:{if !$0 {deleting=nil}}),titleVisibility:.visible) {
                    Button("Видалити папку",role:.destructive){if let id=deleting?.id {store.deleteFolder(id)};deleting=nil}
                }
        }
    }
}
