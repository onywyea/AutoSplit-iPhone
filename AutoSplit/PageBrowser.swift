import SwiftUI

struct PageBrowser:View {
    @EnvironmentObject var store:ScannerStore
    let documentID:UUID
    let initialPageID:UUID
    @State private var selection:UUID
    @State private var editing=false
    @State private var cropNow=false
    @State private var exporting=false
    @State private var quickSharing=false
    @State private var exportFailed=false
    @State private var removed:[(Int,Leaf)]=[]
    @State private var deleting=false
    @State private var styling=false
    @State private var originals=false
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
                    Button {editing=true} label:{Label("За бажанням уточніть краї",systemImage:"crop").font(.caption.weight(.semibold)).padding(10)}.tint(.orange).disabled(store.busy)
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
                VStack(spacing:6) {
                    HStack {
                        Button {step(-1)} label:{Image(systemName:"chevron.left").frame(width:44,height:44)}.disabled(position==0)
                        Spacer(minLength:0)
                        if let page=selectedPage {PageReviewBadge(page:page).lineLimit(1)}
                        Spacer(minLength:0)
                        Button {nextIssue()} label:{Image(systemName:"arrow.right.circle").frame(width:44,height:44)}.accessibilityLabel("Наступна сторінка для перевірки")
                            .disabled(!pages.contains(where:{$0.id != selection && $0.reviewReason != nil}))
                        Button {step(1)} label:{Image(systemName:"chevron.right").frame(width:44,height:44)}.disabled(position+1>=pages.count)
                    }
                    toolsDock

                }.padding(.horizontal,14).padding(.bottom,8).disabled(store.busy)

            } else {ContentUnavailableView("Немає сторінок",systemImage:"doc")}
            if !removed.isEmpty {
                Button {let id=removed.first?.1.id;store.restorePages(documentID,removed:removed);removed=[];if let id {selection=id}} label:{Label("Скасувати видалення",systemImage:"arrow.uturn.backward").frame(minHeight:44)}.disabled(store.busy || store.savingPhotos>0)
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity).background(.black)
        .navigationTitle("\(pages.isEmpty ? 0:position+1) / \(pages.count)").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)
        .toolbar {
            ToolbarItem(placement:.topBarTrailing) {
                Menu {
                    Button {exporting=true} label:{Label("Розмір / стиснення PDF",systemImage:"doc.zipper")}
                    Button {originals=true} label:{Label("Поділитися оригіналом",systemImage:"photo")}
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
        .sheet(isPresented:$exporting) {PDFExportSheet(ids:[documentID])}
        .sheet(isPresented:$quickSharing) {ShareSheet(urls:store.shareURLs)}
        .alert("Не вдалося підготувати PDF",isPresented:$exportFailed) {Button("Зрозуміло") {store.error=nil}} message:{Text(store.error ?? "Повторіть експорт")}

        .sheet(isPresented:$editing,onDismiss:{cropNow=false}) {if let page=selectedPage {NavigationStack {PageEditor(documentID:documentID,leaf:page,beginCrop:cropNow || (page.sourceKind=="camera" && page.cropVerified != true))}}}
        .sheet(isPresented:$styling) {DocumentStyleSheet(documentID:documentID)}
        .sheet(isPresented:$originals) {OriginalsExportSheet(documentID:documentID,pageID:selection)}
        .confirmationDialog("Видалити цю сторінку зі скану?",isPresented:$deleting,titleVisibility:.visible) {
            Button("Видалити сторінку",role:.destructive) {deleteSelectedPage()}
            Button("Скасувати",role:.cancel) {deletionTarget=nil}
        } message:{Text("Сторінку буде вилучено з документа. Інші сторінки залишаться.")}
        .onChange(of:pages.map(\.id)) {_,ids in
            if !ids.contains(selection),let first=ids.first {selection=first}
        }
    }
    private func savePDF() {
        Task {
            await store.export([documentID])
            if store.error != nil {exportFailed=true}
            else if !store.shareURLs.isEmpty {quickSharing=true}
        }
    }
    private var toolsDock:some View {
        ScanControls {
            HStack(spacing:4) {
                action("Обрізка","crop") {cropNow=true;editing=true}
                action("Поворот","rotate.right") {rotatePage()}
                action("Вигляд","slider.horizontal.3") {cropNow=false;editing=true}
                action("PDF","square.and.arrow.up") {savePDF()}
            }.padding(.vertical,8)
        }
    }
    private func action(_ title:String,_ icon:String,perform:@escaping ()->Void)->some View {
        VStack(spacing:6) {
            Button(action:perform) {Image(systemName:icon).font(.title3).frame(width:26,height:44)}
                .scanSecondaryButton().accessibilityLabel(title)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity)
    }
    private func nextIssue() {
        guard !pages.isEmpty else {return}
        for offset in 1..<pages.count {
            let index=(position+offset)%pages.count
            if pages[index].reviewReason != nil {selection=pages[index].id;return}
        }
    }
    private func rotatePage() {
        guard var page=selectedPage,!store.busy else {return}
        page.turns=(page.turns+1)%4;page.manualTurns=page.turns
        Task {await store.updatePage(documentID,page)}
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
        removed=store.deletePages(documentID,ids:[target])
        if let next {selection=next}
        deletionTarget=nil
    }
}
