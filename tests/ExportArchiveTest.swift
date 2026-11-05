import Foundation

@main
struct ExportArchiveTest {
    static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pdf = folder.appendingPathComponent("Тест_ПКМУ975.pdf")
        let task = folder.appendingPathComponent("Завдання.txt")
        try Data("%PDF-fixture".utf8).write(to: pdf)
        try Data("КОМПЛЕКТ-975".utf8).write(to: task)
        let parts = try ExportArchive.makeParts([pdf], task: task, in: folder, name: "Тест")
        guard parts.count == 1 else { throw ScanError.message("Expected one ZIP") }
    }
}

enum ScanError: Error { case message(String) }
