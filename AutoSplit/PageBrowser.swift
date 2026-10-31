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
                if let page=selectedPage,page.sourceKind=="camera",page.cropVerified != true {
                    Button {editing=true} label:{Label("Межі не знайдено — вкажіть кути",systemImage:"crop").font(.caption.weight(.semibold)).padding(10)}.tint(.orange).disabled(store.busy)
                }
                DocumentPager(pages:pages.map {BrowserPage(id:$0.id,file:$0.output)},selection:$selection)
                    .frame(maxWidth:.infinity,maxHeight:.infinity).layoutPriority(1)
                if pages.count>1 {
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
                }.frame(height:96)
                }
                HStack(spacing:24) {
                    Button {step(-1)} label:{Image(systemName:"chevron.left").frame(width:44,height:44)}.disabled(position==0)
                    Button {editing=true} label:{Label("Редагувати",systemImage:"slider.horizontal.3").font(.subheadline.weight(.semibold)).frame(maxWidth:.infinity)}.disabled(store.busy)
                    Button {step(1)} label:{Image(systemName:"chevron.right").frame(width:44,height:44)}.disabled(position+1>=pages.count)
                }.padding(.horizontal,16).padding(.bottom,6)
            } else {ContentUnavailableView("Немає сторінок",systemImage:"doc")}
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.black)
        .navigationTitle("\(pages.isEmpty ? 0:position+1) / \(pages.count)").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Button {Task {await store.rotateAutomatically(documentID,pageID:selection)}} label:{Image(systemName:"wand.and.stars")}.disabled(store.busy).accessibilityLabel("Автоповорот цієї сторінки")
            }
        }
        .overlay(alignment:.top) {if store.busy {HStack {ProgressView();Text(store.status).font(.caption)}.padding(10).background(.regularMaterial,in:Capsule()).padding(.top,8)}}
        .sheet(isPresented:$editing) {if let page=selectedPage {NavigationStack {PageEditor(documentID:documentID,leaf:page,beginCrop:page.sourceKind=="camera" && page.cropVerified != true)}}}
    }
    private func step(_ delta:Int) {
        let next=position+delta
        guard pages.indices.contains(next) else {return}
        selection=pages[next].id
    }
}
