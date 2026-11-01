import UIKit
import Vision
import CoreImage

struct EdgeRepairResult {let image:UIImage;let changed:Int}
extension Imaging {
    static func cleanRim(_ image:UIImage,automatic:Bool=true,strokes:[CleanupStroke]=[],overlap:Double=0.06,reach:Double=0.08) throws -> UIImage {
        try repairRim(image,automatic:automatic,strokes:strokes,overlap:overlap,reach:reach).image
    }
    static func repairRim(_ image:UIImage,automatic:Bool=true,strokes:[CleanupStroke]=[],overlap:Double=0.06,reach:Double=0.08) throws -> EdgeRepairResult {
        guard automatic || !strokes.isEmpty,let cg=image.cgImage else {return EdgeRepairResult(image:image,changed:0)}
        let w=cg.width,h=cg.height
        var rgba=[UInt8](repeating:0,count:w*h*4)
        let info=CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ok=rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let context=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:info) else {return false}
            context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        guard ok else {return EdgeRepairResult(image:image,changed:0)}
        var mask=automatic ? EdgeBand.mask(rgba,width:w,height:h,bandFraction:reach) : [UInt8](repeating:0,count:w*h)
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
        let changed=mask.reduce(0){$0+($1>0 ? 1:0)}
        guard changed>0 else {return EdgeRepairResult(image:image,changed:0)}
        let radius=Int(Double(min(w,h))*max(0.01,min(0.12,overlap)))
        let output=PaperRaster.feathered(rgba,width:w,height:h,mask:mask,radius:radius)
        guard let provider=CGDataProvider(data:Data(output) as CFData),let rendered=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:info),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {return EdgeRepairResult(image:image,changed:0)}
        return EdgeRepairResult(image:UIImage(cgImage:rendered),changed:changed)
    }
}
