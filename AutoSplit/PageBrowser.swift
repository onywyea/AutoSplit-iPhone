import SwiftUI

struct PageBrowser:View {
    @EnvironmentObject var store:ScannerStore
    let documentID:UUID
    let initialPageID:UUID
    @State private var selection:UUID
    @State private var editing=false
    var pages:[Leaf] {store.document(documentID)?.pages ?? []}
    var position:Int {pages.firstIndex(where:{$0.id==selection}) ?? 0}
    var selectedPage:Leaf? {pages.first(where:{$0.id==selection})}
    init(documentID:UUID,initialPageID:UUID) {
        self.documentID=documentID;self.initialPageID=initialPageID;_selection=State(initialValue:initialPageID)
    }
    var body:some View {
        VStack(spacing:0) {
            if !pages.isEmpty {
                TabView(selection:$selection) {
                    ForEach(Array(pages.enumerated()),id:\.element.id) { index,page in
                        Group {
                            // Only neighbouring pages decode full-resolution images, even in very large scans.
                            if abs(index-position)<=1 {ZoomPage(file:page.output)}
                            else {Color.black}
                        }.tag(page.id)
                    }
                }.tabViewStyle(.page(indexDisplayMode:.never)).background(.black)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal,showsIndicators:false) {
                        LazyHStack(spacing:10) {
                            ForEach(Array(pages.enumerated()),id:\.element.id) { index,page in
                                Button {selection=page.id} label: {
                                    VStack(spacing:4) {
                                        Thumb(file:page.output).frame(width:44,height:60).clipShape(RoundedRectangle(cornerRadius:5))
                                        Text("\(index+1)").font(.caption2.monospacedDigit()).foregroundStyle(selection==page.id ? Color.accent:.secondary)
                                    }.padding(4).overlay(RoundedRectangle(cornerRadius:8).stroke(selection==page.id ? Color.accent:.clear,lineWidth:2))
                                }.id(page.id).buttonStyle(.plain)
                            }
                        }.padding(.horizontal,18).padding(.vertical,10)
                    }.onChange(of:selection) {_,id in withAnimation {proxy.scrollTo(id,anchor:.center)}}
                        .onAppear {proxy.scrollTo(selection,anchor:.center)}
                }
                HStack(spacing:24) {
                    Button {step(-1)} label:{Image(systemName:"chevron.left").frame(width:44,height:44)}.disabled(position==0)
                    Button {editing=true} label:{Label("Редагувати",systemImage:"slider.horizontal.3").font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity)}.disabled(store.busy)
                    Button {step(1)} label:{Image(systemName:"chevron.right").frame(width:44,height:44)}.disabled(position+1>=pages.count)
                }.padding(.horizontal,16).padding(.bottom,6)
            } else {ContentUnavailableView("Немає сторінок",systemImage:"doc")}
        }.background(Color.canvas)
        .navigationTitle("\(pages.isEmpty ? 0:position+1) / \(pages.count)").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Button {Task {await store.rotateAutomatically(documentID,pageID:selection)}} label:{Image(systemName:"wand.and.stars")}.disabled(store.busy).accessibilityLabel("Автоповорот цієї сторінки")
            }
        }
        .overlay(alignment:.top) {if store.busy {HStack {ProgressView();Text(store.status).font(.caption)}.padding(10).background(.regularMaterial,in:Capsule()).padding(.top,8)}}
        .sheet(isPresented:$editing) {if let page=selectedPage {NavigationStack {PageEditor(documentID:documentID,leaf:page)}}}
    }
    private func step(_ delta:Int) {
        let next=position+delta
        guard pages.indices.contains(next) else {return}
        withAnimation {selection=pages[next].id}
    }
}
private struct ZoomPage:View {
    let file:String
    @State private var image:UIImage?
    var body:some View {
        Group {if let image {ZoomImage(image:image)} else {ProgressView().tint(.white)}}
            .task(id:file) {
                image=nil
                let decoded=await Task.detached(priority:.userInitiated){Disk.image(file,limit:3000)}.value
                guard !Task.isCancelled else {return}
                image=decoded
            }
            .onDisappear {image=nil}
    }
}
private final class ZoomCanvas:UIScrollView,UIScrollViewDelegate {
    let picture=UIImageView()
    var current:UIImage?
    override init(frame:CGRect) {
        super.init(frame:frame)
        delegate=self;minimumZoomScale=1;maximumZoomScale=5
        backgroundColor = .black;showsVerticalScrollIndicator=false;showsHorizontalScrollIndicator=false
        alwaysBounceHorizontal=false;alwaysBounceVertical=false
        picture.contentMode = .scaleAspectFit;addSubview(picture)
        let tap=UITapGestureRecognizer(target:self,action:#selector(doubleTap(_:)));tap.numberOfTapsRequired=2;addGestureRecognizer(tap)
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not supported")}
    func display(_ image:UIImage) {
        guard current !== image else {return}
        current=image;setZoomScale(1,animated:false);picture.image=image;setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if zoomScale==1 {picture.frame=CGRect(origin:.zero,size:bounds.size);contentSize=bounds.size}
    }
    func viewForZooming(in scrollView:UIScrollView)->UIView? {picture}
    @objc private func doubleTap(_ gesture:UITapGestureRecognizer) {
        if zoomScale>1 {setZoomScale(1,animated:true);return}
        let point=gesture.location(in:picture),factor:CGFloat=2.5
        let rect=CGRect(x:point.x-bounds.width/factor/2,y:point.y-bounds.height/factor/2,width:bounds.width/factor,height:bounds.height/factor)
        zoom(to:rect,animated:true)
    }
}
private struct ZoomImage:UIViewRepresentable {
    let image:UIImage
    func makeUIView(context:Context)->ZoomCanvas {let view=ZoomCanvas(frame:.zero);view.display(image);return view}
    func updateUIView(_ view:ZoomCanvas,context:Context){view.display(image)}
}
