import SwiftUI
import PDFKit

@MainActor
final class ScannerStore:ObservableObject {
    @Published var documents:[ScanDocument]=[]
    @Published var busy=false
    @Published var savingPhotos=0
    @Published var status=""
    @Published var error:String?
    @Published var shareURLs:[URL]=[]
    @Published var exportSummary=""
    private var stopped=false
    init() { do { documents=try Disk.load() } catch { self.error="Не вдалося відкрити список сканів: \(error.localizedDescription)" } }
    func document(_ id:UUID)->ScanDocument? { documents.first{$0.id==id} }
    func index(_ id:UUID)->Int? { documents.firstIndex{$0.id==id} }
    func save() { do { try Disk.save(documents) } catch { self.error=error.localizedDescription } }
    func newDocument()->UUID { let doc=ScanDocument(); documents.insert(doc,at:0); save(); return doc.id }
    func cancel() { stopped=true; status="Зупинка після поточної сторінки…" }
    func addImage(_ image:UIImage,to id:UUID,sourceKind:String="image",prepare:Bool=false,pdfFile:String?=nil,pdfPage:Int?=nil) async {
        guard index(id) != nil else { return }
        savingPhotos += 1
        defer { savingPhotos -= 1 }
        do {
            let name=try await Task.detached(priority:.userInitiated) {
                try autoreleasepool {
                    let values=try FileManager.default.attributesOfFileSystem(forPath:Disk.root.path)
                    if let free=values[.systemFreeSize] as? NSNumber,free.int64Value<80_000_000 { throw ScanError.message("Замало вільного місця для наступної сторінки") }
                    return try Disk.writeImage(Imaging.resized(image,limit:3000))
                }
            }.value
            guard let i=index(id) else { return }
            var leaf=Leaf(original:name,output:name)
            leaf.sourceKind=sourceKind;leaf.originalPDF=pdfFile;leaf.originalPDFPage=pdfPage
            if sourceKind=="pdf" {leaf.quad = .full;leaf.cropVerified=true;leaf.edgeFill=true}
            if prepare {leaf.note="Визначення меж аркуша…"}
            documents[i].pages.append(leaf);save()
            if prepare {
                let snapshot=leaf
                let preview=try await Task.detached(priority:.userInitiated) {try autoreleasepool {try Imaging.prepareCapture(snapshot)}}.value
                let output=try await Task.detached {try Disk.writeImage(preview.image)}.value
                if let d=index(id),let p=documents[d].pages.firstIndex(where:{$0.id==snapshot.id}) {
                    documents[d].pages[p].output=output;documents[d].pages[p].quad=preview.quad
                    documents[d].pages[p].cropVerified=preview.verified;documents[d].pages[p].edgeRepairCount=preview.edgeRepairCount;documents[d].pages[p].edgeRevision=9
                    documents[d].pages[p].note=preview.verified ? "Межі знайдено. Розпізнавання після завершення зйомки":"Межі не знайдено — вкажіть кути або перезніміть ближче"
                    documents[d].pages[p].note += " · "+(preview.edgeRepairCount>0 ? "Край оброблено":"Край перевірено — без змін")
                    save()
                }
            }
        } catch { self.error=error.localizedDescription }
    }
    func importFiles(_ urls:[URL],to id:UUID) async {
        guard !busy else { return }; busy=true; stopped=false
        defer { busy=false; save() }
        for url in urls {
            if stopped { break }
            let access=url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                if url.pathExtension.lowercased()=="pdf" {
                    let sourceName=UUID().uuidString+".pdf"
                    let pageCount=try await Task.detached(priority:.userInitiated) { () throws -> Int in
                        guard let pdf=PDFDocument(url:url),!pdf.isLocked else {throw ScanError.message("PDF недоступний або захищений паролем")}
                        try FileManager.default.copyItem(at:url,to:Disk.url(sourceName))
                        try FileManager.default.setAttributes([.protectionKey:FileProtectionType.complete],ofItemAtPath:Disk.url(sourceName).path)
                        return pdf.pageCount
                    }.value
                    for p in 0..<pageCount {
                        if stopped { break }
                        status="Імпорт \(p+1)/\(pageCount)"
                        let image=try await Task.detached(priority:.userInitiated) { () throws -> UIImage in
                            try autoreleasepool {
                                guard let pdf=PDFDocument(url:Disk.url(sourceName)),let page=pdf.page(at:p) else {throw ScanError.message("Не вдалося відкрити сторінку PDF")}
                                let box=page.bounds(for:.mediaBox),scale=min(4,2800/max(box.width,box.height))
                                return page.thumbnail(of:CGSize(width:box.width*scale,height:box.height*scale),for:.mediaBox)
                            }
                        }.value
                        await addImage(image,to:id,sourceKind:"pdf",pdfFile:sourceName,pdfPage:p)
                    }
                } else {
                    let image=try await Task.detached(priority:.userInitiated) { () throws -> UIImage in
                        guard let image=UIImage(contentsOfFile:url.path) else {throw ScanError.message("Не вдалося відкрити фото")}
                        return Imaging.resized(image,limit:3000)
                    }.value
                    await addImage(image,to:id)
                }
            } catch { self.error=error.localizedDescription; break }
        }
    }
    func analyze(_ id:UUID,only pageID:UUID?=nil,force:Bool=false) async {
        guard !busy,let doc=document(id) else { return }; busy=true; stopped=false
        defer { busy=false; save() }
        let pending=doc.pages.filter { pageID == nil ? (force || !$0.ocrReady) : $0.id==pageID }
        for (position,leaf) in pending.enumerated() {
            if stopped { break }
            status="Обробка \(position+1)/\(pending.count)"
            do {
                let result=try await Task.detached(priority:.userInitiated) { try autoreleasepool { try Imaging.process(leaf) } }.value
                let output=try await Task.detached { try Disk.writeImage(result.image) }.value
                guard let i=index(id),let p=documents[i].pages.firstIndex(where:{$0.id==leaf.id}) else { continue }
                documents[i].pages[p].output=output; documents[i].pages[p].quad=result.quad
                documents[i].pages[p].turns=result.turns; documents[i].pages[p].text=result.text
                documents[i].pages[p].note=result.note;documents[i].pages[p].cropVerified=result.cropVerified;documents[i].pages[p].edgeRepairCount=result.edgeRepairCount;documents[i].pages[p].edgeRevision=9; documents[i].pages[p].ocrReady=true; save()
            } catch {
                if let i=index(id),let p=documents[i].pages.firstIndex(where:{$0.id==leaf.id}) { documents[i].pages[p].note=error.localizedDescription }
            }
        }
        refreshNames(id)
        status=stopped ? "Зупинено. Можна продовжити пізніше" : "Скан готовий до перегляду"
    }
    // Explicit action: choosing automatic rotation clears the saved manual override.
    func rotateAutomatically(_ id:UUID,pageID:UUID?=nil) async {
        guard !busy,let i=index(id) else {return}
        for p in documents[i].pages.indices where pageID == nil || documents[i].pages[p].id==pageID {
            documents[i].pages[p].manualTurns=nil;documents[i].pages[p].ocrReady=false
        }
        error=nil;save()
        await analyze(id,only:pageID,force:true)
    }
    func rebuildSafely(_ id:UUID) async {
        guard !busy,let i=index(id) else {return}
        for p in documents[i].pages.indices {
            documents[i].pages[p].manualTurns=nil
            documents[i].pages[p].ocrReady=false
            documents[i].pages[p].quad=nil;documents[i].pages[p].cropVerified=nil;documents[i].pages[p].manualCrop=nil
            documents[i].pages[p].cleanupStrokes=nil;documents[i].pages[p].finish = .natural
            documents[i].pages[p].edgeFill=true;documents[i].pages[p].edgeRevision=nil
        }
        error=nil;save();await analyze(id,force:true)
    }
    func ensureEdgeProcessing(_ id:UUID,force:Bool=false) async {
        guard !busy,let doc=document(id) else {return}
        let pending=doc.pages.filter {force || ($0.edgeRevision ?? 0)<9}
        guard !pending.isEmpty else {return}
        busy=true;stopped=false;error=nil
        defer {busy=false;save()}
        for (position,original) in pending.enumerated() {
            if stopped {break}
            var leaf=original
            if force || leaf.edgeChoiceExplicit != true {leaf.edgeFill=true}
            status="Обробка країв \(position+1)/\(pending.count)"
            do {
                let item=leaf
                let result=try await Task.detached(priority:.utility) {try autoreleasepool {try Imaging.renderWithEdgeReport(item)}}.value
                let output=try await Task.detached {try Disk.writeImage(result.image)}.value
                guard let d=index(id),let p=documents[d].pages.firstIndex(where:{$0.id==leaf.id}) else {continue}
                documents[d].pages[p].output=output;documents[d].pages[p].edgeFill=leaf.edgeFill
                documents[d].pages[p].edgeRepairCount=result.changed;documents[d].pages[p].edgeRevision=9
                let previous=original.note.components(separatedBy:" · ").filter {!$0.hasPrefix("Край ") && $0 != "Очистку краю вимкнено"}
                let edgeNote=leaf.edgeFill ? (result.changed>0 ? "Край оброблено":"Край перевірено — без змін") : "Очистку краю вимкнено"
                documents[d].pages[p].note=([edgeNote]+previous).joined(separator:" · ")
                save()
            } catch {self.error=error.localizedDescription;break}
        }
        status=stopped ? "Зупинено. Обробку країв можна продовжити" : "Краї перевірено"
    }
    func refreshNames(_ id:UUID) {
        guard let i=index(id) else { return }
        let text=documents[i].pages.map(\.text).joined(separator:"\n")
        let candidates=NameFinder.candidates(text); documents[i].candidates=candidates
        // Never silently choose between a deceased service member and a relative.
        let explicit=candidates.filter(\.explicit)
        if !documents[i].nameConfirmed,explicit.count==1 { documents[i].title=explicit[0].name }
        save()
    }
    func rename(_ id:UUID,_ title:String) { guard let i=index(id) else{return}; documents[i].title=title; documents[i].nameConfirmed=true; save() }
    func updatePage(_ doc:UUID,_ leaf:Leaf) async {
        guard !busy,let i=index(doc),let p=documents[i].pages.firstIndex(where:{$0.id==leaf.id}) else{return}
        busy=true;error=nil; status="Оновлення сторінки…"; defer{busy=false}
        do {
            let result=try await Task.detached {try autoreleasepool {try Imaging.renderWithEdgeReport(leaf)}}.value
            let name=try await Task.detached {try Disk.writeImage(result.image)}.value
            var edited=leaf;edited.edgeRepairCount=result.changed;edited.edgeRevision=9;if edited.manualCrop==true {edited.cropVerified=true}; edited.output=name; edited.text=""; edited.ocrReady=false; edited.note="Зміни збережено — оновіть розпізнавання"
            documents[i].pages[p]=edited; documents[i].candidates=[]; save()
        } catch { self.error=error.localizedDescription }
    }
    func deletePage(_ doc:UUID,_ leaf:UUID) {
        guard !busy,let i=index(doc) else{return}
        documents[i].pages.removeAll{$0.id==leaf}; refreshNames(doc); save()
    }
    func movePages(_ doc:UUID,from:IndexSet,to:Int) { guard !busy,let i=index(doc) else{return}; documents[i].pages.move(fromOffsets:from,toOffset:to);save() }
    func deleteDocument(_ id:UUID) {deleteDocuments([id])}
    func deleteDocuments(_ ids:Set<UUID>) {
        guard !busy,savingPhotos==0 else{return}
        let previous=documents
        let removed=documents.filter{ids.contains($0.id)}
        documents.removeAll{ids.contains($0.id)}
        do {try Disk.save(documents)}catch{documents=previous;self.error=error.localizedDescription;return}
        let kept=Set(documents.flatMap{doc in doc.pages.flatMap{[$0.original,$0.output]+[$0.originalPDF].compactMap{$0}}})
        let files=Set(removed.flatMap{doc in doc.pages.flatMap{[$0.original,$0.output]+[$0.originalPDF].compactMap{$0}}}).subtracting(kept)
        Task.detached(priority:.utility) {
            for file in files where (file as NSString).lastPathComponent==file {
                try? FileManager.default.removeItem(at:Disk.url(file))
            }
        }
    }
    func export(_ ids:Set<UUID>,task:String?=nil,compression:PDFCompression = .balanced) async {
        guard !busy else{return};busy=true;error=nil;status="Підготовка PDF…";shareURLs=[];exportSummary=""
        defer{busy=false}
        let selected=documents.filter{ids.contains($0.id)}
        do {
            guard !selected.isEmpty else{throw ScanError.message("Виберіть скани")}
            let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let urls=try await Task.detached(priority:.userInitiated) { () throws -> [URL] in
                var urls:[URL]=[]
                for (n,doc) in selected.enumerated() {
                    guard !doc.pages.isEmpty else{throw ScanError.message("Скан «\(doc.title)» порожній")}
                    if let unverified=doc.pages.firstIndex(where:{$0.sourceKind=="camera" && $0.cropVerified != true}) {
                        throw ScanError.message("Сторінка \(unverified+1): межі аркуша не визначені. Вкажіть кути або явно залиште весь кадр у редакторі.")
                    }
                    let url=folder.appendingPathComponent("\(n+1)_"+NameFinder.safeName(doc.title)+".pdf")
                    // A PDF import does not need to be rasterized again on export.
                    // Keep original page contents and only update the page rotation.
                    let keepPDF=compression == .original && doc.pages.allSatisfy {
                        $0.originalPDF != nil && $0.originalPDFPage != nil && $0.manualCrop != true && ($0.cleanupStrokes ?? []).isEmpty && $0.finish == .natural && ($0.edgeRepairCount ?? 0)==0
                    }
                    if keepPDF {
                        let merged=PDFDocument()
                        var sources:[String:PDFDocument]=[:]
                        for leaf in doc.pages {
                            guard let file=leaf.originalPDF,let number=leaf.originalPDFPage else {throw ScanError.message("Не знайдено вихідну сторінку PDF")}
                            if sources[file]==nil {sources[file]=PDFDocument(url:Disk.url(file))}
                            guard let source=sources[file],let original=source.page(at:number),let page=original.copy() as? PDFPage else {throw ScanError.message("Не вдалося відкрити вихідну сторінку PDF")}
                            page.rotation=(page.rotation+leaf.turns*90)%360
                            merged.insert(page,at:merged.pageCount)
                        }
                        guard merged.write(to:url) else {throw ScanError.message("Не вдалося зберегти PDF")}
                        urls.append(url)
                        continue
                    }
                    // Stream PDF pages directly to disk instead of building the whole PDF in memory.
                    guard let consumer=CGDataConsumer(url:url as CFURL) else{throw ScanError.message("Не вдалося створити PDF")}
                    var box=CGRect(x:0,y:0,width:595,height:842)
                    guard let context=CGContext(consumer:consumer,mediaBox:&box,nil) else{throw ScanError.message("Помилка PDF")}
                    do {
                        for leaf in doc.pages {
                            try autoreleasepool {
                                let cg=try PDFImage.load(leaf.output,compression:compression)
                                let imageSize=CGSize(width:cg.width,height:cg.height)
                                var bounds=imageSize.width>imageSize.height ? CGRect(x:0,y:0,width:842,height:595) : box
                                let media=Data(bytes:&bounds,count:MemoryLayout<CGRect>.size) as CFData
                                context.beginPDFPage([kCGPDFContextMediaBox as String:media] as CFDictionary)
                                let factor=min(bounds.width/imageSize.width,bounds.height/imageSize.height)
                                let size=CGSize(width:imageSize.width*factor,height:imageSize.height*factor)
                                context.draw(cg,in:CGRect(x:(bounds.width-size.width)/2,y:(bounds.height-size.height)/2,width:size.width,height:size.height))
                                context.endPDFPage()
                            }
                        }
                        context.closePDF()
                    } catch { context.closePDF();throw error }
                    urls.append(url)
                }
                if let task {
                    let url=folder.appendingPathComponent("Завдання_для_ChatGPT.txt")
                    let manifest=selected.map{"• \($0.title): \($0.pages.count) стор."}.joined(separator:"\n")
                    try (task+"\n\nДокументи:\n"+manifest).write(to:url,atomically:true,encoding:.utf8);urls.append(url)
                }
                return urls
            }.value
            shareURLs=urls
            let bytes=urls.filter{$0.pathExtension=="pdf"}.reduce(Int64(0)) {sum,url in
                let values=try? url.resourceValues(forKeys:[.fileSizeKey])
                return sum+Int64(values?.fileSize ?? 0)
            }
            exportSummary="\(selected.count) PDF · \(ByteCountFormatter.string(fromByteCount:bytes,countStyle:.file))"
            status="PDF підготовлено"
        } catch { self.error=error.localizedDescription }
    }
}
