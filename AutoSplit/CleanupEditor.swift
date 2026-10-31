import SwiftUI

struct CleanupEditor:View {
    @Environment(\.dismiss) private var dismiss
    let file:String
    let automatic:Bool
    let reference:Leaf?
    let done:([CleanupStroke])->Void
    @State private var strokes:[CleanupStroke]
    @State private var current:[Point]=[]
    @State private var radius=0.025
    @State private var preview:UIImage?
    @State private var working=false
    @State private var error:String?
    init(file:String,initial:[CleanupStroke],automatic:Bool,reference:Leaf?=nil,done:@escaping([CleanupStroke])->Void) {
        self.file=file;self.automatic=automatic;self.reference=reference;self.done=done;_strokes=State(initialValue:initial)
    }
    var body:some View {
        NavigationStack {
            VStack(spacing:14) {
                Text(preview == nil ? "Зафарбуйте залишки фону. Не торкайтеся тексту та печаток." : "Перевірте результат. Зміни застосуються після натискання «Зберегти».")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                if let original=Disk.image(file) {
                    GeometryReader { proxy in
                        let factor=min(proxy.size.width/original.size.width,proxy.size.height/original.size.height)
                        let size=CGSize(width:original.size.width*factor,height:original.size.height*factor)
                        let offset=CGPoint(x:(proxy.size.width-size.width)/2,y:(proxy.size.height-size.height)/2)
                        ZStack(alignment:.topLeading) {
                            Image(uiImage:preview ?? original).resizable().frame(width:size.width,height:size.height).offset(x:offset.x,y:offset.y)
                            if preview == nil {
                                ForEach(Array(strokes.enumerated()),id:\.offset) { _,stroke in
                                    strokePath(stroke.points,size:size,offset:offset).stroke(.pink.opacity(0.45),style:StrokeStyle(lineWidth:CGFloat(stroke.radius)*min(size.width,size.height)*2,lineCap:.round,lineJoin:.round))
                                }
                                strokePath(current,size:size,offset:offset).stroke(.pink.opacity(0.55),style:StrokeStyle(lineWidth:CGFloat(radius)*min(size.width,size.height)*2,lineCap:.round,lineJoin:.round))
                                Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onChanged { value in
                                    let x=(value.location.x-offset.x)/size.width,y=(value.location.y-offset.y)/size.height
                                    guard x>=0,x<=1,y>=0,y<=1 else {return}
                                    current.append(Point(x:Double(x),y:Double(y)))
                                }.onEnded { _ in
                                    if !current.isEmpty {strokes.append(CleanupStroke(points:current,radius:radius));current=[]}
                                })
                            }
                        }
                    }.padding(.horizontal,12)
                }
                HStack {
                    Image(systemName:"circle.dotted")
                    Slider(value:$radius,in:0.008...0.07).disabled(preview != nil || working).accessibilityLabel("Розмір пензля")
                    Image(systemName:"circle.fill")
                }.tint(.mint).padding(.horizontal,24)
                HStack(spacing:24) {
                    Button {if !strokes.isEmpty {strokes.removeLast()};preview=nil} label:{Label("Скасувати штрих",systemImage:"arrow.uturn.backward")}.disabled(strokes.isEmpty || working)
                    Button(preview == nil ? "Перевірити" : "До пензля") {
                        if preview != nil {preview=nil;return}
                        renderPreview()
                    }.disabled(working)
                }.font(.subheadline).padding(.bottom,20)
                if let error {Text(error).font(.caption).foregroundStyle(.red)}
            }.background(Color.canvas).navigationTitle("Очистка краю").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Закрити"){dismiss()}.disabled(working)}
                ToolbarItem(placement:.confirmationAction){Button("Зберегти"){done(strokes);dismiss()}.disabled(working)}
            }
            .overlay {if working {ProgressView("Відновлення фону…").padding(24).background(.regularMaterial,in:RoundedRectangle(cornerRadius:18))}}
        }
    }
    private func strokePath(_ points:[Point],size:CGSize,offset:CGPoint)->Path {
        Path {path in
            guard let first=points.first else {return}
            let start=CGPoint(x:offset.x+first.x*size.width,y:offset.y+first.y*size.height)
            path.move(to:start)
            if points.count==1 {path.addLine(to:CGPoint(x:start.x+0.1,y:start.y+0.1))}
            for point in points.dropFirst(){path.addLine(to:CGPoint(x:offset.x+point.x*size.width,y:offset.y+point.y*size.height))}
        }
    }
    private func renderPreview() {
        working=true;error=nil
        let file=self.file,strokes=self.strokes,automatic=self.automatic,reference=self.reference
        Task {
            do {
                preview=try await Task.detached(priority:.userInitiated) {
                    if var page=reference {page.cleanupStrokes=strokes;return try Imaging.render(page)}
                    guard let image=Disk.image(file) else {throw ScanError.message("Оригінал відсутній")}
                    return try Imaging.cleanRim(image,automatic:automatic,strokes:strokes)
                }.value
            } catch {self.error=error.localizedDescription}
            working=false
        }
    }
}
