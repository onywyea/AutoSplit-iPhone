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
    @State private var previewStatus=""
    @State private var previewDebounce:Task<Void,Never>?
    @State private var showingOriginal=false
    @State private var dirty=false
    var body:some View {
        ScrollView {
            VStack(spacing:20) {
                if let image=showingOriginal ? originalImage : preview {
                    Image(uiImage:image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius:18)).padding(.horizontal)
                }
                if rendering {HStack{ProgressView();Text("Оновлення перегляду…").font(.caption).foregroundStyle(.secondary)}}
                else {Label(dirty ? "Є незбережені зміни":"Зміни зберігаються автоматично",systemImage:dirty ? "clock":"checkmark.circle").font(.caption).foregroundStyle(.secondary)}
                HStack(spacing:28) {
                    tool("Кути","crop.rotate") { cropping=true }
                    tool("Повернути","rotate.right") { leaf.turns=(leaf.turns+1)%4;leaf.manualTurns=leaf.turns;dirty=true;refresh() }
                    tool(showingOriginal ? "Результат" : "Оригінал","square.on.square") { showingOriginal.toggle() }
                }
                Button {cleaning=true} label: {Label("Прибрати фон пензлем",systemImage:"eraser").font(.subheadline.weight(.medium))}
                Button {
                    textImage=preview
                } label: {Label("Виділити текст · Live Text",systemImage:"text.viewfinder").font(.subheadline.weight(.medium))}
                VStack(alignment:.leading,spacing:16) {
                    Text("Ця сторінка").font(.headline)
                    AppearanceControls(leaf:$leaf)
                    Text("Зміни тут застосовуються лише до відкритої сторінки.").font(.caption).foregroundStyle(.secondary)
                    Button {
                        let appearance=leaf
                        Task {
                            if await store.applyAppearance(appearance,to:documentID) {dirty=false;previewStatus="Налаштування застосовано до всього документа та нових сторінок"}
                        }
                    } label:{Label("Застосувати вигляд і край до всього скану",systemImage:"doc.on.doc")}.disabled(dirty || rendering || store.busy)
                    if !leaf.edgeFill {Label("Очищення вимкнено. Увімкніть перемикач, щоб змінювати край.",systemImage:"info.circle").font(.caption).foregroundStyle(.secondary)}
                    else if !previewStatus.isEmpty {Label(previewStatus,systemImage:"info.circle").font(.caption).foregroundStyle(.secondary)}
                }.padding(20).background(Color.card,in:RoundedRectangle(cornerRadius:22)).padding(.horizontal)
                Button("Залишити весь кадр без обробки") {
                    leaf.quad = .full;leaf.manualCrop=true;leaf.cropVerified=true;leaf.turns=0;leaf.manualTurns=0;leaf.finish = .natural;leaf.edgeFill=false;leaf.edgeChoiceExplicit=true;leaf.cleanupStrokes=nil
                    leaf.sharpness=0;dirty=true;refresh()
                }.font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical)
        }
        .background(Color.canvas).navigationTitle("Сторінка").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
        .toolbar { ToolbarItem(placement:.topBarTrailing) {
            Button("Готово") { Task {if dirty {await store.updatePage(documentID,leaf)};if store.error == nil {dismiss()}} }.fontWeight(.semibold).disabled(store.busy || rendering)
        } }
        .task {
            async let source=ScanImageLoader.shared.image(leaf.original,limit:2400)
            async let result=ScanImageLoader.shared.image(leaf.output,limit:2400)
            originalImage=await source
            let loaded=await result
            if preview==nil {preview=loaded}
            if beginCrop && !didShowInitialCrop {didShowInitialCrop=true;cropping=true}else{refresh()}
        }
        .onChange(of:leaf.finish){_,_ in dirty=true;refresh()}.onChange(of:leaf.edgeFill){_,_ in dirty=true;refresh()}
        .onChange(of:leaf.sharpness){_,_ in dirty=true;queuePreview()}
        .onChange(of:leaf.edgeReach){_,_ in dirty=true;queuePreview()}
        .onChange(of:leaf.edgeOverlap){_,_ in dirty=true;queuePreview()}
        .interactiveDismissDisabled(dirty || (store.busy && rendering))
        .onDisappear {
            previewDebounce?.cancel()
            Task {
                if let saved=store.document(documentID)?.pages.first(where:{$0.id==leaf.id}),!saved.ocrReady {await store.analyze(documentID,only:leaf.id)}
            }
        }
        .sheet(isPresented:$cropping) {
            CornerEditor(file:leaf.original,initial:leaf.quad ?? .full) { q in leaf.quad=q;leaf.manualCrop=true;leaf.cropVerified=true;dirty=true;refresh() }
        }
        .sheet(isPresented:$cleaning) {
            CleanupEditor(file:leaf.original,initial:leaf.cleanupStrokes ?? [],automatic:false,reference:leaf) { strokes in
                leaf.cleanupStrokes=strokes;dirty=true;refresh()
            }
        }
        .sheet(isPresented:Binding(get:{textImage != nil},set:{if !$0 {textImage=nil}})) {
            if let image=textImage {LiveTextSheet(image:image)}
        }
        .alert("Не вдалося зберегти зміни",isPresented:Binding(get:{store.error != nil},set:{if !$0 {store.error=nil}})) {Button("Зрозуміло") {store.error=nil}} message:{Text(store.error ?? "")}
        .overlay { if store.busy { ProgressView().padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:16)) } }
    }
    func tool(_ title:String,_ icon:String,action:@escaping()->Void)->some View {
        VStack(spacing:7) {
            Button(action:action) {Image(systemName:icon).font(.title3).frame(width:28,height:44)}.scanSecondaryButton().accessibilityLabel(title)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
    func queuePreview() {
        previewDebounce?.cancel()
        previewDebounce=Task {
            try? await Task.sleep(nanoseconds:200_000_000)
            guard !Task.isCancelled else {return}
            refresh()
        }
    }
    func refresh() {
        generation+=1
        guard !rendering else {refreshQueued=true;return}
        let item=leaf,version=generation
        rendering=true
        Task {
            do {
                let result=try await Task.detached(priority:.userInitiated) {try autoreleasepool{try Imaging.renderWithEdgeReport(item)}}.value
                if generation==version {
                    preview=result.image;showingOriginal=false
                    if dirty {
                        let saved=await store.saveRenderedPage(documentID,leaf:item,image:result.image,changed:result.changed)
                        if saved && generation==version {dirty=false}
                    }
                    previewStatus = !item.edgeFill ? "Очищення вимкнено":(result.changed==0 ? "Фон не знайдено — уточніть кути або скористайтесь пензлем":"Край оновлено · замінено \(result.changed) пікселів")
                }
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
    @State private var activeCorner:Int?
    @State private var dragOrigin:Point?
    let done:(Quad)->Void
    init(file:String,initial:Quad,done:@escaping(Quad)->Void) { self.file=file;_quad=State(initialValue:initial);self.done=done }
    var body:some View {
        NavigationStack {
            VStack(spacing:20) {
                Text("Перетягніть точки на кути. Точне положення видно у лупі над пальцем.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
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
                            }.fill(Color.accent.opacity(0.12))
                            Path { path in
                                for i in 0..<4 {
                                    let p=CGPoint(x:offset.x+quad.points[i].x*size.width,y:offset.y+quad.points[i].y*size.height)
                                    if i==0 {path.move(to:p)} else{path.addLine(to:p)}
                                };path.closeSubpath()
                            }.stroke(quad.valid ? Color.accent : .red,lineWidth:2)
                            ForEach(0..<4,id:\.self) { i in
                                Circle().fill(.white).frame(width:22,height:22).overlay(Circle().stroke(Color.accent,lineWidth:4)).frame(width:48,height:48).contentShape(Rectangle())
                                    .position(x:offset.x+quad.points[i].x*size.width,y:offset.y+quad.points[i].y*size.height)
                                    .accessibilityLabel(["Верхній лівий кут","Верхній правий кут","Нижній правий кут","Нижній лівий кут"][i])
                                    .gesture(DragGesture(minimumDistance:0,coordinateSpace:.named("crop")).onChanged { value in
                                        if activeCorner != i {activeCorner=i;dragOrigin=quad.points[i]}
                                        guard let origin=dragOrigin,size.width>0,size.height>0 else {return}
                                        quad.points[i]=Point(x:min(1,max(0,origin.x+value.translation.width/size.width)),y:min(1,max(0,origin.y+value.translation.height/size.height)))
                                    }.onEnded {_ in activeCorner=nil;dragOrigin=nil})
                            }
                            if let active=activeCorner {
                                let point=quad.points[active]
                                let x=offset.x+point.x*size.width,y=offset.y+point.y*size.height
                                let loupeX=min(max(65,x),max(65,proxy.size.width-65))
                                let loupeY=y>155 ? y-100:min(proxy.size.height-65,y+110)
                                CornerLoupe(image:image,point:point,displaySize:size)
                                    .position(x:loupeX,y:max(65,loupeY)).allowsHitTesting(false)
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

private struct CornerLoupe:View {
    let image:UIImage
    let point:Point
    let displaySize:CGSize
    var body:some View {
        // Draw in a fixed 120-point canvas. A large SwiftUI image inside a
        // ZStack changes its layout bounds and moves the sample off the loupe.
        Canvas {context,canvas in
            let bounds=CGRect(origin:.zero,size:canvas)
            context.fill(Path(bounds),with:.color(Color(white:0.12)))
            guard displaySize.width>0,displaySize.height>0 else {return}
            let zoom:CGFloat=3.0
            let width:CGFloat=displaySize.width*zoom
            let height:CGFloat=displaySize.height*zoom
            let centerX:CGFloat=canvas.width/2
            let centerY:CGFloat=canvas.height/2
            let sourceX:CGFloat=CGFloat(point.x)*width
            let sourceY:CGFloat=CGFloat(point.y)*height
            let destination=CGRect(x:centerX-sourceX,y:centerY-sourceY,width:width,height:height)
            let resolved=context.resolve(Image(uiImage:image))
            context.draw(resolved,in:destination)
            var crosshair=Path()
            crosshair.move(to:CGPoint(x:centerX-13,y:centerY))
            crosshair.addLine(to:CGPoint(x:centerX+13,y:centerY))
            crosshair.move(to:CGPoint(x:centerX,y:centerY-13))
            crosshair.addLine(to:CGPoint(x:centerX,y:centerY+13))
            context.stroke(crosshair,with:.color(.black),lineWidth:3)
            context.stroke(crosshair,with:.color(.white),lineWidth:1)
        }.frame(width:120,height:120).clipShape(RoundedRectangle(cornerRadius:16))
            .overlay(RoundedRectangle(cornerRadius:16).stroke(.white,lineWidth:3))
            .shadow(color:.black.opacity(0.5),radius:8,y:3)
    }
}
