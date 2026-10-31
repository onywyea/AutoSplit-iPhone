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
    private var configured=false
    private var capturing=false
    private var lastTime=Date.distantPast
    private var lastQuad:Quad?
    private var stable=0
    private var armed=true
    private var absent=0
    private var lastSignature:[UInt8]?
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
        AVCaptureDevice.requestAccess(for:.video) { [weak self] granted in
            guard let self else { return }
            guard granted else { DispatchQueue.main.async { self.message="Дозвольте камеру в Налаштуваннях iPhone → ScanFlow" }; return }
            self.queue.async {
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
    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
    func setAuto(_ value:Bool) { frames.async { self.auto=value; self.stable=0 } }
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
                self.frames.async {self.stable=0}
            } catch {}
        }
    }
    private func pauseDetectionAfterShot() {
        frames.async {
            self.ignoreFramesUntil=Date().addingTimeInterval(1.2)
            self.lastSignature=nil; self.stable=0; self.armed=false
        }
    }
    func shoot() {
        queue.async {
            guard self.configured,self.session.isRunning,!self.capturing else { return }
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
        guard Date()>ignoreFramesUntil,Date().timeIntervalSince(lastTime)>0.45,let buffer=CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastTime=Date()
        let request=VNDetectRectanglesRequest(); request.minimumConfidence=0.8; request.maximumObservations=1
        request.minimumSize=0.35; request.minimumAspectRatio=0.3; request.quadratureTolerance=25
        do {
            try VNImageRequestHandler(cvPixelBuffer:buffer,orientation:.up).perform([request])
            guard let r=request.results?.first else {
                stable=0; absent+=1
                if absent>=2 { armed=true; lastQuad=nil }
                DispatchQueue.main.async { self.detected=false;self.detectedQuad=nil; self.message="Аркуш має бути повністю в кадрі" }; return
            }
            absent=0
            func p(_ v:CGPoint)->Point { .init(x:Double(v.x),y:Double(1-v.y)) }
            let quad=Quad(points:[p(r.topLeft),p(r.topRight),p(r.bottomRight),p(r.bottomLeft)])
            var delta=1.0
            if let lastQuad {
                delta=zip(quad.points,lastQuad.points).map { pair in abs(pair.0.x-pair.1.x)+abs(pair.0.y-pair.1.y) }.reduce(0,+)/4
            }
            let signature=frameSignature(buffer)
            var motion=0.0
            if let previous=lastSignature,previous.count==signature.count,!signature.isEmpty {
                motion=zip(previous,signature).map{pair in abs(Double(pair.0)-Double(pair.1))/255}.reduce(0,+)/Double(signature.count)
            }
            lastSignature=signature
            if delta>0.12 || motion>0.06 { armed=true }
            stable=delta<0.018 && motion<0.015 ? stable+1 : 0; lastQuad=quad
            let statusMessage=auto ? (armed ? "Тримайте нерухомо…" : "Перегорніть або заберіть аркуш") : "Аркуш знайдено"
            let aspect=CGFloat(CVPixelBufferGetWidth(buffer))/CGFloat(CVPixelBufferGetHeight(buffer))
            let adjusting=camera?.isAdjustingFocus == true || camera?.isAdjustingExposure == true
            if adjusting {stable=0}
            DispatchQueue.main.async { self.detected=true;self.detectedQuad=quad;self.frameAspect=aspect;self.message=adjusting ? "Налаштування різкості…":statusMessage }
            if auto && armed && stable>=3 { armed=false; stable=0; shoot() }
        } catch { DispatchQueue.main.async { self.message="Зніміть вручну кнопкою внизу" } }
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
    @State private var auto=true
    @State private var exposure=false
    @State private var reviewing=false
    let documentID:UUID
    var pages:[Leaf] {store.document(documentID)?.pages ?? []}
    var count:Int {pages.count}
    var waiting:Bool {store.savingPhotos>0 || engine.shooting}
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
        .onAppear {engine.captured={image in Task {await store.addImage(image,to:documentID)}};engine.start()}
        .onDisappear {engine.stop();store.save()}
        .onChange(of:auto){_,value in engine.setAuto(value)}
        .onChange(of:reviewing){_,value in if value {engine.stop()}}
        .sheet(isPresented:$reviewing,onDismiss:{engine.start()}) {
            if let first=pages.last {
                NavigationStack {
                    PageBrowser(documentID:documentID,initialPageID:first.id)
                        .toolbar {ToolbarItem(placement:.topBarLeading){Button("До камери"){reviewing=false}}}
                }
            }
        }
    }
}
