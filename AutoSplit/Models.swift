import Foundation
import UIKit
import ImageIO

enum Finish: String, Codable, CaseIterable { case white = "Білий кольоровий", natural = "Оригінальний", clean = "Чистий", mono = "Чорно-білий" }
struct Leaf: Codable, Identifiable {
    var id = UUID()
    var original: String
    var output: String
    var quad: Quad?
    var sourceKind: String? = nil
    var originalPDF: String? = nil
    var originalPDFPage: Int? = nil
    var manualCrop: Bool? = nil
    var cropVerified: Bool? = nil
    var turns = 0
    var manualTurns: Int? = nil
    var finish = Finish.natural
    var edgeFill = true
    var edgeOverlap:Double? = nil
    var edgeReach:Double? = nil
    var edgeChoiceExplicit:Bool? = nil
    var edgeRepairCount:Int? = nil
    var edgeRevision:Int? = nil
    var cleanupStrokes: [CleanupStroke]? = nil
    var text = ""
    var note = "Очікує обробки"
    var ocrReady = false
    var reviewed:Bool? = nil
}
struct CleanupStroke: Codable, Equatable {
    var points: [Point]
    var radius: Double
}
struct ScanDocument: Codable, Identifiable {
    var id = UUID()
    var title = "Новий скан"
    var created = Date()
    var pages: [Leaf] = []
    var candidates: [NameCandidate] = []
    var nameConfirmed = false
    var preferredFinish: Finish? = nil
}
enum ScanError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
enum Disk {
    static var root: URL {
        let u=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ScanFlow-v2")
        try? FileManager.default.createDirectory(at:u,withIntermediateDirectories:true)
        return u
    }
    static func url(_ name: String) -> URL { root.appendingPathComponent(name) }
    static func writeImage(_ image: UIImage) throws -> String {
        let name=UUID().uuidString+".jpg"
        guard let bytes=image.jpegData(compressionQuality:0.97) else { throw ScanError.message("Не вдалося записати сторінку") }
        try bytes.write(to:url(name),options:[.atomic,.completeFileProtection]); return name
    }
    static func image(_ name: String, limit: Int = 4096) -> UIImage? {
        guard let source=CGImageSourceCreateWithURL(url(name) as CFURL,nil),
              let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:limit,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        return UIImage(cgImage:cg)
    }
    static func save(_ documents: [ScanDocument]) throws {
        try JSONEncoder().encode(documents).write(to:url("documents.json"),options:[.atomic,.completeFileProtection])
    }
    static func load() throws -> [ScanDocument] {
        guard FileManager.default.fileExists(atPath:url("documents.json").path) else { return [] }
        return try JSONDecoder().decode([ScanDocument].self,from:Data(contentsOf:url("documents.json")))
    }
}
