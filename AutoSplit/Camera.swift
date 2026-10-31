import SwiftUI
import AVFoundation
import Vision
import CoreImage

final class CameraEngine: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session=AVCaptureSession()
    private let queue=DispatchQueue(label:"scan.camera")
    private let frames=DispatchQueue(label:"scan.edges")
    private let output=AVCapturePhotoOutput()
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
    @Published var flash=false
    @Published var shooting=false
    @Published var flashEnabled=true
    @Published var flashSupported=false
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
                        let input=try AVCaptureDeviceInput(device:device)
                        guard self.session.canAddInput(input),self.session.canAddOutput(self.output) else { throw ScanError.message("Не вдалося налаштувати камеру") }
                        self.session.addInput(input); self.session.addOutput(self.output)
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
            DispatchQueue.main.async { self.flashEnabled=enabled }
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
        DispatchQueue.main.async { self.flash=true; self.captured?(image)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.12) { self.flash=false }
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
                DispatchQueue.main.async { self.detected=false; self.message="Аркуш має бути повністю в кадрі" }; return
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
            DispatchQueue.main.async { self.detected=true; self.message=statusMessage }
            if auto && armed && stable>=3 { armed=false; stable=0; shoot() }
        } catch { DispatchQueue.main.async { self.message="Зніміть вручну кнопкою внизу" } }
    }
}
final class CameraLayer: UIView {
    override class var layerClass:AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview:AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection=preview.connection,connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle=90 }
    }
}
struct CameraPreview:UIViewRepresentable {
    let engine:CameraEngine
    func makeUIView(context:Context)->CameraLayer {
        let view=CameraLayer(); view.preview.session=engine.session; view.preview.videoGravity = .resizeAspectFill; return view
    }
    func updateUIView(_ uiView:CameraLayer,context:Context) { uiView.setNeedsLayout() }
}
struct CaptureView:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine=CameraEngine()
    @State private var auto=true
    let documentID:UUID
    var count:Int { store.document(documentID)?.pages.count ?? 0 }
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing:20) {
                HStack {
                    Button { dismiss() } label: { Image(systemName:"xmark").font(.title3).frame(width:44,height:44).background(.white.opacity(0.12),in:Circle()) }.disabled(store.savingPhotos>0 || engine.shooting)
                    Spacer(); Text("\(count) стор.").font(.headline.monospacedDigit())
                    Spacer(); Button(store.savingPhotos>0 ? "Зберігаю…" : "Готово") { dismiss() }.fontWeight(.semibold).disabled(store.savingPhotos>0 || engine.shooting)
                }.padding(.horizontal)
                ZStack {
                    CameraPreview(engine:engine).clipShape(RoundedRectangle(cornerRadius:28))
                    RoundedRectangle(cornerRadius:24).stroke(engine.detected ? Color.mint : .white.opacity(0.5),style:StrokeStyle(lineWidth:2,dash:[14,10])).padding(22)
                    if engine.flash { Color.white.opacity(0.5) }
                }.aspectRatio(3/4,contentMode:.fit).padding(.horizontal,12)
                Text(engine.message).font(.subheadline).foregroundStyle(engine.detected ? .mint : .white.opacity(0.7)).frame(height:40)
                HStack(spacing:45) {
                    Toggle(isOn:$auto) { Text("Авто").font(.caption) }.toggleStyle(.button).tint(.mint)
                    Button { engine.shoot() } label: { Circle().fill(.white).frame(width:70,height:70).padding(6).overlay(Circle().stroke(.white,lineWidth:2)) }.accessibilityLabel("Зняти сторінку").disabled(store.savingPhotos>0 || engine.shooting)
                    Button { engine.toggleFlash() } label: {
                        VStack(spacing:6) {
                            Image(systemName:engine.flashEnabled ? "bolt.fill" : "bolt.slash.fill").font(.title3)
                            Text(engine.flashEnabled ? "Увімк." : "Вимк.").font(.caption2)
                        }.frame(width:54,height:54)
                    }
                    .foregroundStyle(engine.flashEnabled ? Color.yellow : Color.white.opacity(0.65))
                    .accessibilityLabel(engine.flashEnabled ? "Вимкнути спалах" : "Увімкнути спалах")
                    .disabled(!engine.flashSupported || engine.shooting)
                }
                Text("Після автоматичного знімка перегорніть аркуш. Кути можна уточнити після зйомки.").font(.caption).foregroundStyle(.white.opacity(0.45)).multilineTextAlignment(.center).padding(.horizontal,30)
                Spacer(minLength:0)
            }.foregroundStyle(.white)
        }
        .onAppear { engine.captured={ image in Task { await store.addImage(image,to:documentID) } }; engine.start() }
        .onDisappear { engine.stop(); store.save() }
        .onChange(of:auto) { _,value in engine.setAuto(value) }
    }
}
