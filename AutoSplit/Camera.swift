import SwiftUI
import AVFoundation
import Vision
import CoreImage
import ImageIO

final class CameraEngine: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session=AVCaptureSession()
    private let queue=DispatchQueue(label:"scan.camera")
    private let frames=DispatchQueue(label:"scan.edges")
    private let output=AVCapturePhotoOutput()
    private var camera:AVCaptureDevice?
    private let processingLock=NSLock()
    private var processing=false
    @Published var preparing=false
    private var configured=false
    private var capturing=false
    private var lastTime=Date.distantPast
    private var tracker=CaptureStability()
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
                        guard let device=AVCaptureDevice.default(.builtInWideAngleCamera,for:.video,position:.back) else { throw ScanError.message("Камера недоступна") }
                        self.camera=device
                        try device.lockForConfiguration()
                        if device.isFocusModeSupported(.continuousAutoFocus) {device.focusMode = .continuousAutoFocus}
                        if device.isExposureModeSupported(.continuousAutoExposure) {device.exposureMode = .continuousAutoExposure}
                        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {device.whiteBalanceMode = .continuousAutoWhiteBalance}
                        device.setExposureTargetBias(min(device.maxExposureTargetBias,max(device.minExposureTargetBias,0.3)),completionHandler:nil)
                        device.unlockForConfiguration()
                        let input=try AVCaptureDeviceInput(device:device)
                        guard self.session.canAddInput(input),self.session.canAddOutput(self.output) else { throw ScanError.message("Не вдалося налаштувати камеру") }
                        self.session.addInput(input); self.session.addOutput(self.output)
                        self.output.maxPhotoQualityPrioritization = .quality
                        let dimensions=device.activeFormat.supportedMaxPhotoDimensions
                        let usable=dimensions.filter {Int64($0.width)*Int64($0.height)<=12_500_000}
                        if let best=(usable.isEmpty ? dimensions:usable).max(by:{Int64($0.width)*Int64($0.height)<Int64($1.width)*Int64($1.height)}) {
                            self.output.maxPhotoDimensions=best
                        }
                        let video=AVCaptureVideoDataOutput(); video.alwaysDiscardsLateVideoFrames=true
                        video.setSampleBufferDelegate(self,queue:self.frames)
                        if self.session.canAddOutput(video) { self.session.addOutput(video) }
                        for connection in [video.connection(with:.video),self.output.connection(with:.video)].compactMap({$0}) {
                            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle=90 }
                        }
                        self.session.commitConfiguration(); self.configured=true
                    }
                    self.session.startRunning()
                    let supported=self.output.supportedFlashModes.contains(.on)
                    DispatchQueue.main.async { self.flashSupported=supported }
                } catch {
                    if !self.configured { self.session.commitConfiguration() }
                    DispatchQueue.main.async { self.message=error.localizedDescription }
                }
            }
        }
    }
    private var processingNow:Bool {processingLock.lock();defer {processingLock.unlock()};return processing}
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
                device.setExposureTargetBias(bias,completionHandler:nil);device.unlockForConfiguration()
                DispatchQueue.main.async {self.brightness=Double(bias)}
            } catch {DispatchQueue.main.async {self.message="Не вдалося змінити експозицію"}}
        }
    }
    func focus(at point:CGPoint) {
        queue.async {
            guard let device=self.camera else {return}
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {device.focusPointOfInterest=point}
                if device.isExposurePointOfInterestSupported {device.exposurePointOfInterest=point}
                if device.isFocusModeSupported(.continuousAutoFocus) {device.focusMode = .continuousAutoFocus}
                if device.isExposureModeSupported(.continuousAutoExposure) {device.exposureMode = .continuousAutoExposure}
                device.unlockForConfiguration()
                self.frames.async {self.tracker.resetStability()}
            } catch {}
        }
    }
    private func pauseDetectionAfterShot() {
        frames.async {
            self.ignoreFramesUntil=Date().addingTimeInterval(1.2)
            self.tracker.didCapture()
        }
    }
    func shoot() {
        queue.async {
            guard self.configured,self.session.isRunning,!self.capturing,!self.processingNow else { return }
            self.capturing=true
            DispatchQueue.main.async { self.shooting=true }
            let settings=AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .quality
            settings.maxPhotoDimensions=self.output.maxPhotoDimensions
            let selectedMode:AVCaptureDevice.FlashMode=self.useFlash ? .on : .off
            settings.flashMode=self.output.supportedFlashModes.contains(selectedMode) ? selectedMode : .off
            self.pauseDetectionAfterShot()
            self.output.capturePhoto(with:settings,delegate:self)
        }
    }
    func photoOutput(_ output:AVCapturePhotoOutput,didFinishProcessingPhoto photo:AVCapturePhoto,error:Error?) {
        defer {
            pauseDetectionAfterShot()
            queue.async { self.capturing=false }
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
            let signature=frameSignature(buffer)
            let ready=tracker.update(candidate,signature:signature,time:now.timeIntervalSinceReferenceDate,focusing:camera?.isAdjustingFocus == true)
            let quad=tracker.quad
            let aspect=CGFloat(CVPixelBufferGetWidth(buffer))/CGFloat(CVPixelBufferGetHeight(buffer))
            let text = quad == nil ? "У кадрі має бути весь аркуш · можна зняти вручну" :
                (auto ? (tracker.armed ? "Аркуш знайдено · готую знімок…":"Перегорніть або заберіть аркуш") : "Аркуш знайдено")
            DispatchQueue.main.async {self.detected=quad != nil;self.detectedQuad=quad;self.frameAspect=aspect;self.message=text}
            if auto && ready {tracker.didCapture();shoot()}
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
    var waiting:Bool {store.savingPhotos>0 || engine.shooting || engine.preparing}
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
                    }.stroke(.mint,lineWidth:2)
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
                    Button {engine.toggleFlash()} label:{Image(systemName:engine.flashEnabled ? "bolt.fill":"bolt.slash.fill").foregroundStyle(engine.flashEnabled ? Color.yellow:.white)}.disabled(!engine.flashSupported || engine.shooting).accessibilityLabel("Спалах")
                    Button {exposure.toggle()} label:{Image(systemName:"sun.max")}.accessibilityLabel("Яскравість фото")
                }.font(.title3).padding(.horizontal,18)
                if exposure {
                    HStack {
                        Image(systemName:"sun.min")
                        Slider(value:Binding(get:{engine.brightness},set:{engine.setBrightness($0)}),in:-0.7...1.0).tint(.white)
                        Image(systemName:"sun.max.fill")
                        Text(String(format:"%+.1f",engine.brightness)).font(.caption.monospacedDigit()).frame(width:36)
                    }.padding(14).background(.black.opacity(0.55),in:RoundedRectangle(cornerRadius:18)).padding(.horizontal,22)
                }
                Spacer()
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
        }.background(.black)
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
