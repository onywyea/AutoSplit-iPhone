import SwiftUI

struct PageBrowser:View {
    @EnvironmentObject var store:ScannerStore
    let documentID:UUID
    let initialPageID:UUID
    @State private var selection:UUID
    @State private var editing=false
    @State private var deleting=false
    @State private var styling=false
    @State private var deletionTarget:UUID?
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
                Menu {
                    Button {styling=true} label:{Label("Стиль усіх сторінок",systemImage:"slider.horizontal.3")}
                    Button {Task {await store.rotateAutomatically(documentID,pageID:selection)}} label:{Label("Автоповорот цієї сторінки",systemImage:"wand.and.stars")}
                } label:{Image(systemName:"ellipsis.circle")}.disabled(store.busy || pages.isEmpty).accessibilityLabel("Дії зі сканом")
            }
            ToolbarItem(placement:.topBarTrailing) {
                Button(role:.destructive) {deletionTarget=selection;deleting=true} label:{Image(systemName:"trash")}
                    .disabled(store.busy || store.savingPhotos>0 || selectedPage==nil)
                    .accessibilityLabel("Видалити поточну сторінку")
            }
        }
        .overlay(alignment:.top) {if store.busy {HStack {ProgressView();Text(store.status).font(.caption)}.padding(10).background(.regularMaterial,in:Capsule()).padding(.top,8)}}
        .sheet(isPresented:$editing) {if let page=selectedPage {NavigationStack {PageEditor(documentID:documentID,leaf:page,beginCrop:page.sourceKind=="camera" && page.cropVerified != true)}}}
        .sheet(isPresented:$styling) {DocumentStyleSheet(documentID:documentID)}
        .confirmationDialog("Видалити цю сторінку зі скану?",isPresented:$deleting,titleVisibility:.visible) {
            Button("Видалити сторінку",role:.destructive) {deleteSelectedPage()}
            Button("Скасувати",role:.cancel) {deletionTarget=nil}
        } message:{Text("Сторінку буде вилучено з документа. Інші сторінки залишаться.")}
        .onChange(of:pages.map(\.id)) {_,ids in
            if !ids.contains(selection),let first=ids.first {selection=first}
        }
    }
    private func step(_ delta:Int) {
        let next=position+delta
        guard pages.indices.contains(next) else {return}
        selection=pages[next].id
    }
    private func deleteSelectedPage() {
        guard !store.busy,store.savingPhotos==0,let target=deletionTarget,
              let index=pages.firstIndex(where:{$0.id==target}) else {return}
        let remaining=pages.filter {$0.id != target}
        let next=remaining.isEmpty ? nil:remaining[min(index,remaining.count-1)].id
        store.deletePage(documentID,target)
        if let next {selection=next}
        deletionTarget=nil
    }
}
