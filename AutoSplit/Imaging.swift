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
    static func recognize(_ image: UIImage, fast: Bool,correction:Bool=true,maxPixel:Int=2600) throws -> (String, Float, Bool) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = fast ? .fast : .accurate
        request.usesLanguageCorrection = !fast && correction
        request.minimumTextHeight = fast ? 0.01 : 0.003
        let supported = try request.supportedRecognitionLanguages()
        let preferred = ["uk-UA", "ru-RU", "en-US"].filter { supported.contains($0) }
        if !preferred.isEmpty { request.recognitionLanguages = preferred }
        request.automaticallyDetectsLanguage = true
        guard let cg = resized(image, limit:CGFloat(fast ? 1200 : maxPixel)).cgImage else { throw ScanError.message("Пошкоджене зображення") }
        try VNImageRequestHandler(cgImage: cg).perform([request])
        let rows = (request.results ?? []).sorted {
            let rowA = Int($0.boundingBox.midY * 100)
            let rowB = Int($1.boundingBox.midY * 100)
            if rowA != rowB { return rowA > rowB }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        var grouped:[[(String,CGRect,Float)]]=[]
        for observation in rows {
            guard let candidate=observation.topCandidates(1).first else {continue}
            let box=observation.boundingBox
            if let last=grouped.last?.first,abs(last.1.midY-box.midY)<min(last.1.height,box.height)*0.45 {
                grouped[grouped.count-1].append((candidate.string,box,candidate.confidence))
            } else {grouped.append([(candidate.string,box,candidate.confidence)])}
        }
        let lines=grouped.map {line in line.sorted {$0.1.minX<$1.1.minX}.map {$0.0}.joined(separator:"   ")}
        let confidence=grouped.flatMap {$0.map {$0.2}}
        let mean=confidence.isEmpty ? Float(0):confidence.reduce(0,+)/Float(confidence.count)
        return (lines.joined(separator:"\n"),mean,supported.contains("uk-UA"))
    }
    static func textAxis(_ image:UIImage)->TextAxis {
        guard let cg=resized(image,limit:1000).cgImage else{return TextAxis(horizontal:0,vertical:0,components:0)}
        let w=cg.width,h=cg.height
        var gray=[UInt8](repeating:255,count:w*h)
        let ok=gray.withUnsafeMutableBytes { raw -> Bool in
            guard let context=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) else{return false}
            context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        return ok ? RasterFlow.estimate(gray,width:w,height:h) : TextAxis(horizontal:0,vertical:0,components:0)
    }

}
