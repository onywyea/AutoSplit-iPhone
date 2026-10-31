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
    private var stopped=false
    init() { do { documents=try Disk.load() } catch { self.error="Не вдалося відкрити список сканів: \(error.localizedDescription)" } }
    func document(_ id:UUID)->ScanDocument? { documents.first{$0.id==id} }
    func index(_ id:UUID)->Int? { documents.firstIndex{$0.id==id} }
    func save() { do { try Disk.save(documents) } catch { self.error=error.localizedDescription } }
    func newDocument()->UUID { let doc=ScanDocument(); documents.insert(doc,at:0); save(); return doc.id }
    func cancel() { stopped=true; status="Зупинка після поточної сторінки…" }
    func addImage(_ image:UIImage,to id:UUID) async {
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
            documents[i].pages.append(Leaf(original:name,output:name)); save()
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
                    guard let pdf=PDFDocument(url:url),!pdf.isLocked else { throw ScanError.message("PDF недоступний або захищений паролем") }
                    for p in 0..<pdf.pageCount {
                        if stopped { break }
                        status="Імпорт \(p+1)/\(pdf.pageCount)"
                        if let page=pdf.page(at:p) {
                            let box=page.bounds(for:.mediaBox),scale=min(4,2800/max(box.width,box.height))
                            let image=page.thumbnail(of:CGSize(width:box.width*scale,height:box.height*scale),for:.mediaBox)
                            await addImage(image,to:id)
                        }
                    }
                } else {
                    guard let image=UIImage(contentsOfFile:url.path) else { throw ScanError.message("Не вдалося відкрити фото") }
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
                documents[i].pages[p].note=result.note; documents[i].pages[p].ocrReady=true; save()
            } catch {
                if let i=index(id),let p=documents[i].pages.firstIndex(where:{$0.id==leaf.id}) { documents[i].pages[p].note=error.localizedDescription }
            }
        }
        refreshNames(id)
        status=stopped ? "Зупинено. Можна продовжити пізніше" : "Скан готовий до перегляду"
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
        busy=true; status="Оновлення сторінки…"; defer{busy=false}
        do {
            let name=try await Task.detached { try autoreleasepool { try Disk.writeImage(Imaging.render(leaf)) } }.value
            var edited=leaf; edited.output=name; edited.text=""; edited.ocrReady=false; edited.note="Зміни збережено — оновіть розпізнавання"
            documents[i].pages[p]=edited; documents[i].candidates=[]; save()
        } catch { self.error=error.localizedDescription }
    }
    func deletePage(_ doc:UUID,_ leaf:UUID) {
        guard !busy,let i=index(doc) else{return}
        documents[i].pages.removeAll{$0.id==leaf}; refreshNames(doc); save()
    }
    func movePages(_ doc:UUID,from:IndexSet,to:Int) { guard !busy,let i=index(doc) else{return}; documents[i].pages.move(fromOffsets:from,toOffset:to);save() }
    func deleteDocument(_ id:UUID) { guard !busy else{return};documents.removeAll{$0.id==id};save() }
    func export(_ ids:Set<UUID>,task:String?=nil) async {
        guard !busy else{return};busy=true;status="Підготовка PDF…";shareURLs=[]
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
                    let url=folder.appendingPathComponent("\(n+1)_"+NameFinder.safeName(doc.title)+".pdf")
                    // Stream PDF pages directly to disk instead of building the whole PDF in memory.
                    guard let consumer=CGDataConsumer(url:url as CFURL) else{throw ScanError.message("Не вдалося створити PDF")}
                    var box=CGRect(x:0,y:0,width:595,height:842)
                    guard let context=CGContext(consumer:consumer,mediaBox:&box,nil) else{throw ScanError.message("Помилка PDF")}
                    do {
                        for leaf in doc.pages {
                            try autoreleasepool {
                                guard let image=Disk.image(leaf.output),let cg=image.cgImage else{throw ScanError.message("Не знайдено зображення сторінки")}
                                var bounds=image.size.width>image.size.height ? CGRect(x:0,y:0,width:842,height:595) : box
                                let media=Data(bytes:&bounds,count:MemoryLayout<CGRect>.size) as CFData
                                context.beginPDFPage([kCGPDFContextMediaBox as String:media] as CFDictionary)
                                let factor=min(bounds.width/image.size.width,bounds.height/image.size.height)
                                let size=CGSize(width:image.size.width*factor,height:image.size.height*factor)
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
            shareURLs=urls;status="PDF підготовлено"
        } catch { self.error=error.localizedDescription }
    }
}
