import SwiftUI

enum PageTrim {
    static let full = CGRect(x: 0, y: 0, width: 1, height: 1)

    // Coordinates are normalized from the top left of the image.
    static func rotated(_ rect: CGRect, by turns: Int) -> CGRect {
        switch (turns % 4 + 4) % 4 {
        case 1: return CGRect(x: 1 - rect.maxY, y: rect.minX, width: rect.height, height: rect.width)
        case 2: return CGRect(x: 1 - rect.maxX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
        case 3: return CGRect(x: rect.minY, y: 1 - rect.maxX, width: rect.height, height: rect.width)
        default: return rect
        }
    }

    static func apply(_ image: UIImage, rect: CGRect?, turns: Int) throws -> UIImage {
        guard let rect else { return image }
        guard let cg = image.cgImage else { throw ScanError.message("Не вдалося прочитати сторінку") }
        let region = rotated(rect, by: turns).intersection(full)
        guard !region.isNull, !region.isEmpty else { throw ScanError.message("Вкажіть область обрізки") }
        let pixels = CGRect(x: region.minX * CGFloat(cg.width), y: region.minY * CGFloat(cg.height),
                            width: region.width * CGFloat(cg.width), height: region.height * CGFloat(cg.height))
        guard let cropped = cg.cropping(to: pixels.integral) else { throw ScanError.message("Не вдалося обрізати сторінку") }
        return UIImage(cgImage: cropped)
    }

    static func combined(_ selection: CGRect, previous: CGRect?, turns: Int) -> CGRect {
        let base = rotated(previous ?? full, by: turns)
        let combined = CGRect(x: base.minX + selection.minX * base.width,
                              y: base.minY + selection.minY * base.height,
                              width: selection.width * base.width, height: selection.height * base.height)
        return rotated(combined, by: -turns).intersection(full)
    }
}

struct PageTrimView: View {
    let page: Leaf
    let save: (CGRect?) -> Void
    let cancel: () -> Void
    @State private var preview: UIImage?
    @State private var loaded = false
    @State private var rect = PageTrim.full

    var body: some View {
        VStack {
            Text("Обрізка сторінки").font(.headline)
            GeometryReader { proxy in
                if let preview, proxy.size.width > 32, proxy.size.height > 32 {
                    let scale = min((proxy.size.width - 32) / preview.size.width,
                                    (proxy.size.height - 32) / preview.size.height)
                    let size = CGSize(width: preview.size.width * scale, height: preview.size.height * scale)
                    canvas(preview, size: size)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                } else if loaded {
                    Text("Не вдалося відкрити сторінку").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Text("Перетягніть кути рамки").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Скасувати", action: cancel).frame(minHeight: 44)
                Spacer()
                if page.outputTrim != nil {
                    Button("Скинути") { save(nil) }.frame(minHeight: 44)
                    Spacer()
                }
                Button("Зберегти") {
                    save(PageTrim.combined(rect, previous: page.outputTrim, turns: page.turns))
                }.buttonStyle(.borderedProminent).disabled(preview == nil || rect == PageTrim.full)
            }.padding(.horizontal, 16)
        }
        .foregroundStyle(.white)
        .onAppear {
            ScanImageLoader.shared.load(page.output, limit: 2000) { image in
                DispatchQueue.main.async { preview = image; loaded = true }
            }
        }
    }

    private func canvas(_ preview: UIImage, size: CGSize) -> some View {
        let bounds = CGRect(origin: .zero, size: size)
        let frame = CGRect(x: rect.minX * size.width, y: rect.minY * size.height,
                           width: rect.width * size.width, height: rect.height * size.height)
        return Image(uiImage: preview).resizable().frame(width: size.width, height: size.height)
            .overlay {
                Path { path in path.addRect(bounds); path.addRect(frame) }
                    .fill(.black.opacity(0.6), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
            }
            .overlay {
                Path { $0.addRect(frame) }.stroke(.white, lineWidth: 1.5).allowsHitTesting(false)
            }
            .overlay {
                ZStack {
                    ForEach(0..<4) { corner in
                        handle(corner, frame: frame, size: size)
                    }
                }.frame(width: size.width, height: size.height)
            }
            .coordinateSpace(name: "trim-image")
    }

    private func handle(_ corner: Int, frame: CGRect, size: CGSize) -> some View {
        let left = corner.isMultiple(of: 2)
        let top = corner < 2
        return Circle().fill(.white).frame(width: 14, height: 14)
            .frame(width: 40, height: 40).contentShape(Rectangle())
            .position(x: left ? frame.minX : frame.maxX, y: top ? frame.minY : frame.maxY)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("trim-image"))
                .onChanged { value in
                    let x = min(1, max(0, value.location.x / size.width))
                    let y = min(1, max(0, value.location.y / size.height))
                    let minX = left ? min(x, rect.maxX - 0.08) : rect.minX
                    let maxX = left ? rect.maxX : max(x, rect.minX + 0.08)
                    let minY = top ? min(y, rect.maxY - 0.08) : rect.minY
                    let maxY = top ? rect.maxY : max(y, rect.minY + 0.08)
                    rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                })
            .accessibilityLabel(top ? (left ? "Верхній лівий кут" : "Верхній правий кут")
                                    : (left ? "Нижній лівий кут" : "Нижній правий кут"))
    }
}
