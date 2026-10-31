import UIKit
import Vision
import CoreImage

extension Imaging {
    static func cleanRim(_ image:UIImage,automatic:Bool=true,strokes:[CleanupStroke]=[]) throws -> UIImage {
        guard automatic || !strokes.isEmpty,let cg=image.cgImage else {return image}
        let w=cg.width,h=cg.height
        var rgba=[UInt8](repeating:0,count:w*h*4)
        let info=CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ok=rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let context=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:info) else {return false}
            context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        guard ok else {return image}
        // Vision supplies a contour mask, not just the four perspective corners.
        var hint:[UInt8]?=nil
        let request=VNDetectDocumentSegmentationRequest()
        if automatic,let small=resized(image,limit:1600).cgImage {
            try? VNImageRequestHandler(cgImage:small).perform([request])
            if let observation=request.results?.first,observation.confidence>=0.65,
               let buffer=observation.globalSegmentationMask?.pixelBuffer {
                let input=CIImage(cvPixelBuffer:buffer)
                let scaled=input.transformed(by:CGAffineTransform(scaleX:CGFloat(w)/input.extent.width,y:CGFloat(h)/input.extent.height))
                if let maskImage=CIContext().createCGImage(scaled,from:CGRect(x:0,y:0,width:w,height:h)) {
                    var pixels=[UInt8](repeating:0,count:w*h)
                    let valid=pixels.withUnsafeMutableBytes { raw -> Bool in
                        guard let context=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else {return false}
                        context.draw(maskImage,in:CGRect(x:0,y:0,width:w,height:h));return true
                    }
                    if valid {hint=pixels}
                }
            }
        }
        var mask=automatic ? PaperRaster.mask(rgba,width:w,height:h,hint:hint) : [UInt8](repeating:0,count:w*h)
        // No broad "outside document" erasure. Only a small post-crop edge strip
        // may be repaired automatically; explicit brush strokes remain available.
        if automatic {
            let rim=max(2,min(36,Int(Double(min(w,h))*0.015)))
            for y in 0..<h {for x in 0..<w where min(x,min(y,min(w-1-x,h-1-y)))>=rim {mask[y*w+x]=0}}
        }
        if !strokes.isEmpty {
            let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
            let painted=UIGraphicsImageRenderer(size:CGSize(width:w,height:h),format:format).image { renderer in
                let context=renderer.cgContext
                context.setFillColor(UIColor.black.cgColor);context.fill(CGRect(x:0,y:0,width:w,height:h))
                context.setStrokeColor(UIColor.white.cgColor);context.setFillColor(UIColor.white.cgColor)
                context.setLineCap(.round);context.setLineJoin(.round)
                for stroke in strokes {
                    guard let first=stroke.points.first else {continue}
                    let radius=CGFloat(stroke.radius)*CGFloat(min(w,h))
                    context.setLineWidth(radius*2)
                    if stroke.points.count==1 {
                        context.fillEllipse(in:CGRect(x:first.x*Double(w)-Double(radius),y:first.y*Double(h)-Double(radius),width:Double(radius*2),height:Double(radius*2)))
                    } else {
                        context.beginPath();context.move(to:CGPoint(x:first.x*Double(w),y:first.y*Double(h)))
                        for point in stroke.points.dropFirst(){context.addLine(to:CGPoint(x:point.x*Double(w),y:point.y*Double(h)))}
                        context.strokePath()
                    }
                }
            }
            if let paintedCG=painted.cgImage {
                var pixels=[UInt8](repeating:0,count:w*h)
                let valid=pixels.withUnsafeMutableBytes { raw -> Bool in
                    guard let context=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else {return false}
                    context.draw(paintedCG,in:CGRect(x:0,y:0,width:w,height:h));return true
                }
                if valid {for p in 0..<mask.count where pixels[p]>100 {mask[p]=255}}
            }
        }
        // Keep detected dark text inside the automatic mask. Explicit brush marks are user edits.
        if automatic && strokes.isEmpty {
            let text=VNRecognizeTextRequest();text.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage:cg).perform([text])
            for observation in text.results ?? [] {
                let box=observation.boundingBox.insetBy(dx:-0.004,dy:-0.004)
                let x0=max(0,min(w-1,Int(box.minX*Double(w)))),x1=max(0,min(w-1,Int(box.maxX*Double(w))))
                let y0=max(0,min(h-1,Int((1-box.maxY)*Double(h)))),y1=max(0,min(h-1,Int((1-box.minY)*Double(h))))
                guard x0<=x1,y0<=y1 else {continue}
                for y in y0...y1 {for x in x0...x1 {
                    let p=y*w+x,i=p*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
                    if max(r,max(g,b))-min(r,min(g,b))<30 && r+g+b<450 {mask[p]=0}
                }}
            }
        }
        let output=PaperRaster.feathered(rgba,width:w,height:h,mask:mask)
        guard let provider=CGDataProvider(data:Data(output) as CFData),let rendered=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:info),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {return image}
        return UIImage(cgImage:rendered)
    }
}
