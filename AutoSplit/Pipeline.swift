import UIKit
import Vision
import CoreImage

struct PageResult { let image: UIImage; let quad: Quad?; let turns: Int; let text: String; let note: String }
extension Imaging {
    static func detect(_ image: UIImage) throws -> Quad? {
        guard let cg=resized(image,limit:1600).cgImage else { return nil }
        // Prefer the document model over arbitrary rectangular objects on the table.
        let documentRequest=VNDetectDocumentSegmentationRequest()
        try? VNImageRequestHandler(cgImage:cg).perform([documentRequest])
        if let document=documentRequest.results?.first,document.confidence>=0.65 {
            func point(_ p:CGPoint)->Point { .init(x:Double(p.x),y:Double(1-p.y)) }
            let quad=Quad(points:[point(document.topLeft),point(document.topRight),point(document.bottomRight),point(document.bottomLeft)])
            if quad.valid { return quad }
        }
        let r=VNDetectRectanglesRequest()
        r.maximumObservations=6; r.minimumConfidence=0.70; r.minimumAspectRatio=0.25
        r.maximumAspectRatio=1; r.minimumSize=0.25; r.quadratureTolerance=30
        try VNImageRequestHandler(cgImage:cg).perform([r])
        let rects=(r.results ?? []).filter { $0.boundingBox.width * $0.boundingBox.height > 0.18 }
        guard let best=rects.max(by: { lhs,rhs in lhs.boundingBox.width*lhs.boundingBox.height*CGFloat(lhs.confidence) < rhs.boundingBox.width*rhs.boundingBox.height*CGFloat(rhs.confidence) }) else { return nil }
        func p(_ point:CGPoint)->Point { .init(x:Double(point.x),y:Double(1-point.y)) }
        let q=Quad(points:[p(best.topLeft),p(best.topRight),p(best.bottomRight),p(best.bottomLeft)])
        return q.valid ? q : nil
    }
    static func perspective(_ image: UIImage, quad: Quad?) throws -> UIImage {
        guard let quad else { return image }
        guard quad.valid,let input=CIImage(image:image),let filter=CIFilter(name:"CIPerspectiveCorrection") else { throw ScanError.message("Угли перетинаються або область надто мала") }
        let e=input.extent
        func v(_ i:Int)->CIVector { CIVector(x:quad.points[i].x*e.width,y:(1-quad.points[i].y)*e.height) }
        filter.setValue(input,forKey:kCIInputImageKey)
        for (key,index) in [("inputTopLeft",0),("inputTopRight",1),("inputBottomRight",2),("inputBottomLeft",3)] { filter.setValue(v(index),forKey:key) }
        guard let out=filter.outputImage,let cg=CIContext().createCGImage(out,from:out.extent) else { throw ScanError.message("Не вдалося виправити перспективу") }
        return UIImage(cgImage:cg)
    }
    static func finish(_ image:UIImage, mode:Finish, edgeFill:Bool) throws -> UIImage {
        var image=image
        if mode != .natural,let input=CIImage(image:image) {
            let filter=CIFilter(name:"CIColorControls")!
            filter.setValue(input,forKey:kCIInputImageKey)
            filter.setValue(mode == .mono ? 0 : 0.88,forKey:kCIInputSaturationKey)
            filter.setValue(mode == .mono ? 1.35 : 1.06,forKey:kCIInputContrastKey)
            filter.setValue(0.025,forKey:kCIInputBrightnessKey)
            if let out=filter.outputImage,let cg=CIContext().createCGImage(out,from:out.extent) { image=UIImage(cgImage:cg) }
        }
        return edgeFill ? try cleanRim(image) : image
    }
    static func cleanRim(_ image:UIImage) throws -> UIImage {
        guard let cg=image.cgImage else { return image }
        let w=cg.width,h=cg.height
        var bytes=[UInt8](repeating:0,count:w*h*4)
        let ok=bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            ctx.draw(cg,in:CGRect(x:0,y:0,width:w,height:h)); return true
        }
        guard ok else { return image }
        // Protect recognized text even near page edges. Original is always kept for undo.
        let request=VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage:cg).perform([request])
        let protected=(request.results ?? []).map { $0.boundingBox.insetBy(dx:-0.008,dy:-0.008) }
        var samples=[[Int]](repeating:[],count:3)
        for fy in [0.06,0.12,0.88,0.94] {
            for fx in stride(from:0.07,through:0.93,by:0.043) {
                let x=min(w-1,Int(Double(w)*fx)),y=min(h-1,Int(Double(h)*fy)),i=(y*w+x)*4
                let brightness=(Int(bytes[i])+Int(bytes[i+1])+Int(bytes[i+2]))/3
                if brightness>160 { for c in 0..<3 { samples[c].append(Int(bytes[i+c])) } }
            }
        }
        guard samples[0].count>15 else { return image }
        let paper=samples.map { $0.sorted()[$0.count/2] }
        let rim=min(18,max(2,Int(Double(min(w,h))*0.009)))
        for y in 0..<h {
            for x in 0..<w where x<rim || y<rim || x>=w-rim || y>=h-rim {
                // CGContext memory uses lower-left coordinates, matching Vision.
                let point=CGPoint(x:Double(x)/Double(w),y:Double(y)/Double(h))
                if protected.contains(where:{$0.contains(point) || $0.contains(CGPoint(x:point.x,y:1-point.y))}) { continue }
                let i=(y*w+x)*4
                let difference=(0..<3).map { abs(Int(bytes[i+$0])-paper[$0]) }.max() ?? 0
                if difference>45 {
                    for c in 0..<3 { bytes[i+c]=UInt8(paper[c]) }; bytes[i+3]=255
                }
            }
        }
        guard let provider=CGDataProvider(data:Data(bytes) as CFData),let output=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else { return image }
        return UIImage(cgImage:output)
    }
    static func process(_ leaf:Leaf) throws -> PageResult {
        guard let original=Disk.image(leaf.original) else { throw ScanError.message("Не знайдено оригінал сторінки") }
        let quad=try leaf.quad ?? detect(original)
        let cropped=try perspective(original,quad:quad)
        var scores:[(Int,Double)] = []
        for turn in 0..<4 {
            let read=try recognize(rotate(resized(cropped,limit:1400),turns:turn),fast:false)
            scores.append((turn,Double(read.1)*Double(min(1400,read.0.filter(\.isLetter).count))))
        }
        scores.sort { $0.1 > $1.1 }
        let ambiguous=scores[0].1<25 || scores[1].1>scores[0].1*0.92
        let turns=leaf.turns != 0 ? leaf.turns : (ambiguous ? 0 : scores[0].0)
        let image=try finish(rotate(cropped,turns:turns),mode:leaf.finish,edgeFill:leaf.edgeFill)
        let read=try recognize(image,fast:false)
        var notes:[String] = []
        if quad == nil { notes.append("Потрібно вказати кути аркуша") }
        if ambiguous && leaf.turns == 0 { notes.append("Перевірте напрям тексту") }
        if read.1<0.65 { notes.append("Текст розпізнано невпевнено") }
        if !read.2 { notes.append("Системний OCR без uk-UA: перевірте ФІО") }
        return PageResult(image:image,quad:quad,turns:turns,text:read.0,note:notes.joined(separator:" · "))
    }
    static func render(_ leaf:Leaf) throws -> UIImage {
        guard let original=Disk.image(leaf.original) else { throw ScanError.message("Оригінал відсутній") }
        return try finish(rotate(perspective(original,quad:leaf.quad),turns:leaf.turns),mode:leaf.finish,edgeFill:leaf.edgeFill)
    }
}
