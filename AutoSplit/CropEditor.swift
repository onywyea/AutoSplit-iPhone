import SwiftUI

struct PageEditor:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let documentID:UUID
    @State var leaf:Leaf
    @State private var cropping=false
    @State private var preview:UIImage?
    @State private var showingOriginal=false
    var body:some View {
        ScrollView {
            VStack(spacing:20) {
                if let image=showingOriginal ? Disk.image(leaf.original) : (preview ?? Disk.image(leaf.output)) {
                    Image(uiImage:image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:18)).padding(.horizontal)
                }
                HStack(spacing:28) {
                    tool("Кути","crop.rotate") { cropping=true }
                    tool("Повернути","rotate.right") { leaf.turns=(leaf.turns+1)%4;refresh() }
                    tool(showingOriginal ? "Результат" : "Оригінал","square.on.square") { showingOriginal.toggle() }
                }
                VStack(alignment:.leading,spacing:16) {
                    Text("Вигляд сторінки").font(.headline)
                    Picker("Обробка",selection:$leaf.finish) { ForEach(Finish.allCases,id:\.self){Text($0.rawValue).tag($0)} }.pickerStyle(.segmented)
                    Toggle("Прибрати залишки фону по краю",isOn:$leaf.edgeFill).tint(.mint)
                    Text("Заповнюється лише вузький край кольором паперу. Перевірте позначки біля країв; оригінал збережено.").font(.caption).foregroundStyle(.secondary)
                    if !leaf.note.isEmpty { Label(leaf.note,systemImage:"info.circle").font(.caption).foregroundStyle(.secondary) }
                }.padding(20).background(Color.card,in:RoundedRectangle(cornerRadius:22)).padding(.horizontal)
                Button("Повернути оригінальний вигляд") {
                    leaf.quad=nil;leaf.turns=0;leaf.finish = .natural;leaf.edgeFill=false
                    preview=Disk.image(leaf.original)
                }.font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical)
        }
        .background(Color.canvas).navigationTitle("Сторінка").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
        .toolbar { ToolbarItem(placement:.topBarTrailing) {
            Button("Зберегти") { Task { await store.updatePage(documentID,leaf);if store.error == nil { dismiss() } } }.fontWeight(.semibold).disabled(store.busy)
        } }
        .onChange(of:leaf.finish){_,_ in refresh()}.onChange(of:leaf.edgeFill){_,_ in refresh()}
        .sheet(isPresented:$cropping) {
            CornerEditor(file:leaf.original,initial:leaf.quad ?? .full) { q in leaf.quad=q;refresh() }
        }
        .overlay { if store.busy { ProgressView().padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)) } }
    }
    func tool(_ title:String,_ icon:String,action:@escaping()->Void)->some View {
        Button(action:action){VStack(spacing:8){Image(systemName:icon).font(.title3);Text(title).font(.caption)}}.tint(.primary)
    }
    func refresh() {
        let item=leaf
        Task {
            do {
                let image=try await Task.detached { try Imaging.render(item) }.value
                if leaf.quad==item.quad && leaf.turns==item.turns && leaf.finish==item.finish && leaf.edgeFill==item.edgeFill { preview=image;showingOriginal=false }
            } catch { store.error=error.localizedDescription }
        }
    }
}
struct CornerEditor:View {
    @Environment(\.dismiss) private var dismiss
    let file:String
    @State var quad:Quad
    let done:(Quad)->Void
    init(file:String,initial:Quad,done:@escaping(Quad)->Void) { self.file=file;_quad=State(initialValue:initial);self.done=done }
    var body:some View {
        NavigationStack {
            VStack(spacing:20) {
                Text("Перетягніть чотири точки точно на кути аркуша").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                if let image=Disk.image(file) {
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
            }.background(Color.canvas).navigationTitle("Межі аркуша").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Скасувати"){dismiss()}}
                ToolbarItem(placement:.confirmationAction){Button("Застосувати"){done(quad);dismiss()}.disabled(!quad.valid)}
            }
        }
    }
}
