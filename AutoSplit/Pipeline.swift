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
    static func process(_ leaf:Leaf) throws -> PageResult {
        guard let original=Disk.image(leaf.original) else { throw ScanError.message("Не знайдено оригінал сторінки") }
        let quad=try leaf.quad ?? detect(original)
        let prepared=try cleanRim(original,automatic:leaf.edgeFill,strokes:leaf.cleanupStrokes ?? [])
        let cropped=try perspective(prepared,quad:quad)
        let axis=textAxis(cropped)
        var scores=[Double](repeating:0,count:4)
        let candidates=axis.reliable ? (axis.evidence>0 ? [0,2] : [1,3]) : [0,1,2,3]
        for turn in candidates where leaf.manualTurns == nil {
            let read=try recognize(rotate(resized(cropped,limit:2200),turns:turn),fast:false)
            scores[turn]=Double(read.1)*Double(min(3000,read.0.filter(\.isLetter).count))
        }
        let decision=RasterAxis.choose(scores:scores,axis:axis,manual:leaf.manualTurns)
        let turns=decision.turns
        let image=try finish(rotate(cropped,turns:turns),mode:leaf.finish,edgeFill:false)
        let read=try recognize(image,fast:false)
        var notes:[String] = []
        if quad == nil { notes.append("Потрібно вказати кути аркуша") }
        if decision.uncertain && leaf.manualTurns == nil { notes.append("Перевірте напрям тексту") }
        if read.1<0.65 { notes.append("Текст розпізнано невпевнено") }
        if !read.2 { notes.append("Системний OCR без uk-UA: перевірте ФІО") }
        return PageResult(image:image,quad:quad,turns:turns,text:read.0,note:notes.joined(separator:" · "))
    }
    static func render(_ leaf:Leaf) throws -> UIImage {
        guard let original=Disk.image(leaf.original) else { throw ScanError.message("Оригінал відсутній") }
        let prepared=try cleanRim(original,automatic:leaf.edgeFill,strokes:leaf.cleanupStrokes ?? [])
        return try finish(rotate(perspective(prepared,quad:leaf.quad),turns:leaf.turns),mode:leaf.finish,edgeFill:false)
    }
}
