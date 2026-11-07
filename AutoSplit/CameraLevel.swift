import SwiftUI
import CoreMotion
@MainActor final class CameraLevelModel:ObservableObject {
    private let motion=CMMotionManager()
    @Published var x=0.0
    @Published var y=0.0
    @Published var angle:Double?
    func start() {
        guard motion.isDeviceMotionAvailable,!motion.isDeviceMotionActive else{return}
        motion.deviceMotionUpdateInterval=0.1
        motion.startDeviceMotionUpdates(to:.main) {[weak self] sample,_ in
            guard let self,let g=sample?.gravity else{return}
            self.x=g.x;self.y=g.y
            self.angle=atan2(hypot(g.x,g.y),-g.z)*180 / .pi
        }
    }
    func stop(){motion.stopDeviceMotionUpdates()}
}
struct CameraLevelBadge:View {
    @ObservedObject var level:CameraLevelModel
    var body:some View {
        HStack(spacing:8) {
            ZStack {
                Circle().stroke(.white.opacity(0.5),lineWidth:1).frame(width:25,height:25)
                Image(systemName:"plus").font(.caption2)
                Circle().fill(tone).frame(width:8,height:8).offset(x:max(-11,min(11,level.x*55)),y:max(-11,min(11,-level.y*55)))
            }.frame(width:32,height:32)
            Text(level.angle.map {String(format:"Рівень %.1f°",$0)} ?? "Рівень недоступний").font(.caption.monospacedDigit())
        }.foregroundStyle(tone).padding(.horizontal, 12).padding(.vertical, 4).modifier(StudioGlassCapsule()).allowsHitTesting(false)
            .accessibilityLabel("Нахил до горизонталі").accessibilityValue(level.angle.map{String(format:"%.1f градусів",$0)} ?? "недоступно")
    }
    private var tone:Color {(level.angle ?? 180)<=2 ? .green:.white}
}

