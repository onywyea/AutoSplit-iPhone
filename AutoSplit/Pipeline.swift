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
        for observation in document.results ?? [] where observation.confidence>=0.45 {
            proposals.append((quad(observation),Double(observation.confidence)+0.8))
        }
        let rectangles=VNDetectRectanglesRequest()
        rectangles.maximumObservations=24;rectangles.minimumConfidence=0.50;rectangles.minimumSize=0.10
        rectangles.minimumAspectRatio=0.25;rectangles.maximumAspectRatio=1;rectangles.quadratureTolerance=35
        try? VNImageRequestHandler(cgImage:cg).perform([rectangles])
        for observation in rectangles.results ?? [] {proposals.append((quad(observation),Double(observation.confidence)))}
        // Validate the physical paper/background transition locally at the
        // proposed edges. Blue objects and OCR elsewhere in the photo cannot
        // veto an otherwise valid sheet. An internal table has paper on BOTH
        // sides, so it does not pass this boundary check.
        let w=cg.width,h=cg.height
        var pixels=[UInt8](repeating:0,count:w*h*4)
        let ok=pixels.withUnsafeMutableBytes {raw -> Bool in
            let flags=CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            guard let context=CGContext(data:raw.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:flags) else {return false}
            context.draw(cg,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        guard ok else {return nil}
        func paperValue(_ x:Double,_ y:Double)->Double? {
            guard x>=0,y>=0,x<Double(w),y<Double(h) else {return nil}
            let index=(Int(y)*w+Int(x))*4
            let r=Double(pixels[index]),g=Double(pixels[index+1]),b=Double(pixels[index+2])
            let light=(r+g+b)/3.0
            let spread=max(r,max(g,b))-min(r,min(g,b))
            return light-1.3*spread
        }
        func boundary(_ q:Quad)->Double? {
            guard CropSafety.usable(q,content:[],camera:true) else {return nil}
            let step=max(3.0,Double(min(w,h))*0.012)
            var contrasts:[Double]=[]
            for side in 0..<4 {
                let a=q.points[side],b=q.points[(side+1)%4]
                let ax=a.x*Double(w),ay=a.y*Double(h)
                let dx=(b.x-a.x)*Double(w),dy=(b.y-a.y)*Double(h)
                let length=hypot(dx,dy)
                guard length>1 else {continue}
                let nx = -dy/length,ny=dx/length
                var votes:[Double]=[]
                for sample in 2...18 {
                    let t=Double(sample)/20.0
                    let x=ax+dx*t,y=ay+dy*t
                    if let inside=paperValue(x+nx*step,y+ny*step),
                       let outside=paperValue(x-nx*step,y-ny*step) {
                        votes.append(inside-outside)
                    }
                }
                if votes.count>=9 {votes.sort();contrasts.append(votes[votes.count/2])}
            }
            let strong=contrasts.filter {$0>=12.0}.count
            guard contrasts.count>=3,strong>=3 else {return nil}
            return contrasts.reduce(0.0,+)/Double(contrasts.count)
        }
        // An additional detector input separates neutral paper from warm wood.
        // This creates PROPOSALS only; every proposal must pass the original
        // color-image boundary check above before it can crop anything.
        var mask=[UInt8](repeating:0,count:w*h)
        for pixel in 0..<(w*h) {
            let base=pixel*4
            let r=Int(pixels[base]),g=Int(pixels[base+1]),b=Int(pixels[base+2])
            let light=(r+g+b)/3
            let spread=max(r,max(g,b))-min(r,min(g,b))
            if light>=130 && spread<=max(24,light/6) {mask[pixel]=255}
        }
        if let provider=CGDataProvider(data:Data(mask) as CFData),
           let paper=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:w,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) {
            let edges=VNDetectRectanglesRequest()
            edges.maximumObservations=24;edges.minimumConfidence=0.35;edges.minimumSize=0.10
            edges.minimumAspectRatio=0.25;edges.maximumAspectRatio=1;edges.quadratureTolerance=35
            try? VNImageRequestHandler(cgImage:paper).perform([edges])
            for observation in edges.results ?? [] {proposals.append((quad(observation),Double(observation.confidence)))}
        }
        var best:Quad?
        var bestScore = -Double.infinity
        for proposal in proposals {
            guard let edge=boundary(proposal.0) else {continue}
            let area=CropSafety.area(proposal.0)
            let score=edge+proposal.1*10.0+sqrt(area)*10.0
            if score>bestScore {best=proposal.0;bestScore=score}
        }
        return best
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
        var cropped=try perspective(brushed,quad:quad)
        // Auto-detected photo corners can land on the physical contact edge.
        // Remove a six-pixel guard at typical scan resolution before filtering.
        // Always render from the saved original: this never accumulates on edits.
        let photo=leaf.sourceKind=="camera" || leaf.sourceKind=="image"
        if verified && photo && leaf.manualCrop != true && leaf.edgeFill,let cg=cropped.cgImage {
            let guardPixels=max(2,min(8,Int(Double(min(cg.width,cg.height))*0.004)))
            let bounds=CGRect(x:guardPixels,y:guardPixels,width:cg.width-guardPixels*2,height:cg.height-guardPixels*2)
            if let inner=cg.cropping(to:bounds) {cropped=UIImage(cgImage:inner)}
        }
        // Find wood/contact shadows in original color, before lighting can bleach the evidence.
        let repaired=try repairRim(cropped,automatic:leaf.edgeFill && verified,overlap:leaf.edgeOverlap ?? 0.06,reach:leaf.edgeReach ?? 0.08)
        cropped=repaired.image
        if leaf.finish == .white && verified {cropped=try correctPaperLighting(cropped)}
        return EdgeRepairResult(image:cropped,changed:repaired.changed)
    }
    static func prepareCapture(_ leaf:Leaf) throws -> CapturePreview {
        guard let original=Disk.image(leaf.original) else {throw ScanError.message("Оригінал відсутній")}
        let decision=try cropDecision(leaf,original:original)
        // Quick review does not run four OCR rotations. It does show the actual
        // detected crop before the thumbnail becomes available.
        let repaired=try preparedImage(leaf,original:original,quad:decision.quad,verified:decision.verified)
        let final=try finishPage(repaired.image,leaf:leaf,verified:decision.verified)
        return CapturePreview(image:final.image,quad:decision.quad,verified:decision.verified,edgeRepairCount:repaired.changed+final.changed)
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
    static func finishPage(_ image:UIImage,leaf:Leaf,verified:Bool) throws -> EdgeRepairResult {
        let amount=leaf.sharpness ?? ((leaf.finish == .white || leaf.finish == .clean) ? 0.85:0)
        let ink=leaf.inkStrength ?? ((leaf.finish == .white || leaf.finish == .clean) ? 0.75:0)
        let contrast=ink>0 ? try enhanceDocumentInk(image,amount:ink):image
        let filtered=try finish(contrast,mode:verified ? leaf.finish:.natural,edgeFill:false,sharpness:amount)
        // Last pixel operation: no later sharpening can restore a removed hairline.
        return leaf.edgeFill && verified ? try sealRim(filtered):EdgeRepairResult(image:filtered,changed:0)
    }
    static func finish(_ image:UIImage, mode:Finish, edgeFill:Bool,sharpness:Double=0.85) throws -> UIImage {
        var image=image
        // White-color correction is applied once, after crop and before edge
        // repair in preparedImage. Avoid stacking the old enhancer over it.
        if mode != .natural && mode != .white,let input=CIImage(image:image) {
            let filter=CIFilter(name:"CIColorControls")!
            filter.setValue(input,forKey:kCIInputImageKey)
            filter.setValue(mode == .mono ? 0 : 1.0,forKey:kCIInputSaturationKey)
            filter.setValue(mode == .mono ? 1.35 : 1.0,forKey:kCIInputContrastKey)
            filter.setValue(0.025,forKey:kCIInputBrightnessKey)
            if let out=filter.outputImage,let cg=CIContext().createCGImage(out,from:out.extent) { image=UIImage(cgImage:cg) }
        }
        if sharpness>0 {image=try enhanceDocumentDetail(image,amount:sharpness)}
        return edgeFill ? try cleanRim(image) : image
    }
    static func enhanceDocumentDetail(_ image:UIImage,amount:Double=0.85) throws -> UIImage {
        guard let cg=image.cgImage else {return image}
        let width=cg.width,height=cg.height
        var rgba=[UInt8](repeating:0,count:width*height*4)
        let flags=CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let valid=rgba.withUnsafeMutableBytes {raw -> Bool in
            guard let context=CGContext(data:raw.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:flags) else {return false}
            context.draw(cg,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard valid else {throw ScanError.message("Не вдалося прочитати деталі сторінки")}
        let corrected=DocumentDetail.enhance(rgba,width:width,height:height,amount:amount)
        guard let provider=CGDataProvider(data:Data(corrected) as CFData),
              let out=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:flags),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {throw ScanError.message("Не вдалося записати чіткість сторінки")}
        return UIImage(cgImage:out)
    }
    static func enhanceDocumentInk(_ image:UIImage,amount:Double=0.75) throws -> UIImage {
        guard let cg=image.cgImage else {return image}
        let width=cg.width,height=cg.height
        var rgba=[UInt8](repeating:0,count:width*height*4)
        let flags=CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let valid=rgba.withUnsafeMutableBytes {raw -> Bool in
            guard let context=CGContext(data:raw.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:flags) else {return false}
            context.draw(cg,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard valid else {throw ScanError.message("Не вдалося прочитати контраст сторінки")}
        let corrected=DocumentInk.enhance(rgba,amount:amount)
        guard let provider=CGDataProvider(data:Data(corrected) as CFData),
              let out=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:flags),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {throw ScanError.message("Не вдалося записати контраст сторінки")}
        return UIImage(cgImage:out)
    }
    static func correctPaperLighting(_ image:UIImage) throws -> UIImage {
        guard let cg=image.cgImage else {return image}
        let width=cg.width,height=cg.height
        var rgba=[UInt8](repeating:0,count:width*height*4)
        let flags=CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let valid=rgba.withUnsafeMutableBytes {raw -> Bool in
            guard let context=CGContext(data:raw.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:flags) else {return false}
            context.draw(cg,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard valid else {throw ScanError.message("Не вдалося прочитати освітлення аркуша")}
        let corrected=PaperLighting.correct(rgba,width:width,height:height)
        guard let provider=CGDataProvider(data:Data(corrected) as CFData),
              let output=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:flags),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {
            throw ScanError.message("Не вдалося записати корекцію освітлення")
        }
        return UIImage(cgImage:output)
    }
    static func process(_ leaf:Leaf,seekName:Bool=false) throws -> PageResult {
        guard let original=Disk.image(leaf.original,limit:8192) else { throw ScanError.message("Не знайдено оригінал сторінки") }
        let crop=try cropDecision(leaf,original:original)
        let quad=crop.quad
        let repaired=try preparedImage(leaf,original:original,quad:quad,verified:crop.verified)
        let cropped=repaired.image
        let axis=textAxis(cropped)
        var readings=[OrientationReading](repeating:OrientationReading(),count:4)
        let candidates=axis.reliable ? (axis.evidence>0 ? [0,2] : [1,3]) : [0,1,2,3]
        if leaf.manualTurns==nil {
            let sample=try orientationSample(cropped)
            for turn in candidates {readings[turn]=try orientationReading(rotate(sample,turns:turn))}
            if (readings.map(\.anchors).max() ?? 0)<3 {
                for turn in 0..<4 where !candidates.contains(turn) {readings[turn]=try orientationReading(rotate(sample,turns:turn))}
            }
        }
        var decision=OrientationText.choose(readings,axis:axis,manual:leaf.manualTurns)
        if leaf.manualTurns==nil,decision.uncertain {
            let sample=try orientationSample(cropped)
            for turn in candidates {readings[turn]=try orientationReading(rotate(sample,turns:turn),focusBody:true)}
            decision=OrientationText.choose(readings,axis:axis,manual:nil)
        }
        let turns=decision.turns
        let final=try finishPage(rotate(cropped,turns:turns),leaf:leaf,verified:crop.verified)
        let image = try PageTrim.apply(final.image, rect: leaf.outputTrim, turns: turns)
        var read=try recognize(image,fast:false,maxPixel:seekName ? 3400:2600)
        // Only retry the naming page. Raw paper can retain faint letters lost by
        // the visual filter; this OCR pass never changes the displayed image.
        if seekName, leaf.outputTrim == nil,NameFinder.candidates(read.0).isEmpty {
            let raw=rotate(try perspective(original,quad:quad),turns:turns)
            let fallback=try recognize(raw,fast:false,correction:false,maxPixel:3400)
            if !fallback.0.isEmpty {
                read=(read.0+"\n"+fallback.0,max(read.1,fallback.1),read.2 || fallback.2)
            }
        }
        var notes:[String] = []
        if leaf.edgeFill {notes.append(repaired.changed+final.changed>0 ? "Край оброблено":"Край перевірено — без змін")}
        if !crop.verified {notes.append("Межі не знайдено — вкажіть кути або перезніміть ближче")}
        if decision.uncertain && leaf.manualTurns == nil { notes.append("Перевірте напрям тексту") }
        if read.1<0.65 { notes.append("Текст розпізнано невпевнено") }
        if !read.2 { notes.append("Системний OCR без uk-UA: перевірте ПІБ") }
        return PageResult(image:image,quad:quad,turns:turns,text:read.0,note:notes.joined(separator:" · "),cropVerified:crop.verified,edgeRepairCount:repaired.changed+final.changed)
    }
    static func render(_ leaf:Leaf) throws -> UIImage {try renderWithEdgeReport(leaf).image}
    static func renderWithEdgeReport(_ leaf:Leaf) throws -> EdgeRepairResult {
        guard let original=Disk.image(leaf.original,limit:8192) else { throw ScanError.message("Оригінал відсутній") }
        let crop=try cropDecision(leaf,original:original)
        let prepared=try preparedImage(leaf,original:original,quad:crop.quad,verified:crop.verified)
        let final=try finishPage(rotate(prepared.image,turns:leaf.turns),leaf:leaf,verified:crop.verified)
        let image = try PageTrim.apply(final.image, rect: leaf.outputTrim, turns: leaf.turns)
        return EdgeRepairResult(image:image,changed:prepared.changed+final.changed)
    }
}
