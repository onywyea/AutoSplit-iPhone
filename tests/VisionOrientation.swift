// Synthetic document only. No user photos or identifying document data.
import AppKit
import Vision

enum ScanError:Error {case message(String)}
typealias UIImage=NSImage
extension NSImage {
    convenience init(cgImage:CGImage) {self.init(cgImage:cgImage,size:NSSize(width:cgImage.width,height:cgImage.height))}
    var cgImage:CGImage? {cgImage(forProposedRect:nil,context:nil,hints:nil)}
}
enum Imaging {
    static func resized(_ image:NSImage,limit:CGFloat)->NSImage {
        guard let cg=image.cgImage else{return image}
        let factor=min(1,limit/CGFloat(max(cg.width,cg.height)))
        let w=max(1,Int(CGFloat(cg.width)*factor)),h=max(1,Int(CGFloat(cg.height)*factor))
        let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg,in:CGRect(x:0,y:0,width:w,height:h))
        return NSImage(cgImage:ctx.makeImage()!)
    }
    static func rotate(_ image:NSImage,turns:Int)->NSImage {
        guard let cg=image.cgImage else{return image}
        let t=(turns%4+4)%4,w=t%2==0 ? cg.width:cg.height,h=t%2==0 ? cg.height:cg.width
        let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x:CGFloat(w)/2,y:CGFloat(h)/2);ctx.rotate(by:CGFloat(t) * .pi / 2)
        ctx.draw(cg,in:CGRect(x:-CGFloat(cg.width)/2,y:-CGFloat(cg.height)/2,width:CGFloat(cg.width),height:CGFloat(cg.height)))
        return NSImage(cgImage:ctx.makeImage()!)
    }
}
@main struct VisionOrientationChecks {
    static func main() throws {
        let image=NSImage(size:NSSize(width:1600,height:2200))
        image.lockFocus()
        NSColor.white.setFill();NSRect(x:0,y:0,width:1600,height:2200).fill()
        let lines=["КАРТКА ПЛАТНИКА ПОДАТКІВ","Дата народження та місце видачі", "Реєстраційний номер облікової картки", "Дата реєстрації у державному реєстрі", "Орган державної податкової служби", "Посадова особа органу та дата видачі", "Підпис відповідальної особи"]
        let attributes:[NSAttributedString.Key:Any]=[.font:NSFont(name:"TimesNewRomanPSMT",size:25) ?? NSFont.systemFont(ofSize:25),.foregroundColor:NSColor(white:0.5,alpha:1)]
        for (i,line) in lines.enumerated() { (line as NSString).draw(at:NSPoint(x:270,y:CGFloat(1740-i*46)),withAttributes:attributes)}
        NSGraphicsContext.saveGraphicsState()
        let transform=NSAffineTransform();transform.translateX(by:1160,yBy:380);transform.rotate(byDegrees:180);transform.concat()
        ("ЗГІДНО З ОРИГІНАЛОМ" as NSString).draw(at:.zero,withAttributes:[.font:NSFont.boldSystemFont(ofSize:22),.foregroundColor:NSColor.blue])
        ("ДЛЯ ДОВІДОК" as NSString).draw(at:NSPoint(x:0,y:40),withAttributes:[.font:NSFont.systemFont(ofSize:18),.foregroundColor:NSColor.black])
        NSGraphicsContext.restoreGraphicsState();image.unlockFocus()
        let sample=try Imaging.orientationSample(image)
        var readings=[OrientationReading]()
        for turn in 0..<4 {
            let rotated=Imaging.rotate(sample,turns:turn)
            readings.append(try Imaging.orientationReading(rotated,focusBody:true))
            let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.usesLanguageCorrection=true
            request.automaticallyDetectsLanguage=true
            let supported=try request.supportedRecognitionLanguages();request.recognitionLanguages=["uk-UA","ru-RU","en-US"].filter{supported.contains($0)}
            try VNImageRequestHandler(cgImage:rotated.cgImage!).perform([request])
            for line in (request.results ?? []).prefix(3) {
                let text=line.topCandidates(1).first
                if let text,let first=text.string.indices.first(where:{text.string[$0].isLetter}),let last=text.string.indices.last(where:{text.string[$0].isLetter}),
                   let firstBox=try? text.boundingBox(for:first..<text.string.index(after:first)),let lastBox=try? text.boundingBox(for:last..<text.string.index(after:last)) {
                    NSLog("Vision word advance turn %d: dx %.3f dy %.3f",turn,lastBox.boundingBox.midX-firstBox.boundingBox.midX,lastBox.boundingBox.midY-firstBox.boundingBox.midY)
                }
                NSLog("Vision diagnostic turn %d: %@ confidence %.3f dx %.3f dy %.3f",turn,text?.string ?? "",Double(text?.confidence ?? 0),line.topRight.x-line.topLeft.x,line.topRight.y-line.topLeft.y)
            }
        }
        for (i,r) in readings.enumerated() {NSLog("Synthetic Vision turn %d: bodyLines=%d characters=%d score=%.2f anchors=%d",i,r.bodyLines,r.bodyCharacters,r.bodyScore,r.bodyAnchors)}
        for input in 0..<4 {
            let candidates=(0..<4).map {readings[($0+input)%4]}
            let axis=input%2==0 ? TextAxis(horizontal:100,vertical:0,components:100):TextAxis(horizontal:0,vertical:100,components:100)
            let result=OrientationText.choose(candidates,axis:axis,manual:nil)
            guard result.turns==(4-input)%4 else {fatalError("Synthetic Vision orientation failed for turn \(input): got \(result.turns)")}
        }
        print("All four native Vision orientations passed for faint compact text with opposite stamps")
    }
}
