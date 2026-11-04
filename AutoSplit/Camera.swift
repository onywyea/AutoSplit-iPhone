import SwiftUI
import AVFoundation
import Vision
import CoreImage
import ImageIO

struct CameraLens:Identifiable,Equatable {
    let id:String
    let title:String
}

final class CameraEngine: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session=AVCaptureSession()
    private let queue=DispatchQueue(label:"scan.camera")
    private let frames=DispatchQueue(label:"scan.edges")
    private let output=AVCapturePhotoOutput()
    private var camera:AVCaptureDevice?
    private var cameraInput:AVCaptureDeviceInput?
    private var lensDevices:[AVCaptureDevice]=[]
    private var changingLens=false
    private var exposureBias:Float=0.3
    // Camera queue owns writes; frame queue reads this under processingLock.
    private var seriesFocus=(UserDefaults.standard.object(forKey:"scanflow.seriesFocus") as? Bool) ?? true
    @Published var seriesFocusEnabled=(UserDefaults.standard.object(forKey:"scanflow.seriesFocus") as? Bool) ?? true
    private var needsDocumentFocus=true
    @Published var framingHint=""
    private var captureAllowedAfter=Date.distantPast
    @Published var lenses:[CameraLens]=[]
    @Published var selectedLensID=""
    @Published var switchingLens=false
    private let processingLock=NSLock()
    private var processing=false
    @Published var preparing=false
    private var configured=false
    private var capturing=false
    private var lastTime=Date.distantPast
    private var tracker=CaptureStability()
    private var qualityHold=LensSettleHold()
    private var qualityReadyAt=Date.distantPast
    private var readyLensPosition:Float=0
    private var readyDeviceID=""
    @Published var focusStatus="Перевіряю фокус…"
    @Published var focusReady=false
    @Published var focusLocked=false
    private var lastSegmentation=Date.distantPast
    private var runningWanted=false
    private let imageContext=CIContext()
    private var auto=true
    private var useFlash=true
    private var ignoreFramesUntil=Date.distantPast
    @Published var message="Наведіть камеру на аркуш"
    @Published var detected=false
    @Published var shooting=false
    @Published var flashEnabled=true
    @Published var flashSupported=false
    @Published var detectedQuad:Quad?
    @Published var frameAspect:CGFloat=0.75
    @Published var brightness=0.3
    @Published var lastFlashFired:Bool?
    var captured:((UIImage)->Void)?
    func start() {
        queue.async {self.runningWanted=true}
        AVCaptureDevice.requestAccess(for:.video) { [weak self] granted in
            guard let self else { return }
            guard granted else { DispatchQueue.main.async { self.message="Дозвольте камеру в Налаштуваннях iPhone → ScanFlow" }; return }
            self.queue.async {
                guard self.runningWanted else {return}
                do {
                    if !self.configured {
                        self.session.beginConfiguration(); self.session.sessionPreset = .photo
                        let discovery=AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInUltraWideCamera,.builtInWideAngleCamera,.builtInTelephotoCamera],mediaType:.video,position:.back)
                        self.lensDevices=discovery.devices
                        let saved=UserDefaults.standard.string(forKey:"scanflow.cameraLens")
                        let preferred=self.lensDevices.first(where:{$0.uniqueID==saved})
                        let normal=self.lensDevices.first(where:{$0.deviceType == .builtInWideAngleCamera})
                        guard let device=preferred ?? normal ?? self.lensDevices.first else { throw ScanError.message("Камера недоступна") }
                        self.processingLock.lock();self.camera=device;self.processingLock.unlock()
                        try device.lockForConfiguration()
                        self.configureFocus(device,series:self.seriesFocus,waitForDocument:true)
                        if device.isExposureModeSupported(.continuousAutoExposure) {device.exposureMode = .continuousAutoExposure}
                        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {device.whiteBalanceMode = .continuousAutoWhiteBalance}
                        device.setExposureTargetBias(min(device.maxExposureTargetBias,max(device.minExposureTargetBias,0.3)),completionHandler:nil)
                        device.unlockForConfiguration()
                        let input=try AVCaptureDeviceInput(device:device)
                        guard self.session.canAddInput(input),self.session.canAddOutput(self.output) else { throw ScanError.message("Не вдалося налаштувати камеру") }
                        self.session.addInput(input);self.cameraInput=input; self.session.addOutput(self.output)
                        self.output.maxPhotoQualityPrioritization = .quality
                        self.configurePhotoDimensions(device)
                        let video=AVCaptureVideoDataOutput(); video.alwaysDiscardsLateVideoFrames=true
                        video.setSampleBufferDelegate(self,queue:self.frames)
                        if self.session.canAddOutput(video) { self.session.addOutput(video) }
                        for connection in [video.connection(with:.video),self.output.connection(with:.video)].compactMap({$0}) {
                            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle=90 }
                        }
                        self.session.commitConfiguration(); self.configured=true
                    }
                    self.captureAllowedAfter=Date().addingTimeInterval(0.7)
                    self.frames.async {self.qualityHold.reset();self.tracker.resetStability()}
                    self.session.startRunning()
                    self.publishLenses()
                } catch {
                    if !self.configured { self.session.commitConfiguration() }
                    DispatchQueue.main.async { self.message=error.localizedDescription }
                }
            }
        }
    }
    private var processingNow:Bool {processingLock.lock();defer {processingLock.unlock()};return processing || changingLens}
    private func publishLenses() {
        var choices:[CameraLens]=[]
        for type in [AVCaptureDevice.DeviceType.builtInUltraWideCamera,.builtInWideAngleCamera,.builtInTelephotoCamera] {
            for device in lensDevices where device.deviceType==type {
                let title:String
                if type == .builtInUltraWideCamera {title="Ультраширококутна"}
                else if type == .builtInTelephotoCamera {title="Телеоб’єктив"}
                else {title="Основна"}
                choices.append(CameraLens(id:device.uniqueID,title:title))
            }
        }
        let id=camera?.uniqueID ?? ""
        let supported=camera?.hasFlash == true && output.supportedFlashModes.contains(.on)
        DispatchQueue.main.async {self.lenses=choices;self.selectedLensID=id;self.flashSupported=supported;self.lastFlashFired=nil}
    }
    // Must be called with the device configuration lock on the camera queue.
    private func configureFocus(_ device:AVCaptureDevice,series:Bool,point:CGPoint=CGPoint(x:0.5,y:0.5),waitForDocument:Bool=false) {
        if device.isFocusPointOfInterestSupported {device.focusPointOfInterest=point}
        if waitForDocument && series && device.isFocusModeSupported(.continuousAutoFocus) {device.focusMode = .continuousAutoFocus}
        else if series && device.isFocusModeSupported(.autoFocus) {device.focusMode = .autoFocus}
        else if !series && device.isFocusModeSupported(.continuousAutoFocus) {device.focusMode = .continuousAutoFocus}
        else if series && device.isFocusModeSupported(.continuousAutoFocus) {device.focusMode = .continuousAutoFocus}
        else if device.isFocusModeSupported(.autoFocus) {device.focusMode = .autoFocus}
        else if device.isFocusModeSupported(.locked) {device.focusMode = .locked}
    }
    func setSeriesFocus(_ enabled:Bool) {
        queue.async {
            guard !self.capturing,!self.processingNow,let device=self.camera else {return}
            do {
                try device.lockForConfiguration()
                self.configureFocus(device,series:enabled,waitForDocument:enabled)
                device.unlockForConfiguration()
                self.processingLock.lock();self.seriesFocus=enabled;self.needsDocumentFocus=enabled;self.qualityReadyAt = .distantPast;self.processingLock.unlock()
                UserDefaults.standard.set(enabled,forKey:"scanflow.seriesFocus")
                self.frames.async {self.qualityHold.reset();self.tracker.resetStability()}
                self.captureAllowedAfter=Date().addingTimeInterval(0.3)
                DispatchQueue.main.async {self.seriesFocusEnabled=enabled;self.focusLocked=false;self.focusReady=false;self.focusStatus=enabled ? "Фокусуюся один раз…":"Безперервний автофокус"}
            } catch {DispatchQueue.main.async {self.message="Не вдалося змінити режим фокуса"}}
        }
    }
    // Some lenses only expose continuous AF. Freeze them after measured settling.
    private func latchSeriesFocus(_ deviceID:String,position:Float) {
        queue.async {
            guard self.seriesFocus,!self.capturing,let device=self.camera,device.uniqueID==deviceID,
                  device.focusMode == .continuousAutoFocus,device.isFocusModeSupported(.locked),
                  !device.isAdjustingFocus,abs(device.lensPosition-position)<=0.004 else {return}
            do {
                try device.lockForConfiguration()
                defer {device.unlockForConfiguration()}
                guard !device.isAdjustingFocus,abs(device.lensPosition-position)<=0.004 else {return}
                device.focusMode = .locked
            } catch {DispatchQueue.main.async {self.message="Торкніться документа, щоб повторити фокусування"}}
        }
    }
    private func configureLens(_ device:AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer {device.unlockForConfiguration()}
        configureFocus(device,series:seriesFocus,waitForDocument:true)
        if device.isExposureModeSupported(.continuousAutoExposure) {device.exposureMode = .continuousAutoExposure}
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {device.whiteBalanceMode = .continuousAutoWhiteBalance}
        let bias=min(device.maxExposureTargetBias,max(device.minExposureTargetBias,exposureBias))
        device.setExposureTargetBias(bias,completionHandler:nil)
    }
    private func configurePhotoDimensions(_ device:AVCaptureDevice) {
        let dimensions=device.activeFormat.supportedMaxPhotoDimensions
        let usable=dimensions.filter {Int64($0.width)*Int64($0.height)<=25_000_000}
        if let best=(usable.isEmpty ? dimensions:usable).max(by:{Int64($0.width)*Int64($0.height)<Int64($1.width)*Int64($1.height)}) {
            output.maxPhotoDimensions=best
        }
        for item in session.outputs {
            if let connection=item.connection(with:.video),connection.isVideoRotationAngleSupported(90) {connection.videoRotationAngle=90}
        }
    }
    func selectLens(_ id:String) {
        queue.async {
            guard self.configured,self.session.isRunning,!self.capturing,!self.processingNow,
                  let device=self.lensDevices.first(where:{$0.uniqueID==id}),
                  let old=self.cameraInput,old.device.uniqueID != id else {return}
            self.processingLock.lock();self.changingLens=true;self.processingLock.unlock()
            DispatchQueue.main.async {self.switchingLens=true;self.focusLocked=false;self.focusReady=false;self.focusStatus="Фокус нового об’єктива…";self.message="Перемикання об’єктива…"}
            defer {
                self.processingLock.lock();self.changingLens=false;self.processingLock.unlock()
                DispatchQueue.main.async {self.switchingLens=false}
            }
            do {
                let input=try AVCaptureDeviceInput(device:device)
                try self.configureLens(device)
                self.session.beginConfiguration()
                self.session.removeInput(old)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.processingLock.lock();self.camera=device;self.needsDocumentFocus=true;self.processingLock.unlock()
                    self.cameraInput=input
                    self.configurePhotoDimensions(device)
                    self.session.commitConfiguration()
                    UserDefaults.standard.set(id,forKey:"scanflow.cameraLens")
                    self.captureAllowedAfter=Date().addingTimeInterval(0.8)
                    self.frames.async {
                        self.tracker=CaptureStability();self.qualityHold.reset();self.lastSegmentation = .distantPast
                        self.ignoreFramesUntil=Date().addingTimeInterval(0.8)
                        DispatchQueue.main.async {self.detected=false;self.detectedQuad=nil}
                    }
                    self.publishLenses()
                    DispatchQueue.main.async {self.message="Наведіть камеру на аркуш"}
                } else {
                    if self.session.canAddInput(old) {self.session.addInput(old)}
                    self.configurePhotoDimensions(old.device)
                    self.session.commitConfiguration()
                    DispatchQueue.main.async {self.message="Не вдалося перемкнути об’єктив. Попередню камеру збережено"}
                }
            } catch {DispatchQueue.main.async {self.message=error.localizedDescription}}
        }
    }
    private var focusAdjusting:Bool {
        processingLock.lock();let device=camera;processingLock.unlock()
        return device?.isAdjustingFocus == true
    }
    func setProcessing(_ value:Bool) {
        processingLock.lock();processing=value;processingLock.unlock()
        DispatchQueue.main.async {self.preparing=value;if value {self.message="Визначення меж аркуша…"}}
    }
    func stop() { queue.async {self.runningWanted=false; if self.session.isRunning { self.session.stopRunning() } } }
    func setAuto(_ value:Bool) { frames.async { self.auto=value; self.tracker.resetStability() } }
    func toggleFlash() {
        queue.async {
            self.useFlash.toggle()
            let enabled=self.useFlash
            DispatchQueue.main.async { self.flashEnabled=enabled;self.lastFlashFired=nil }
        }
    }
    func setBrightness(_ value:Double) {
        queue.async {
            guard let device=self.camera else {return}
            do {
                try device.lockForConfiguration()
                let bias=min(device.maxExposureTargetBias,max(device.minExposureTargetBias,Float(value)))
                self.exposureBias=bias
                device.setExposureTargetBias(bias,completionHandler:nil);device.unlockForConfiguration()
                DispatchQueue.main.async {self.brightness=Double(bias)}
            } catch {DispatchQueue.main.async {self.message="Не вдалося змінити експозицію"}}
        }
    }
    func focus(at point:CGPoint) {
        queue.async {
            guard !self.capturing,!self.processingNow,let device=self.camera else {return}
            do {
                try device.lockForConfiguration()
                if device.isExposurePointOfInterestSupported {device.exposurePointOfInterest=point}
                self.configureFocus(device,series:self.seriesFocus,point:point)
                if device.isExposureModeSupported(.continuousAutoExposure) {device.exposureMode = .continuousAutoExposure}
                device.unlockForConfiguration()
                self.captureAllowedAfter=Date().addingTimeInterval(0.6)
                self.processingLock.lock();self.needsDocumentFocus=false;self.qualityReadyAt = .distantPast;self.processingLock.unlock()
                self.frames.async {self.tracker.resetStability();self.qualityHold.reset()}
                DispatchQueue.main.async {self.focusReady=false;self.focusLocked=false;self.focusStatus=self.seriesFocus ? "Фокусуюся один раз…":"Фокусуюся…"}
            } catch {DispatchQueue.main.async {self.message="Не вдалося перефокусувати. Спробуйте ще раз"}}
        }
    }
    private func pauseDetectionAfterShot(markCaptured:Bool=true) {
        frames.async {
            self.ignoreFramesUntil=Date().addingTimeInterval(markCaptured ? 0.35:0.45)
            if markCaptured {self.tracker.didCapture()}
            else {self.tracker.resetStability()}
        }
    }
    func shoot(automatic:Bool=false) {
        queue.async {
            guard self.configured,self.session.isRunning,!self.capturing,!self.processingNow,Date()>=self.captureAllowedAfter else { return }
            self.processingLock.lock()
            let recent=Date().timeIntervalSince(self.qualityReadyAt)<0.6
            let checkedPosition=self.readyLensPosition,checkedDeviceID=self.readyDeviceID
            self.processingLock.unlock()
            guard let device=self.camera else {return}
            let checked=recent && checkedDeviceID==device.uniqueID && !device.isAdjustingFocus && abs(device.lensPosition-checkedPosition)<=0.004
            // A manual shutter press always takes the frame. Automatic shots
            // still wait for a recent settled lens, never for text recognition.
            if automatic && !checked {return}
            // A refocus request may have just changed locked -> autoFocus before
            // lens motion starts. A stale settled frame must not cancel that pass.
            if automatic && self.seriesFocus && device.isFocusModeSupported(.locked) && device.focusMode != .locked {return}
            do {
                // Freeze a verified focus position through the photo exposure.
                // This is a real hardware mode, not a green timer indicator.
                if checked && device.isFocusModeSupported(.locked) {
                    try device.lockForConfiguration()
                    let unchanged = !device.isAdjustingFocus && abs(device.lensPosition-checkedPosition)<=0.004
                    if unchanged {device.focusMode = .locked}
                    device.unlockForConfiguration()
                    if !unchanged && automatic {return}
                    if unchanged {DispatchQueue.main.async {self.focusLocked=true;self.focusStatus="Фокус зафіксовано · знімаю"}}
                }
            } catch {
                if automatic {DispatchQueue.main.async {self.message="Повторюю фокусування…"};return}
            }
            self.capturing=true
            DispatchQueue.main.async { self.shooting=true }
            let settings=AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.maxPhotoDimensions=self.output.maxPhotoDimensions
            let selectedMode:AVCaptureDevice.FlashMode=self.useFlash && self.camera?.hasFlash == true ? .on : .off
            settings.flashMode=self.output.supportedFlashModes.contains(selectedMode) ? selectedMode : .off
            self.pauseDetectionAfterShot()
            self.output.capturePhoto(with:settings,delegate:self)
        }
    }
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?) {
        defer {
            pauseDetectionAfterShot(markCaptured:false)
            queue.async {
                if !self.seriesFocus {
                    if let device=self.camera,device.isFocusModeSupported(.continuousAutoFocus) {
                        do {try device.lockForConfiguration();device.focusMode = .continuousAutoFocus;device.unlockForConfiguration()}
                        catch {DispatchQueue.main.async {self.message="Торкніться документа, щоб повторити фокусування"}}
                    }
                    self.processingLock.lock();self.qualityReadyAt = .distantPast;self.processingLock.unlock()
                    self.frames.async {self.qualityHold.reset()}
                }
                // In series mode keep the actual hardware lock, not just the icon.
                let locked=self.camera?.focusMode == .locked && self.camera?.isAdjustingFocus == false
                self.capturing=false
                DispatchQueue.main.async {self.focusLocked=locked;self.focusReady=locked;self.focusStatus=locked ? "Фокус серії зафіксовано":"Перевіряю фокус…"}
            }
            DispatchQueue.main.async { self.shooting=false }
        }
        if let error { DispatchQueue.main.async { self.message=error.localizedDescription }; return }
        guard let bytes=photo.fileDataRepresentation(),let image=UIImage(data:bytes) else { return }
        var fired:Bool?=photo.resolvedSettings.isFlashEnabled ? nil:false
        if let source=CGImageSourceCreateWithData(bytes as CFData,nil),
           let properties=CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
           let exif=properties[kCGImagePropertyExifDictionary] as? [CFString:Any],
           let flag=exif[kCGImagePropertyExifFlash] as? NSNumber {fired=(flag.intValue & 1)==1}
        let actualFlash=fired
        DispatchQueue.main.async { self.lastFlashFired=actualFlash; self.captured?(image)
        }
    }
    private func frameSignature(_ buffer:CVPixelBuffer)->[UInt8] {
        let input=CIImage(cvPixelBuffer:buffer)
        let scaled=input.transformed(by:CGAffineTransform(scaleX:16/input.extent.width,y:16/input.extent.height))
        guard let cg=imageContext.createCGImage(scaled,from:CGRect(x:0,y:0,width:16,height:16)) else{return []}
        var bytes=[UInt8](repeating:0,count:256)
        bytes.withUnsafeMutableBytes { raw in
            if let context=CGContext(data:raw.baseAddress,width:16,height:16,bitsPerComponent:8,bytesPerRow:16,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0) {context.draw(cg,in:CGRect(x:0,y:0,width:16,height:16))}
        }
        return bytes
    }
    private func pageFingerprint(_ input:CIImage,quad:Quad?)->[UInt8] {
        guard let quad,quad.valid else {return []}
        let extent=input.extent
        func vector(_ point:Point)->CIVector {
            CIVector(x:extent.minX+point.x*extent.width,y:extent.minY+(1-point.y)*extent.height)
        }
        let paper=input.applyingFilter("CIPerspectiveCorrection",parameters:[
            "inputTopLeft":vector(quad.points[0]),"inputTopRight":vector(quad.points[1]),
            "inputBottomRight":vector(quad.points[2]),"inputBottomLeft":vector(quad.points[3])])
        guard !paper.extent.isEmpty,!paper.extent.isInfinite else {return []}
        let origin=paper.transformed(by:CGAffineTransform(translationX:-paper.extent.minX,y:-paper.extent.minY))
        let small=origin.transformed(by:CGAffineTransform(scaleX:CGFloat(PageFingerprint.width)/paper.extent.width,y:CGFloat(PageFingerprint.height)/paper.extent.height))
        let rect=CGRect(x:0,y:0,width:CGFloat(PageFingerprint.width),height:CGFloat(PageFingerprint.height))
        guard let cg=imageContext.createCGImage(small,from:rect) else {return []}
        var gray=[UInt8](repeating:255,count:PageFingerprint.width*PageFingerprint.height)
        gray.withUnsafeMutableBytes {raw in
            let context=CGContext(data:raw.baseAddress,width:PageFingerprint.width,height:PageFingerprint.height,bitsPerComponent:8,bytesPerRow:PageFingerprint.width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:0)
            context?.draw(cg,in:rect)
        }
        return PageFingerprint.make(gray)
    }
    private func focusFirstDocument(_ quad:Quad)->Bool {
        processingLock.lock()
        let pending=needsDocumentFocus && seriesFocus
        if pending {needsDocumentFocus=false;qualityReadyAt = .distantPast}
        processingLock.unlock()
        guard pending else {return false}
        let x=quad.points.map(\.x).reduce(0,+)/4
        let y=quad.points.map(\.y).reduce(0,+)/4
        // Video buffers are rotated clockwise into portrait. Device POI uses
        // the unrotated landscape sensor coordinate system.
        focus(at:CGPoint(x:y,y:1-x))
        return true
    }
    func captureOutput(_ output:AVCaptureOutput,didOutput sampleBuffer:CMSampleBuffer,from connection:AVCaptureConnection) {
        let now=Date()
        guard !processingNow,now>ignoreFramesUntil,now.timeIntervalSince(lastTime)>0.20,
              let buffer=CMSampleBufferGetImageBuffer(sampleBuffer) else {return}
        lastTime=now
        let input=CIImage(cvPixelBuffer:buffer)
        let factor=min(1,1100/max(input.extent.width,input.extent.height))
        let scaled=input.transformed(by:CGAffineTransform(scaleX:factor,y:factor))
        guard let cg=imageContext.createCGImage(scaled,from:scaled.extent) else {return}
        func q(_ r:VNRectangleObservation)->Quad {
            func p(_ v:CGPoint)->Point {Point(x:Double(v.x),y:Double(1-v.y))}
            return Quad(points:[p(r.topLeft),p(r.topRight),p(r.bottomRight),p(r.bottomLeft)])
        }
        func eligible(_ quad:Quad)->Bool {
            let area=CropSafety.area(quad)
            return quad.valid && area>=0.055 && area<0.94
        }
        let request=VNDetectRectanglesRequest()
        request.minimumConfidence=0.55;request.maximumObservations=8
        request.minimumSize=0.15;request.minimumAspectRatio=0.25;request.quadratureTolerance=35
        do {
            try VNImageRequestHandler(cgImage:cg).perform([request])
            var proposals=(request.results ?? []).map {(q($0),Double($0.confidence))}.filter {eligible($0.0)}
            var documentCandidate:Quad?
            // Semantic paper detection supplements rectangles, particularly on
            // a patterned floor. Run periodically, not on every video frame.
            if proposals.isEmpty || now.timeIntervalSince(lastSegmentation)>0.9 {
                lastSegmentation=now
                let document=VNDetectDocumentSegmentationRequest()
                try? VNImageRequestHandler(cgImage:cg).perform([document])
                let sheets=(document.results ?? []).filter {$0.confidence>=0.55}.map {(q($0),Double($0.confidence)+0.55)}.filter {eligible($0.0)}
                documentCandidate=sheets.max {a,b in a.1*sqrt(CropSafety.area(a.0))<b.1*sqrt(CropSafety.area(b.0))}?.0
                proposals += sheets
            }
            let previous=tracker.quad
            let candidate=documentCandidate ?? proposals.max {a,b in
                func score(_ item:(Quad,Double))->Double {
                    let continuity=previous.map {max(0,0.25-CaptureStability.distance($0,item.0))} ?? 0
                    return item.1*sqrt(CropSafety.area(item.0))+continuity*3
                }
                return score(a)<score(b)
            }?.0
            let requestedFocus=candidate.map {focusFirstDocument($0)} ?? false
            let signature=frameSignature(buffer)
            let content=pageFingerprint(input,quad:candidate)
            let focusSample=Date()
            processingLock.lock();let device=camera;let wantsSeries=seriesFocus;let pendingFocus=needsDocumentFocus && wantsSeries;processingLock.unlock()
            let series=wantsSeries && device?.isFocusModeSupported(.locked)==true
            let adjusting=device?.isAdjustingFocus ?? true
            let position=device?.lensPosition ?? 0
            let settled=qualityHold.update(position:position,adjusting:adjusting,time:focusSample.timeIntervalSinceReferenceDate)
            let locked=device?.focusMode == .locked && !adjusting
            if series && !requestedFocus && !pendingFocus && settled && !locked,let device {latchSeriesFocus(device.uniqueID,position:position)}
            let quality = !requestedFocus && !pendingFocus && (series ? locked:settled)
            let ready=tracker.update(candidate,signature:signature,time:now.timeIntervalSinceReferenceDate,focusing:!quality,pageContent:content)
            let quad=tracker.quad
            processingLock.lock()
            qualityReadyAt=quality ? focusSample:.distantPast;readyLensPosition=position;readyDeviceID=device?.uniqueID ?? ""
            processingLock.unlock()
            let focusText:String
            if locked {focusText=series ? "Фокус серії зафіксовано":"Фокус зафіксовано"}
            else if adjusting {focusText=series ? "Фокусуюся один раз…":"Фокусуюся…"}
            else {focusText=quality ? "Фокус стабільний":"Стабілізую фокус…"}
            let hint:String
            if let candidate {
                let center=candidate.points.map(\.y).reduce(0,+)/4
                let offCenter=abs(center-0.5)>0.13 || candidate.points.contains {$0.x<0.035 || $0.x>0.965 || $0.y<0.035 || $0.y>0.965}
                hint=offCenter ? "Для чітких країв: віддаліть камеру й розташуйте аркуш у центрі":"Тримайте iPhone паралельно аркушу"
            } else {hint=""}
            let aspect=CGFloat(CVPixelBufferGetWidth(buffer))/CGFloat(CVPixelBufferGetHeight(buffer))
            let text = quad == nil ? "У кадрі має бути весь аркуш · можна зняти вручну" :
                (auto ? (tracker.armed ? "Аркуш знайдено · готую знімок…":"Перегорніть або заберіть аркуш") : "Аркуш знайдено")
            DispatchQueue.main.async {self.detected=quad != nil;self.detectedQuad=quad;self.frameAspect=aspect;self.message=text;self.focusReady=quality;self.focusLocked=locked;self.focusStatus=focusText;self.framingHint=hint}
            if auto && ready {shoot(automatic:true)}
        } catch {DispatchQueue.main.async {self.message="Зніміть вручну кнопкою внизу"}}
    }

}
final class CameraLayer: UIView {
    weak var engine:CameraEngine?
    override class var layerClass:AnyClass {AVCaptureVideoPreviewLayer.self}
    var preview:AVCaptureVideoPreviewLayer {layer as! AVCaptureVideoPreviewLayer}
    override init(frame:CGRect) {
        super.init(frame:frame)
        addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(tapped(_:))))
    }
    required init?(coder:NSCoder){fatalError("init(coder:) is not supported")}
    @objc private func tapped(_ gesture:UITapGestureRecognizer) {
        engine?.focus(at:preview.captureDevicePointConverted(fromLayerPoint:gesture.location(in:self)))
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection=preview.connection,connection.isVideoRotationAngleSupported(90) {connection.videoRotationAngle=90}
    }
}
struct CameraPreview:UIViewRepresentable {
    let engine:CameraEngine
    func makeUIView(context:Context)->CameraLayer {
        let view=CameraLayer(frame:.zero);view.engine=engine;view.preview.session=engine.session;view.preview.videoGravity = .resizeAspectFill;return view
    }
    func updateUIView(_ view:CameraLayer,context:Context){view.setNeedsLayout()}
}
struct CameraLensPicker:View {
    @ObservedObject var engine:CameraEngine
    let disabled:Bool
    private var title:String {
        if engine.switchingLens {return "Перемикання…"}
        return engine.lenses.first(where:{$0.id==engine.selectedLensID})?.title ?? "Об’єктив"
    }
    var body:some View {
        HStack {
            Menu {
                ForEach(engine.lenses) {lens in
                    Button {engine.selectLens(lens.id)} label:{
                        if lens.id==engine.selectedLensID {Label(lens.title,systemImage:"checkmark")}
                        else {Text(lens.title)}
                    }
                }
            } label:{
                Label(title,systemImage:"camera.aperture").font(.subheadline.weight(.medium))
                    .padding(.horizontal,12).padding(.vertical,8)
                    .background(.black.opacity(0.55),in:Capsule())
            }.disabled(disabled || engine.lenses.count<2).accessibilityLabel("Вибрати об’єктив камери")
            Spacer()
            if !engine.flashSupported && !engine.lenses.isEmpty {
                Text("Без спалаху").font(.caption).padding(8).background(.black.opacity(0.55),in:Capsule())
            }
        }
    }
}
struct CaptureView:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine=CameraEngine()
    @Environment(\.scenePhase) private var scenePhase
    @State private var previousIdleTimer:Bool?
    @State private var visible=false
    @State private var auto=true
    @State private var exposure=false
    @State private var reviewing=false
    let documentID:UUID
    var pages:[Leaf] {store.document(documentID)?.pages ?? []}
    var count:Int {pages.count}
    var waiting:Bool {store.savingPhotos>0 || engine.shooting || engine.preparing || engine.switchingLens}
    var body:some View {
        ZStack {
            // Full-screen camera: no inset document field, rounded frame or fixed dashed rectangle.
            CameraPreview(engine:engine).ignoresSafeArea()
            GeometryReader { proxy in
                if auto,let quad=engine.detectedQuad {
                    let view=proxy.size,aspect=engine.frameAspect
                    let width=max(view.width,view.height*aspect),height=width/aspect
                    let dx=(view.width-width)/2,dy=(view.height-height)/2
                    Path {path in
                        for (index,point) in quad.points.enumerated() {
                            let p=CGPoint(x:dx+point.x*width,y:dy+point.y*height)
                            if index==0 {path.move(to:p)}else{path.addLine(to:p)}
                        }
                        path.closeSubpath()
                    }.stroke(engine.focusReady ? Color.scanSuccess:Color.accent,lineWidth:2)
                }
            }.ignoresSafeArea().clipped().allowsHitTesting(false)
            VStack {
                LinearGradient(colors:[.black.opacity(0.7),.clear],startPoint:.top,endPoint:.bottom).frame(height:160)
                Spacer()
                LinearGradient(colors:[.clear,.black.opacity(0.85)],startPoint:.top,endPoint:.bottom).frame(height:260)
            }.ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing:16) {
                HStack(spacing:20) {
                    Button {dismiss()} label:{Image(systemName:"xmark").frame(width:40,height:40)}.disabled(waiting)
                    Spacer()
                    Button {auto.toggle()} label:{Label(auto ? "Авто":"Вручну",systemImage:auto ? "viewfinder.circle.fill":"viewfinder").font(.subheadline.weight(.semibold))}
                    Button {engine.toggleFlash()} label:{Image(systemName:engine.flashEnabled && engine.flashSupported ? "bolt.fill":"bolt.slash.fill").foregroundStyle(engine.flashEnabled && engine.flashSupported ? Color.yellow:.white)}.disabled(!engine.flashSupported || waiting).accessibilityLabel("Спалах")
                    Button {exposure.toggle()} label:{Image(systemName:"sun.max")}.accessibilityLabel("Яскравість фото")
                }.font(.title3).padding(12).scanGlass().padding(.horizontal,16)
                CameraLensPicker(engine:engine,disabled:waiting).padding(.horizontal,22)
                CameraFocusControls(engine:engine,disabled:waiting).padding(.horizontal,22)
                if exposure {
                    HStack {
                        Image(systemName:"sun.min")
                        Slider(value:Binding(get:{engine.brightness},set:{engine.setBrightness($0)}),in:-0.7...1.0).tint(.accent)
                        Image(systemName:"sun.max.fill")
                        Text(String(format:"%+.1f",engine.brightness)).font(.caption.monospacedDigit()).frame(width:36)
                    }.padding(14).background(.black.opacity(0.55),in:RoundedRectangle(cornerRadius:18)).padding(.horizontal,22)
                }
                Spacer()
                if !engine.framingHint.isEmpty {
                    Text(engine.framingHint).font(.caption).multilineTextAlignment(.center)
                        .padding(8).background(.black.opacity(0.6),in:Capsule()).allowsHitTesting(false)
                }
                Label(engine.focusStatus,systemImage:engine.focusLocked ? "lock.fill":(engine.focusReady ? "checkmark.viewfinder":"viewfinder"))
                    .font(.caption.weight(.semibold)).foregroundStyle(engine.focusReady || engine.focusLocked ? Color.scanSuccess:Color.yellow)
                    .multilineTextAlignment(.center).padding(10).background(.black.opacity(0.65),in:Capsule())
                    .accessibilityLabel(engine.focusStatus)
                Text(engine.message).font(.subheadline.weight(.medium)).multilineTextAlignment(.center).padding(.horizontal,16).padding(.vertical,9).background(.black.opacity(0.5),in:Capsule())
                HStack {
                    Button {reviewing=true} label: {
                        ZStack(alignment:.bottomTrailing) {
                            Thumb(file:pages.last?.output).frame(width:52,height:70).clipShape(RoundedRectangle(cornerRadius:7))
                            Text("\(count)").font(.caption.bold().monospacedDigit()).padding(5).background(Color.accent,in:Circle()).offset(x:7,y:7)
                        }
                    }.frame(width:74).disabled(count==0 || waiting).accessibilityLabel("Переглянути сторінки")
                    Spacer()
                    Button {engine.shoot()} label:{Circle().fill(.white).frame(width:68,height:68).padding(6).overlay(Circle().stroke(.white,lineWidth:2))}.disabled(waiting).accessibilityLabel("Зняти сторінку")
                    Spacer()
                    Button {dismiss()} label:{Text(store.savingPhotos>0 ? "Зберігаю…":"Готово").font(.subheadline.weight(.semibold)).frame(width:74)}.disabled(waiting)
                }.padding(.horizontal,26)
                HStack(spacing:6) {
                    Text("Документ").font(.caption.weight(.semibold))
                    if engine.flashEnabled,let fired=engine.lastFlashFired {
                        Text("·").foregroundStyle(.white.opacity(0.45))
                        Image(systemName:fired ? "bolt.fill":"bolt.slash").foregroundStyle(fired ? Color.yellow:.orange)
                        Text(fired ? "Спалах спрацював":"Спалах не спрацював").font(.caption2)
                    }
                }.padding(.bottom,12)
            }.foregroundStyle(.white)
        }.background(.black).preferredColorScheme(.dark)
        .onAppear {
            visible=true
            if previousIdleTimer==nil {previousIdleTimer=UIApplication.shared.isIdleTimerDisabled}
            updateCameraActivity()
            engine.captured={ [weak engine] image in
                engine?.setProcessing(true)
                Task {
                    await store.addImage(image,to:documentID,sourceKind:"camera",prepare:true)
                    engine?.setProcessing(false)
                }
            }
        }
        .onDisappear {visible=false;engine.stop();UIApplication.shared.isIdleTimerDisabled=previousIdleTimer ?? false;previousIdleTimer=nil;store.save()}
        .onChange(of:auto){_,value in engine.setAuto(value)}
        .onChange(of:reviewing){_,_ in updateCameraActivity()}
        .onChange(of:scenePhase){_,_ in updateCameraActivity()}
        .fullScreenCover(isPresented:$reviewing,onDismiss:{updateCameraActivity()}) {
            NavigationStack {
                PageBrowser(documentID:documentID,initialPageID:pages.last?.id ?? documentID)
                    .toolbar {ToolbarItem(placement:.topBarLeading){Button("До камери"){reviewing=false}}}
            }
        }
    }
    private func updateCameraActivity() {
        let active=visible && scenePhase == .active && !reviewing
        UIApplication.shared.isIdleTimerDisabled=active ? true : (previousIdleTimer ?? false)
        if active {engine.start()}else{engine.stop()}
    }

}
