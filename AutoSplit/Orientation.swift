import UIKit
import Vision

extension Imaging {
    // Orientation-only raster. Never write this image to the scan or its PDF.
    static func orientationSample(_ image:UIImage) throws -> UIImage {
        guard let cg=resized(image,limit:2400).cgImage else {throw ScanError.message("Не вдалося перевірити напрям тексту")}
        let w=cg.width,h=cg.height
        var pixels=[UInt8](repeating:255,count:w*h*4)
        let flags=CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let valid=pixels.withUnsafeMutableBytes {raw -> Bool in
            guard let context=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:flags) else {return false}
            context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        guard valid else {return UIImage(cgImage:cg)}
        for p in 0..<(w*h) {
            let i=p*4,r=Int(pixels[i]),g=Int(pixels[i+1]),b=Int(pixels[i+2])
            if max(r,max(g,b))-min(r,min(g,b))>35 && (b>r+15 || r>g+20) {
                pixels[i]=255;pixels[i+1]=255;pixels[i+2]=255
            }
        }
        guard let provider=CGDataProvider(data:Data(pixels) as CFData),
              let out=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:flags),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {return UIImage(cgImage:cg)}
        return UIImage(cgImage:out)
    }
    static func orientationReading(_ image:UIImage) throws -> OrientationReading {
        guard let cg=image.cgImage else {return OrientationReading()}
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection=false
        request.minimumTextHeight=0.003
        let languages=try request.supportedRecognitionLanguages()
        let preferred=["uk-UA","ru-RU","en-US"].filter {languages.contains($0)}
        if !preferred.isEmpty {request.recognitionLanguages=preferred}
        request.automaticallyDetectsLanguage=true
        try VNImageRequestHandler(cgImage:cg).perform([request])
        var evidence=OrientationReading()
        for observation in request.results ?? [] {
            let box=observation.boundingBox
            // Circular seals and isolated glyphs are weak direction evidence.
            let aspect=box.width*Double(cg.width)/max(1,box.height*Double(cg.height))
            guard let text=observation.topCandidates(1).first else {continue}
            if aspect>=1.3,text.confidence>=0.3 {evidence.rawScore+=Double(min(100,text.string.filter{$0.isLetter}.count))*pow(Double(text.confidence),2)}
            guard aspect>=2 else {continue}
            let line=OrientationText.line(text.string,confidence:Double(text.confidence))
            evidence.score+=line.score;evidence.anchors+=line.anchors;evidence.lines+=line.lines
        }
        return evidence
    }
}
