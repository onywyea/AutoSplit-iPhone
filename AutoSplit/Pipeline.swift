import UIKit
import Vision
import CoreImage

struct PageResult { let image: UIImage; let quad: Quad?; let turns: Int; let text: String; let note: String; let cropVerified:Bool;let edgeRepairCount:Int }
struct CapturePreview { let image:UIImage;let quad:Quad;let verified:Bool;let edgeRepairCount:Int }
extension Imaging {
    static func detect(_ image:UIImage) throws -> Quad? {
        guard let cg=resized(image,limit:1600).cgImage else {return nil}
        func point(_ p:CGPoint)->Point {Point(x:Double(p.x),y:Double(1-p.y))}
        func quad(_ r:VNRectangleObservation)->Quad {Quad(points:[point(r.topLeft),point(r.topRight),point(r.bottomRight),point(r.bottomLeft)])}
        var proposals:[(Quad,Double)]=[]
        let document=VNDetectDocumentSegmentationRequest()
        try? VNImageRequestHandler(cgImage:cg).perform([document])
        for observation in document.results ?? [] where observation.confidence>=0.60 {
            proposals.append((quad(observation),Double(observation.confidence)+0.15))
        }
        let rectangles=VNDetectRectanglesRequest()
        rectangles.maximumObservations=24;rectangles.minimumConfidence=0.60;rectangles.minimumSize=0.12
        rectangles.minimumAspectRatio=0.25;rectangles.maximumAspectRatio=1;rectangles.quadratureTolerance=35
        try? VNImageRequestHandler(cgImage:cg).perform([rectangles])
        for observation in rectangles.results ?? [] {proposals.append((quad(observation),Double(observation.confidence)))}
        // Confidence alone accepted internal table frames in earlier versions.
        let text=VNRecognizeTextRequest();text.recognitionLevel = .accurate;text.usesLanguageCorrection=false
        try? VNImageRequestHandler(cgImage:cg).perform([text])
        var content=(text.results ?? []).compactMap {observation -> Quad? in
            guard let candidate=observation.topCandidates(1).first,candidate.confidence>=0.45,candidate.string.filter({$0.isLetter || $0.isNumber}).count>=3 else {return nil}
            let r=observation.boundingBox
            return Quad(points:[point(CGPoint(x:r.minX,y:r.maxY)),point(CGPoint(x:r.maxX,y:r.maxY)),point(CGPoint(x:r.maxX,y:r.minY)),point(CGPoint(x:r.minX,y:r.minY))])
        }
        // Strong blue marks often sit outside a certificate's printed frame.
        // Include them even when OCR cannot read a circular stamp or a signature.
        let w=cg.width,h=cg.height
        var pixels=[UInt8](repeating:0,count:w*h*4)
        pixels.withUnsafeMutableBytes { raw in
            if let context=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) {context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))}
        }
        var count=0,minX=w,minY=h,maxX=0,maxY=0
        for y in 0..<h {for x in 0..<w {
            let i=(y*w+x)*4,r=Int(pixels[i]),g=Int(pixels[i+1]),b=Int(pixels[i+2])
            if b-r>25 && b-g>12 {count+=1;minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)}
        }}
        if count>=25 {
            let l=Double(minX)/Double(w),r=Double(maxX+1)/Double(w),t=Double(minY)/Double(h),b=Double(maxY+1)/Double(h)
            content.append(Quad(points:[Point(x:l,y:t),Point(x:r,y:t),Point(x:r,y:b),Point(x:l,y:b)]))
        }
        let hasContent = !content.isEmpty
        return proposals.filter {CropSafety.usable($0.0,content:content,camera:true)}
            .max {lhs,rhs in
                let la=CropSafety.area(lhs.0),ra=CropSafety.area(rhs.0)
                // A large floor rectangle must not outrank the sheet enclosing all content.
                let ls=hasContent ? lhs.1/sqrt(la):lhs.1*sqrt(la)
                let rs=hasContent ? rhs.1/sqrt(ra):rhs.1*sqrt(ra)
                return ls<rs
            }?.0
    }
    static func cropDecision(_ leaf:Leaf,original:UIImage) throws -> (quad:Quad,verified:Bool) {
        if leaf.manualCrop==true {return (leaf.quad ?? .full,true)}
        // Existing PDF pages already represent complete documents. Never infer
        // a new sheet edge from a certificate border, table or stamp inside them.
        if leaf.sourceKind==nil || leaf.sourceKind=="pdf" {return (.full,true)}
        if leaf.cropVerified==true,let q=leaf.quad,q.valid {return(q,true)}
        if let q=try detect(original) {return(q,true)}
        return(.full,false)
    }
    static func preparedImage(_ leaf:Leaf,original:UIImage,quad:Quad,verified:Bool) throws -> EdgeRepairResult {
        // Manual brush edits are explicit. Automatic repair is restricted to the
        // narrow rim AFTER a verified photo crop, never to the full PDF canvas.
        let brushed=try cleanRim(original,automatic:false,strokes:leaf.cleanupStrokes ?? [])
        let cropped=try perspective(brushed,quad:quad)
        return try repairRim(cropped,automatic:leaf.edgeFill,overlap:leaf.edgeOverlap ?? 0.04)
    }
    static func prepareCapture(_ leaf:Leaf) throws -> CapturePreview {
        guard let original=Disk.image(leaf.original) else {throw ScanError.message("Оригінал відсутній")}
        let decision=try cropDecision(leaf,original:original)
        // Quick review does not run four OCR rotations. It does show the actual
        // detected crop before the thumbnail becomes available.
        let repaired=try preparedImage(leaf,original:original,quad:decision.quad,verified:decision.verified)
        return CapturePreview(image:repaired.image,quad:decision.quad,verified:decision.verified,edgeRepairCount:repaired.changed)
    }
    static func perspective(_ image: UIImage, quad: Quad?) throws -> UIImage {
        guard let quad,quad != .full else { return image }
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
        let crop=try cropDecision(leaf,original:original)
        let quad=crop.quad
        let repaired=try preparedImage(leaf,original:original,quad:quad,verified:crop.verified)
        let cropped=repaired.image
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
        if leaf.edgeFill {notes.append(repaired.changed>0 ? "Край оброблено":"Край перевірено — без змін")}
        if !crop.verified {notes.append("Межі не знайдено — вкажіть кути або перезніміть ближче")}
        if decision.uncertain && leaf.manualTurns == nil { notes.append("Перевірте напрям тексту") }
        if read.1<0.65 { notes.append("Текст розпізнано невпевнено") }
        if !read.2 { notes.append("Системний OCR без uk-UA: перевірте ФІО") }
        return PageResult(image:image,quad:quad,turns:turns,text:read.0,note:notes.joined(separator:" · "),cropVerified:crop.verified,edgeRepairCount:repaired.changed)
    }
    static func render(_ leaf:Leaf) throws -> UIImage {try renderWithEdgeReport(leaf).image}
    static func renderWithEdgeReport(_ leaf:Leaf) throws -> EdgeRepairResult {
        guard let original=Disk.image(leaf.original) else { throw ScanError.message("Оригінал відсутній") }
        let crop=try cropDecision(leaf,original:original)
        let prepared=try preparedImage(leaf,original:original,quad:crop.quad,verified:crop.verified)
        let image=try finish(rotate(prepared.image,turns:leaf.turns),mode:leaf.finish,edgeFill:false)
        return EdgeRepairResult(image:image,changed:prepared.changed)
    }
}
