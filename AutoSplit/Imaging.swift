import UIKit
import Vision
import CoreImage

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
    static func recognize(_ image: UIImage, fast: Bool) throws -> (String, Float, Bool) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast
        let supported = try request.supportedRecognitionLanguages()
        let preferred = ["uk-UA", "ru-RU", "en-US"].filter { supported.contains($0) }
        if !preferred.isEmpty { request.recognitionLanguages = preferred }
        request.automaticallyDetectsLanguage = true
        guard let cg = resized(image, limit: fast ? 1200 : 2600).cgImage else { throw ScanError.message("Пошкоджене зображення") }
        try VNImageRequestHandler(cgImage: cg).perform([request])
        let rows = (request.results ?? []).sorted {
            let rowA = Int($0.boundingBox.midY * 100)
            let rowB = Int($1.boundingBox.midY * 100)
            if rowA != rowB { return rowA > rowB }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }.compactMap { $0.topCandidates(1).first }
        let mean = rows.isEmpty ? Float(0) : rows.map(\.confidence).reduce(0, +) / Float(rows.count)
        return (rows.map(\.string).joined(separator: "\n"), mean, supported.contains("uk-UA"))
    }
}
