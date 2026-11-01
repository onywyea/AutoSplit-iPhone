import SwiftUI

struct PageEditor:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let documentID:UUID
    @State var leaf:Leaf
    var beginCrop=false
    @State private var didShowInitialCrop=false
    @State private var cropping=false
    @State private var textImage:UIImage?
    @State private var cleaning=false
    @State private var preview:UIImage?
    @State private var originalImage:UIImage?
    @State private var rendering=false
    @State private var refreshQueued=false
    @State private var generation=0
    @State private var showingOriginal=false
    var body:some View {
        ScrollView {
            VStack(spacing:20) {
                if let image=showingOriginal ? originalImage : preview {
                    Image(uiImage:image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:18)).padding(.horizontal)
                }
                if rendering {HStack{ProgressView();Text("Оновлення перегляду…").font(.caption).foregroundStyle(.secondary)}}
                HStack(spacing:28) {
                    tool("Кути","crop.rotate") { cropping=true }
                    tool("Повернути","rotate.right") { leaf.turns=(leaf.turns+1)%4;leaf.manualTurns=leaf.turns;refresh() }
                    tool(showingOriginal ? "Результат" : "Оригінал","square.on.square") { showingOriginal.toggle() }
                }
                Button {cleaning=true} label: {Label("Прибрати фон пензлем",systemImage:"eraser").font(.subheadline.weight(.medium))}
                Button {
                    textImage=preview
                } label: {Label("Виділити текст · Live Text",systemImage:"text.viewfinder").font(.subheadline.weight(.medium))}
                VStack(alignment:.leading,spacing:16) {
                    Text("Вигляд сторінки").font(.headline)
                    Picker("Обробка",selection:$leaf.finish) { ForEach(Finish.allCases,id:\.self){Text($0.rawValue).tag($0)} }.pickerStyle(.segmented)
                    Toggle("Автоматично очищати край",isOn:Binding(get:{leaf.edgeFill},set:{leaf.edgeFill=$0;leaf.edgeChoiceExplicit=true})).tint(.mint)
                    DisclosureGroup("Налаштування краю") {
                        VStack(alignment:.leading,spacing:12) {
                            Text("Зовнішній фон").font(.subheadline)
                            HStack {
                                Slider(value:Binding(get:{(leaf.edgeReach ?? 0.08)*100},set:{leaf.edgeReach=$0/100}),in:2...12,step:1,onEditingChanged:{active in if !active {refresh()}})
                                Text(String(format:"%.0f%%",(leaf.edgeReach ?? 0.08)*100)).font(.caption.monospacedDigit()).frame(width:38)
                            }
                            Text("Перехід усередину паперу").font(.subheadline)
                            HStack {
                                Slider(value:Binding(get:{(leaf.edgeOverlap ?? 0.06)*100},set:{leaf.edgeOverlap=$0/100}),in:2...12,step:0.5,onEditingChanged:{active in if !active {refresh()}})
                                Text(String(format:"%.1f%%",(leaf.edgeOverlap ?? 0.06)*100)).font(.caption.monospacedDigit()).frame(width:38)
                            }
                            Text("Зовнішня смуга визначає зону пошуку фону. Перехід заходить на папір і пом’якшує стик. Якщо фон не знайдено, уточніть кути або скористайтесь пензлем.").font(.caption).foregroundStyle(.secondary)
                        }.padding(.top,10).disabled(!leaf.edgeFill)
                    }
                    if !leaf.note.isEmpty { Label(leaf.note,systemImage:"info.circle").font(.caption).foregroundStyle(.secondary) }
                }.padding(20).background(Color.card,in:RoundedRectangle(cornerRadius:22)).padding(.horizontal)
                Button("Залишити весь кадр без обробки") {
                    leaf.quad = .full;leaf.manualCrop=true;leaf.cropVerified=true;leaf.turns=0;leaf.manualTurns=0;leaf.finish = .natural;leaf.edgeFill=false;leaf.edgeChoiceExplicit=true;leaf.cleanupStrokes=nil
                    preview=originalImage
                }.font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical)
        }
        .background(Color.canvas).navigationTitle("Сторінка").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
        .toolbar { ToolbarItem(placement:.topBarTrailing) {
            Button("Зберегти") { Task { await store.updatePage(documentID,leaf);if store.error == nil { dismiss() } } }.fontWeight(.semibold).disabled(store.busy || rendering)
        } }
        .task {
            async let source=ScanImageLoader.shared.image(leaf.original,limit:2400)
            async let result=ScanImageLoader.shared.image(leaf.output,limit:2400)
            originalImage=await source
            let loaded=await result
            if preview==nil {preview=loaded}
            if beginCrop && !didShowInitialCrop {didShowInitialCrop=true;cropping=true}
        }
        .onChange(of:leaf.finish){_,_ in refresh()}.onChange(of:leaf.edgeFill){_,_ in refresh()}
        .sheet(isPresented:$cropping) {
            CornerEditor(file:leaf.original,initial:leaf.quad ?? .full) { q in leaf.quad=q;leaf.manualCrop=true;leaf.cropVerified=true;refresh() }
        }
        .sheet(isPresented:$cleaning) {
            CleanupEditor(file:leaf.original,initial:leaf.cleanupStrokes ?? [],automatic:false,reference:leaf) { strokes in
                leaf.cleanupStrokes=strokes;refresh()
            }
        }
        .sheet(isPresented:Binding(get:{textImage != nil},set:{if !$0 {textImage=nil}})) {
            if let image=textImage {LiveTextSheet(image:image)}
        }
        .overlay { if store.busy { ProgressView().padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)) } }
    }
    func tool(_ title:String,_ icon:String,action:@escaping()->Void)->some View {
        Button(action:action){VStack(spacing:8){Image(systemName:icon).font(.title3);Text(title).font(.caption)}}.tint(.primary)
    }
    func refresh() {
        generation+=1
        guard !rendering else {refreshQueued=true;return}
        let item=leaf,version=generation
        rendering=true
        Task {
            do {
                let image=try await Task.detached(priority:.userInitiated) {try autoreleasepool{try Imaging.render(item)}}.value
                if generation==version {preview=image;showingOriginal=false}
            } catch {store.error=error.localizedDescription}
            rendering=false
            if refreshQueued {refreshQueued=false;refresh()}
        }
    }

}
struct CornerEditor:View {
    @Environment(\.dismiss) private var dismiss
    let file:String
    @State var quad:Quad
    @State private var image:UIImage?
    let done:(Quad)->Void
    init(file:String,initial:Quad,done:@escaping(Quad)->Void) { self.file=file;_quad=State(initialValue:initial);self.done=done }
    var body:some View {
        NavigationStack {
            VStack(spacing:20) {
                Text("Перетягніть чотири точки точно на кути аркуша").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                if let image {
                    GeometryReader { proxy in
                        let scale=min(proxy.size.width/image.size.width,proxy.size.height/image.size.height)
                        let size=CGSize(width:image.size.width*scale,height:image.size.height*scale)
                        let offset=CGPoint(x:(proxy.size.width-size.width)/2,y:(proxy.size.height-size.height)/2)
                        ZStack(alignment:.topLeading) {
                            Image(uiImage:image).resizable().frame(width:size.width,height:size.height).offset(x:offset.x,y:offset.y)
                            Path { path in
                                for i in 0..<4 {
                                    let p=CGPoint(x:offset.x+quad.points[i].x*size.width,y:offset.y+quad.points[i].y*size.height)
                                    if i==0 {path.move(to:p)} else{path.addLine(to:p)}
                                };path.closeSubpath()
                            }.fill(.mint.opacity(0.12))
                            Path { path in
                                for i in 0..<4 {
                                    let p=CGPoint(x:offset.x+quad.points[i].x*size.width,y:offset.y+quad.points[i].y*size.height)
                                    if i==0 {path.move(to:p)} else{path.addLine(to:p)}
                                };path.closeSubpath()
                            }.stroke(quad.valid ? Color.mint : .red,lineWidth:2)
                            ForEach(0..<4,id:\.self) { i in
                                Circle().fill(.white).frame(width:22,height:22).overlay(Circle().stroke(.mint,lineWidth:4)).frame(width:48,height:48).contentShape(Rectangle())
                                    .position(x:offset.x+quad.points[i].x*size.width,y:offset.y+quad.points[i].y*size.height)
                                    .gesture(DragGesture(coordinateSpace:.named("crop")).onChanged { value in
                                        quad.points[i]=Point(x:min(1,max(0,(value.location.x-offset.x)/size.width)),y:min(1,max(0,(value.location.y-offset.y)/size.height)))
                                    })
                            }
                        }.coordinateSpace(name:"crop")
                    }.padding(20)
                }
                if !quad.valid { Text("Кути не повинні перетинатися").foregroundStyle(.red).font(.caption) }
            }.task(id:file){image=await ScanImageLoader.shared.image(file,limit:2400)}.background(Color.canvas).navigationTitle("Обрізка").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button {dismiss()} label:{Image(systemName:"xmark")}.accessibilityLabel("Скасувати")}
                ToolbarItem(placement:.confirmationAction){Button {done(quad);dismiss()} label:{Image(systemName:"checkmark").fontWeight(.semibold)}.disabled(!quad.valid).accessibilityLabel("Застосувати межі")}
            }
        }
    }
}
