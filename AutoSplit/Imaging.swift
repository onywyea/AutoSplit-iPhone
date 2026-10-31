import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

struct OCRResult {
    var image: UIImage
    var text: String
    var confidence: Float
    var warnings: [String]
}
enum Imaging {
    static func rotate(_ image: UIImage, turns: Int) -> UIImage {
        let t = (turns % 4 + 4) % 4
        if t == 0 { return image }
        let size = t % 2 == 1 ? CGSize(width: image.size.height, height: image.size.width) : image.size
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.rotate(by: CGFloat(t) * .pi / 2)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }
    static func resized(_ image: UIImage, limit: CGFloat) -> UIImage {
        let factor = min(1, limit / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
    static func crop(_ image: UIImage) throws -> (UIImage, String?) {
        guard let cg = resized(image, limit: 1800).cgImage else { return (image, "Не вдалося перевірити межі") }
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 4; request.minimumConfidence = 0.85
        request.minimumAspectRatio = 0.3; request.maximumAspectRatio = 1
        request.minimumSize = 0.4; request.quadratureTolerance = 20
        try VNImageRequestHandler(cgImage: cg).perform([request])
        let rectangles = (request.results ?? []).sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }
        guard let rect = rectangles.first else { return (image, "Межі аркуша не визначені — перевірте обрізання") }
        let area = rect.boundingBox.width * rect.boundingBox.height
        if area > 0.94 { return (image, nil) }
        guard area > 0.40 else { return (image, "Аркуш займає мало кадру — потрібна перевірка обрізання") }
        if rectangles.count > 1 {
            let second = rectangles[1].boundingBox
            if second.width * second.height > area * 0.8 {
                return (image, "Кілька можливих меж аркуша — обрізання не застосовано")
            }
        }
        guard let input = CIImage(image: image) else { return (image, "Не вдалося обрізати аркуш") }
        let bounds = input.extent
        func vector(_ point: CGPoint) -> CIVector { CIVector(x: point.x * bounds.width, y: point.y * bounds.height) }
        let filter = CIFilter(name: "CIPerspectiveCorrection")!
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(vector(rect.topLeft), forKey: "inputTopLeft")
        filter.setValue(vector(rect.topRight), forKey: "inputTopRight")
        filter.setValue(vector(rect.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(vector(rect.bottomRight), forKey: "inputBottomRight")
        guard let output = filter.outputImage, let corrected = CIContext().createCGImage(output, from: output.extent) else {
            return (image, "Помилка виправлення перспективи")
        }
        return (UIImage(cgImage: corrected), "Автообрізання застосовано — перевірте, що текст не обрізаний")
    }
    static func recognize(_ image: UIImage, fast: Bool) throws -> (String, Float, Bool) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
        let supported = try request.supportedRecognitionLanguages()
        let preferred = ["uk-UA", "ru-RU", "en-US"].filter { supported.contains($0) }
        if !preferred.isEmpty { request.recognitionLanguages = preferred }
        request.automaticallyDetectsLanguage = true
        guard let cg = resized(image, limit: fast ? 1200 : 2600).cgImage else { throw AppError.message("Пошкоджене зображення") }
        try VNImageRequestHandler(cgImage: cg).perform([request])
        let rows = (request.results ?? []).sorted {
            if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.012 { return $0.boundingBox.midY > $1.boundingBox.midY }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }.compactMap { $0.topCandidates(1).first }
        let mean = rows.isEmpty ? Float(0) : rows.map(\.confidence).reduce(0, +) / Float(rows.count)
        return (rows.map(\.string).joined(separator: "\n"), mean, supported.contains("uk-UA"))
    }
    static func process(_ input: UIImage) throws -> OCRResult {
        let (cropped, cropWarning) = try crop(input)
        // Accurate OCR is used for orientation as well: fast OCR may not support Cyrillic.
        var candidates: [(turn: Int, text: String, confidence: Float, score: Double, uk: Bool)] = []
        for turn in 0..<4 {
            let rotated = rotate(resized(cropped, limit: 1500), turns: turn)
            let result = try recognize(rotated, fast: false)
            let letters = result.0.filter { $0.isLetter }.count
            let score = Double(result.1) * Double(min(letters, 1200))
            candidates.append((turn, result.0, result.1, score, result.2))
        }
        candidates.sort { $0.score > $1.score }
        let best = candidates[0]
        let ambiguous = best.score < 30 || (candidates.count > 1 && candidates[1].score > best.score * 0.9)
        let turns = ambiguous ? 0 : best.turn
        let oriented = rotate(cropped, turns: turns)
        let full = try recognize(oriented, fast: false)
        var warnings = [String]()
        if let cropWarning { warnings.append(cropWarning) }
        if ambiguous { warnings.append("Напрям тексту неоднозначний — автоповорот не застосовано") }
        if !full.2 { warnings.append("Системний OCR не підтримує українську на цьому пристрої; потрібна перевірка тексту") }
        if full.1 < 0.65 { warnings.append("Низька впевненість OCR") }
        return OCRResult(image: oriented, text: full.0, confidence: full.1, warnings: warnings)
    }
}
