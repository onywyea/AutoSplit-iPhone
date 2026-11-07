import AppKit
import Foundation

// Synthetic pages for the simulator screenshot job; never included in the iOS app.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
func page(_ number: Int) throws -> String {
    let size = NSSize(width: 900, height: 1273)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
    func text(_ value: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor = .black) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
    }
    text("ДЕМОНСТРАЦІЙНИЙ ДОКУМЕНТ", x: 120, y: 1140, font: .boldSystemFont(ofSize: 26))
    text(["ЗАЯВА", "ДОВІДКА", "ВИТЯГ"][number % 3], x: 370, y: 1040, font: .boldSystemFont(ofSize: 28))
    for line in 0..<28 {
        text("Зразок сторінки для перевірки відображення комплекту.", x: 95,
             y: CGFloat(970 - line * 25), font: .systemFont(ofSize: 18))
    }
    let stamp = NSRect(x: 550, y: 120, width: 220, height: 115)
    NSColor.systemBlue.setStroke()
    let border = NSBezierPath(roundedRect: stamp, xRadius: 2, yRadius: 2)
    border.lineWidth = 3; border.stroke()
    text("ЗРАЗОК", x: 600, y: 180, font: .boldSystemFont(ofSize: 23), color: .systemBlue)
    text("Не справжній документ", x: 563, y: 150, font: .systemFont(ofSize: 15), color: .systemBlue)
    image.unlockFocus()
    let name = "preview-\(number).jpg"
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95])!.write(to: root.appendingPathComponent(name))
    return name
}
var docs: [[String: Any]] = []
for (index, title) in ["Ткач_СО_ПКМУ168_донька_Юлія", "Цепліцький_ОЯ_ПКМУ168", "Мельников_СІ_ПКМУ168", "Костенко_МВ_ПКМУ975"].enumerated() {
    var pages: [[String: Any]] = []
    for number in 0..<(index == 0 ? 11 : 3) {
        let file = try page(index * 3 + number % 3)
        pages.append(["id": UUID().uuidString, "original": file, "output": file,
                      "turns": 0, "finish": "Оригінальний", "edgeFill": true,
                      "text": "", "note": "Збережено", "ocrReady": true, "reviewed": true,
                      "sourceKind": "image", "cropVerified": true])
    }
    docs.append(["id": String(format: "00000000-0000-0000-0000-%012d", index + 1),
                 "title": title, "created": Date().timeIntervalSinceReferenceDate - Double(index * 60),
                 "pages": pages, "candidates": [], "nameConfirmed": true])
}
try JSONSerialization.data(withJSONObject: docs).write(to: root.appendingPathComponent("documents.json"))
