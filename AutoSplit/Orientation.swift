#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
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
    static func orientationReading(_ image:UIImage,focusBody:Bool=false) throws -> OrientationReading {
        guard let cg=image.cgImage else {return OrientationReading()}
        let request=VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection=true
        request.minimumTextHeight=0.001
        let languages=try request.supportedRecognitionLanguages()
        let preferred=["uk-UA","ru-RU","en-US"].filter {languages.contains($0)}
        if !preferred.isEmpty {request.recognitionLanguages=preferred}
        request.automaticallyDetectsLanguage=true
        try VNImageRequestHandler(cgImage:cg).perform([request])
        var lines:[OrientationLine]=[]
        for observation in request.results ?? [] {
            guard let text=observation.topCandidates(1).first else {continue}
            let box=observation.boundingBox
            // Vision may recognize a reversed string confidently. Compare the
            // first and last word locations, rather than confidence alone.
            let string=text.string
            if let first=string.indices.first(where:{string[$0].isLetter}),
               let last=string.indices.last(where:{string[$0].isLetter}),first != last,
               let firstBox=try? text.boundingBox(for:first..<string.index(after:first)),
               let lastBox=try? text.boundingBox(for:last..<string.index(after:last)) {
                let advanceX=(lastBox.boundingBox.midX-firstBox.boundingBox.midX)*Double(cg.width)
                let advanceY=(lastBox.boundingBox.midY-firstBox.boundingBox.midY)*Double(cg.height)
                let separated=hypot(advanceX,advanceY)>max(2,box.width*Double(cg.width)*0.12)
                if separated && (advanceX<=0 || abs(advanceY)>advanceX*0.35) {continue}
            }
            let dx=abs(observation.topRight.x-observation.topLeft.x)
            let dy=abs(observation.topRight.y-observation.topLeft.y)
            // Curved seal lettering is not a straight printed line.
            guard dy<=max(0.001,dx)*0.24 else {continue}
            lines.append(OrientationLine(region:OrientationRegion(x:box.minX,y:box.minY,width:box.width,height:box.height),text:text.string,confidence:Double(text.confidence)))
        }
        var evidence=OrientationBlocks.reading(lines,aspect:Double(cg.width)/Double(cg.height))
        if focusBody,let b=evidence.bodyRegion,b.width*b.height<0.55,b.width>0.02,b.height>0.02 {
            let margin=0.012
            let x=max(0,b.x-margin),y=max(0,1-b.y-b.height-margin)
            let bounds=CGRect(x:x*Double(cg.width),y:y*Double(cg.height),width:min(1-x,b.width+margin*2)*Double(cg.width),height:min(1-y,b.height+margin*2)*Double(cg.height)).integral
            if let crop=cg.cropping(to:bounds) {
                let factor=min(3,2400/CGFloat(max(crop.width,crop.height)))
                let width=max(1,Int(CGFloat(crop.width)*factor)),height=max(1,Int(CGFloat(crop.height)*factor))
                let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)
                context?.interpolationQuality = .high
                context?.draw(crop,in:CGRect(x:0,y:0,width:width,height:height))
                guard let enlarged=context?.makeImage() else {return evidence}
                let zoom=try orientationReading(UIImage(cgImage:enlarged))
                if zoom.bodyScore>evidence.bodyScore {evidence=zoom}
            }
        }
        return evidence
    }
}
