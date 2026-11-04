import SwiftUI

struct CameraFocusControls:View {
    @ObservedObject var engine:CameraEngine
    let disabled:Bool
    var body:some View {
        HStack(spacing:12) {
            Button {engine.setSeriesFocus(!engine.seriesFocusEnabled)} label:{
                Label(engine.seriesFocusEnabled ? "Фокус серії":"Автофокус",systemImage:engine.seriesFocusEnabled ? "lock.fill":"lock.open")
            }.accessibilityValue(engine.seriesFocusEnabled ? "Одне фокусування на серію":"Безперервне фокусування")
            Spacer(minLength:0)
            Button {engine.focus(at:CGPoint(x:0.5,y:0.5))} label:{Label("Перефокусувати",systemImage:"viewfinder")}
        }.font(.caption.weight(.semibold)).padding(.horizontal,12).frame(minHeight:44)
            .background(.black.opacity(0.55),in:Capsule()).disabled(disabled)
    }
}
