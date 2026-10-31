import SwiftUI
import VisionKit

struct LiveTextSheet:View {
    @Environment(\.dismiss) private var dismiss
    let image:UIImage
    @State private var message="Розпізнавання тексту…"
    @State private var transcript=""
    var body:some View {
        NavigationStack {
            VStack(spacing:12) {
                Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                if ImageAnalyzer.isSupported {
                    LiveTextImage(image:image) { text,error in
                        transcript=text
                        message=error ?? (text.isEmpty ? "Live Text не знайшов тексту на зображенні." : "Затисніть текст на сторінці, щоб виділити та скопіювати його.")
                    }.padding(12)
                } else {
                    ContentUnavailableView("Live Text недоступний",systemImage:"text.viewfinder",description:Text("Цей пристрій не підтримує системне виділення тексту."))
                }
            }.background(Color.canvas).navigationTitle("Текст на сторінці").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Готово"){dismiss()}}
                ToolbarItem(placement:.primaryAction){Button {UIPasteboard.general.string=transcript;message="Текст скопійовано"} label:{Image(systemName:"doc.on.doc")}.disabled(transcript.isEmpty).accessibilityLabel("Скопіювати весь текст")}
            }
        }
    }
}
struct LiveTextImage:UIViewRepresentable {
    let image:UIImage
    let completed:(String,String?)->Void
    func makeCoordinator()->Coordinator {Coordinator(completed:completed)}
    func makeUIView(context:Context)->UIImageView {
        let view=UIImageView()
        view.contentMode = .scaleAspectFit;view.isUserInteractionEnabled=true;view.clipsToBounds=true
        view.setContentHuggingPriority(.defaultLow,for:.horizontal)
        view.setContentHuggingPriority(.defaultLow,for:.vertical)
        view.setContentCompressionResistancePriority(.defaultLow,for:.horizontal)
        view.setContentCompressionResistancePriority(.defaultLow,for:.vertical)
        view.addInteraction(context.coordinator.interaction)
        return view
    }
    func updateUIView(_ view:UIImageView,context:Context) {
        guard view.image !== image else {return}
        view.image=image
        context.coordinator.analyze(image)
    }
    static func dismantleUIView(_ view:UIImageView,coordinator:Coordinator){coordinator.task?.cancel()}
    @MainActor final class Coordinator {
        let analyzer=ImageAnalyzer()
        let interaction=ImageAnalysisInteraction()
        let completed:(String,String?)->Void
        var task:Task<Void,Never>?
        init(completed:@escaping(String,String?)->Void) {
            self.completed=completed
            interaction.preferredInteractionTypes = .textSelection
        }
        func analyze(_ image:UIImage) {
            task?.cancel();interaction.analysis=nil
            task=Task { [weak self] in
                guard let self else {return}
                do {
                    let result=try await analyzer.analyze(image,configuration:ImageAnalyzer.Configuration([.text]))
                    guard !Task.isCancelled else {return}
                    interaction.analysis=result
                    completed(result.transcript,nil)
                } catch {
                    guard !Task.isCancelled else {return}
                    completed("","Live Text не зміг обробити цю сторінку. Спробуйте інший знімок.")
                }
            }
        }
    }
}
