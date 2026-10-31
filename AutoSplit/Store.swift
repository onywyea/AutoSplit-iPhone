import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor
final class CaseStore: ObservableObject {
    @Published var data = CaseData()
    @Published var busy = false
    @Published var status = "Готово до сканування"
    @Published var error: String?
    @Published var exports: [URL] = []
    private var cancelled = false
    init() {
        do { data = try Storage.load() } catch { self.error = "Не вдалося відкрити збережений комплект: \(error.localizedDescription)" }
    }
    func save() { do { try Storage.save(data) } catch { self.error = error.localizedDescription } }
    func cancel() { cancelled = true; status = "Зупинка після поточної сторінки…" }
    func add(_ images: [UIImage]) {
        guard !busy else { return }
        do {
            for image in images {
                let name = try Storage.saveImage(Imaging.resized(image, limit: 3200))
                data.pages.append(ScanPage(imageFile: name, originalFile: name))
            }
            data.sections = []; save()
        } catch { self.error = error.localizedDescription }
    }
    func importFiles(_ urls: [URL]) async {
        guard !busy else { return }
        busy = true; cancelled = false
        defer { busy = false; save() }
        for url in urls {
            if cancelled { break }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                if url.pathExtension.lowercased() == "pdf" {
                    guard let pdf = PDFDocument(url: url), !pdf.isLocked else { throw AppError.message("PDF недоступний або захищений паролем") }
                    for index in 0..<pdf.pageCount {
                        if cancelled { break }
                        status = "Імпорт \(index + 1)/\(pdf.pageCount)"
                        guard let page = pdf.page(at: index) else { throw AppError.message("Не вдалося прочитати сторінку PDF") }
                        let box = page.bounds(for: .mediaBox)
                        let scale = min(4, 2600 / max(box.width, box.height))
                        let image = page.thumbnail(of: CGSize(width: box.width * scale, height: box.height * scale), for: .mediaBox)
                        data.pages.append(ScanPage(imageFile: try Storage.saveImage(image)))
                        await Task.yield()
                    }
                } else {
                    guard let image = UIImage(contentsOfFile: url.path) else { throw AppError.message("Не вдалося прочитати фото") }
                    data.pages.append(ScanPage(imageFile: try Storage.saveImage(Imaging.resized(image, limit: 3200))))
                }
                data.sections = []
            } catch { self.error = "\(url.lastPathComponent): \(error.localizedDescription)" }
        }
        status = cancelled ? "Імпорт зупинено" : "Сторінки імпортовано"
    }
    func analyze() async {
        guard !busy, !data.pages.isEmpty else { return }
        busy = true; cancelled = false
        data.sections = []; exports = []
        defer { busy = false; save() }
        // Source files are never overwritten. Each processed image is a new file.
        for index in data.pages.indices {
            if cancelled { break }
            status = "Обробка \(index + 1)/\(data.pages.count)"
            let page = data.pages[index]
            do {
                let result = try await Task.detached(priority: .userInitiated) { () throws -> OCRResult in
                    try autoreleasepool {
                        var original = page
                        original.imageFile = page.originalFile ?? page.imageFile
                        guard let image = Storage.image(original) else { throw AppError.message("Не знайдено сторінку") }
                        return try Imaging.process(image)
                    }
                }.value
                let detection = Rules.classify(result.text)
                if data.pages[index].originalFile == nil { data.pages[index].originalFile = data.pages[index].imageFile }
                data.pages[index].imageFile = try Storage.saveImage(result.image)
                data.pages[index].text = result.text
                data.pages[index].confidence = result.confidence
                data.pages[index].kind = detection.kind
                data.pages[index].starts = detection.starts
                data.pages[index].warning = (result.warnings + [detection.warning].compactMap { $0 }).joined(separator: "; ")
                save()
            } catch { data.pages[index].warning = "Обробка не завершена: \(error.localizedDescription)" }
        }
        if !cancelled { regroup(); status = "Перевірте межі та назви розділів" }
        else { data.sections = []; status = "Зупинено. Обробку можна запустити повторно" }
    }
    func regroup() {
        var groups: [ScanSection] = []
        for page in data.pages {
            // Registry extract attaches only to an immediately preceding passport group.
            let attachRegistry = page.kind == "Паспорт" && !page.starts && groups.last?.title == "Паспорт"
            if groups.isEmpty || page.starts || (page.kind == "Паспорт" && !page.starts && !attachRegistry) {
                groups.append(ScanSection(pageIDs: [page.id], title: page.kind))
            } else { groups[groups.count - 1].pageIDs.append(page.id) }
        }
        data.sections = groups; save()
    }
    func restore(_ id: UUID) {
        guard !busy, let index = data.pages.firstIndex(where: { $0.id == id }), let original = data.pages[index].originalFile else { return }
        data.pages[index].imageFile = original
        data.pages[index].text = ""; data.pages[index].confidence = 0
        data.pages[index].kind = Rules.unknown; data.pages[index].starts = false
        data.pages[index].warning = "Оригінал відновлено — потрібне розпізнавання"
        data.sections = []; save()
    }
    func move(_ id: UUID, offset: Int) {
        guard !busy, let index = data.pages.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard data.pages.indices.contains(target) else { return }
        data.pages.swapAt(index, target); data.sections = []; save()
    }
    func rotate(_ id: UUID) {
        guard !busy, let index = data.pages.firstIndex(where: { $0.id == id }), let image = Storage.image(data.pages[index]) else { return }
        do {
            data.pages[index].imageFile = try Storage.saveImage(Imaging.rotate(image, turns: 1))
            for s in data.sections.indices where data.sections[s].pageIDs.contains(id) { data.sections[s].reviewed = false }
            save()
        } catch { self.error = error.localizedDescription }
    }
    func remove(_ id: UUID) {
        guard !busy else { return }
        data.pages.removeAll { $0.id == id }
        for s in data.sections.indices {
            data.sections[s].pageIDs.removeAll { $0 == id }; data.sections[s].reviewed = false
        }
        data.sections.removeAll { $0.pageIDs.isEmpty }; save()
    }
    func toggleStart(_ id: UUID) {
        guard !busy, let index = data.pages.firstIndex(where: { $0.id == id }) else { return }
        data.pages[index].starts.toggle(); regroup()
    }
    func export() {
        guard !busy else { return }
        exports = []
        save()
        do {
            guard !data.sections.isEmpty, data.sections.allSatisfy({ $0.reviewed }) else { throw AppError.message("Спочатку перевірте кожен розділ") }
            guard !data.person.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("Вкажіть ФІО військовослужбовця") }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(Rules.safe(data.person), isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var files: [URL] = []
            var bankText = "Військовослужбовець: \(data.person)\n\n"
            for (number, section) in data.sections.enumerated() {
                let pages = section.pageIDs.compactMap { id in data.pages.first { $0.id == id } }
                guard pages.count == section.pageIDs.count, !pages.isEmpty else { throw AppError.message("Порушено склад розділу") }
                let stem = [data.caseName, section.relation, section.title].filter { !$0.isEmpty }.joined(separator: "_")
                let destination = folder.appendingPathComponent(String(format: "%02d_", number + 1) + Rules.safe(stem) + ".pdf")
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
                let bytes = renderer.pdfData { context in
                    for page in pages {
                        guard let image = Storage.image(page) else { continue }
                        // Keep natural landscape pages readable; do not rotate text sideways to force portrait.
                        let bounds = image.size.width > image.size.height ? CGRect(x: 0, y: 0, width: 842, height: 595) : CGRect(x: 0, y: 0, width: 595, height: 842)
                        context.beginPage(withBounds: bounds, pageInfo: [:])
                        let factor = min(bounds.width / image.size.width, bounds.height / image.size.height)
                        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
                        image.draw(in: CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height))
                    }
                }
                // Guard missing images explicitly instead of silently exporting fewer pages.
                guard pages.allSatisfy({ Storage.image($0) != nil }) else { throw AppError.message("Відсутнє зображення сторінки") }
                try bytes.write(to: destination, options: [.atomic, .completeFileProtection]); files.append(destination)
                let text = pages.map(\.text).joined(separator: "\n\n")
                if section.title == "Реквізити" || !Rules.ibans(text).isEmpty {
                    let recipient = section.recipient.isEmpty ? "НЕ ВКАЗАНО — ПЕРЕВІРИТИ" : section.recipient
                    bankText += "Розділ \(number + 1)\nОтримувач: \(recipient)\nСпорідненість: \(section.relation)\n"
                    for iban in Rules.ibans(text) {
                        bankText += "IBAN: \(iban) [\(Rules.validIBAN(iban) ? "контрольна сума правильна" : "ПОМИЛКА контрольної суми")]\n"
                    }
                    bankText += "Розпізнаний текст (перевірити за оригіналом):\n\(text)\n\n"
                }
            }
            let bankURL = folder.appendingPathComponent("Банківські_реквізити_ОГД.txt")
            try bankText.write(to: bankURL, atomically: true, encoding: .utf8); files.append(bankURL)
            let detailsURL = folder.appendingPathComponent("Дані_комплекту.txt")
            try "Військовослужбовець: \(data.person)\nНазва: \(data.caseName)\n\(data.notes)".write(to: detailsURL, atomically: true, encoding: .utf8)
            files.append(detailsURL); exports = files; status = "Файли підготовлено"
        } catch { self.error = error.localizedDescription }
    }
}
