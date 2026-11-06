import SwiftUI
extension FolderColor {
    var color:Color {
        switch self {
        case .coral:return .orange
        case .amber:return .yellow
        case .green:return .green
        case .teal:return .teal
        case .blue:return .blue
        case .violet:return .purple
        case .pink:return .pink
        }
    }
    var title:String {
        switch self {
        case .coral:return "Кораловий"
        case .amber:return "Золотий"
        case .green:return "Зелений"
        case .teal:return "Бірюзовий"
        case .blue:return "Синій"
        case .violet:return "Фіолетовий"
        case .pink:return "Рожевий"
        }
    }
}
extension ScanFolder {var tint:FolderColor {FolderColor(rawValue:colorID ?? "") ?? .blue}}
struct FolderShelf:View {
    @Environment(\.scanTheme) private var theme
    @EnvironmentObject var store:ScannerStore
    @Binding var selection:String
    var manage:()->Void
    var body:some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                chip("Усі",id:"all",count:store.documents.count,tint:.accent,icon:"square.stack")
                chip("Без папки",id:"unfiled",count:store.folderCount(nil),tint:.secondary,icon:"tray")
                ForEach(store.folders) {folder in
                    chip(folder.name,id:folder.id.uuidString,count:store.folderCount(folder.id),tint:folder.tint.color,icon:"folder.fill")
                }
                Button(action:manage){Image(systemName:"folder.badge.gearshape").padding(12)}.accessibilityLabel("Керувати папками та кольорами")
            }
        }
    }
    private func chip(_ name:String,id:String,count:Int,tint:Color,icon:String)->some View {
        let active = selection == id
        let accent = theme == .system ? tint : Color.primary
        return Button {selection=id} label:{
            HStack(spacing:7) {
                Image(systemName:icon).foregroundStyle(accent)
                Text(name).lineLimit(1)
                Text("\(count)").font(.caption.bold().monospacedDigit()).padding(.horizontal,6).padding(.vertical,2).background(accent.opacity(0.10),in:Capsule())
            }.font(.subheadline.weight(.medium)).padding(.horizontal,12).padding(.vertical,10)
                .modifier(ScanFolderSurface(active: active, accent: accent))
        }.buttonStyle(.plain).accessibilityLabel("\(name), сканів: \(count)").accessibilityAddTraits(selection==id ? .isSelected:[])
    }
}
struct FolderPicker:View {
    @Environment(\.scanTheme) private var theme
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let request:ScanMoveRequest
    var onMoved:()->Void
    @State private var name=""
    @State private var destination:String?
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    DisclosureGroup("Вибрані скани: \(request.items.count)") {
                        ForEach(request.items) {item in
                            VStack(alignment:.leading,spacing:4) {
                                Text(item.title).font(.subheadline)
                                Text(sourceName(item.folderID)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("Перемістяться лише скани з цього списку.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Папка призначення") {
                    destinationRow("Без папки",key:"unfiled",count:store.folderCount(nil),color:.secondary)
                    ForEach(store.folders) {folder in
                        destinationRow(folder.name,key:folder.id.uuidString,count:store.folderCount(folder.id),color:theme == .monochrome ? .primary : folder.tint.color)
                    }
                }
                Section("Нова папка") {
                    TextField("Назва папки",text:$name)
                    Button("Створити папку") {
                        if let id=store.createFolder(name) {destination=id.uuidString;name=""}
                    }.disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }
            }.disabled(store.busy || store.savingPhotos>0)
                .navigationTitle("Перемістити скани").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge:.bottom) {
                    Button("Перемістити · \(request.items.count)",action:move)
                        .frame(maxWidth:.infinity,minHeight:44).scanPrimaryButton().padding()
                        .disabled(destination==nil || store.busy || store.savingPhotos>0)
                        .background(.ultraThinMaterial)
                }
                .toolbar {ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}}}
                .alert("Не вдалося перемістити",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})) {
                    Button("Зрозуміло"){store.error=nil}
                } message:{Text(store.error ?? "")}
        }
    }
    private func sourceName(_ id:UUID?)->String {store.folders.first{$0.id==id}?.name ?? "Без папки"}
    private func destinationRow(_ title:String,key:String,count:Int,color:Color)->some View {
        Button {destination=key} label:{
            HStack {
                Image(systemName:key=="unfiled" ? "tray":"folder.fill").foregroundStyle(color)
                Text(title).foregroundStyle(.primary)
                Spacer();Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                if destination==key {Image(systemName:"checkmark.circle.fill").foregroundStyle(color)}
            }
        }
    }
    private func move() {
        guard let destination else {return}
        let id:UUID?
        if destination=="unfiled" {id=nil}
        else {guard let parsed=UUID(uuidString:destination) else {return};id=parsed}
        if store.moveDocuments(request,to:id) {onMoved();dismiss()}
    }
}
struct FolderManager:View {
    @Environment(\.scanTheme) private var theme
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
                Section {
                    ForEach(store.folders) {folder in
                        HStack {
                            Image(systemName:"folder.fill").foregroundStyle(theme == .monochrome ? Color.primary : folder.tint.color)
                            VStack(alignment:.leading,spacing:3) {
                                Text(folder.name)
                                Text("Сканів: \(store.folderCount(folder.id))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Menu("Колір папки") {
                                    ForEach(FolderColor.allCases,id:\.self) {color in
                                        Button {store.setFolderColor(folder.id,color)} label:{
                                            Label(color.title,systemImage:folder.tint==color ? "checkmark.circle.fill":"circle.fill").foregroundStyle(color.color)
                                        }
                                    }
                                }
                                Button("Перейменувати"){editName=folder.name;editing=folder}
                                Button("Видалити папку",role:.destructive){deleting=folder}
                            } label:{Image(systemName:"ellipsis.circle")}
                        }
                    }
                } header:{Text("Ваші папки")} footer:{Text("Колір можна змінити через меню папки. Видалення папки не видаляє скани.")}
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
