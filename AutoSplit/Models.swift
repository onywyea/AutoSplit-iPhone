import Foundation
import UIKit

struct ScanPage: Identifiable, Codable {
    var id = UUID()
    var imageFile: String
    var originalFile: String? = nil
    var text = ""
    var kind = Rules.unknown
    var starts = false
    var warning: String? = "Потрібне розпізнавання"
    var confidence: Float = 0
}
struct ScanSection: Identifiable, Codable {
    var id = UUID()
    var pageIDs: [UUID]
    var title: String
    var recipient = ""
    var relation = ""
    var reviewed = false
}
struct CaseData: Codable {
    var pages: [ScanPage] = []
    var sections: [ScanSection] = []
    var person = ""
    var caseName = "Комплект_ПКМУ168"
    var notes = ""
}

enum Storage {
    static var root: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AutoSplit", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static func image(_ page: ScanPage) -> UIImage? { UIImage(contentsOfFile: root.appendingPathComponent(page.imageFile).path) }
    static func saveImage(_ image: UIImage) throws -> String {
        let name = UUID().uuidString + ".jpg"
        guard let data = image.jpegData(compressionQuality: 0.94) else { throw AppError.message("Не вдалося зберегти зображення") }
        try data.write(to: root.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        return name
    }
    static func save(_ value: CaseData) throws {
        try JSONEncoder().encode(value).write(to: root.appendingPathComponent("session.json"), options: [.atomic, .completeFileProtection])
    }
    static func load() throws -> CaseData {
        let url = root.appendingPathComponent("session.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return CaseData() }
        return try JSONDecoder().decode(CaseData.self, from: Data(contentsOf: url))
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
