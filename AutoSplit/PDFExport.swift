import SwiftUI
import ImageIO
import UniformTypeIdentifiers

// Runs inside the export worker, with one page's pixels alive at a time.
enum PDFImage {
    static func load(_ file:String,compression:PDFCompression) throws -> CGImage {
        let url=Disk.url(file)
        if compression == .original,
           let provider=CGDataProvider(url:url as CFURL),
           let image=CGImage(jpegDataProviderSource:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) {return image}
        guard let source=CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:compression.pixelLimit
              ] as CFDictionary) else {throw ScanError.message("Не вдалося відкрити зображення сторінки")}
        let data=NSMutableData()
        guard let destination=CGImageDestinationCreateWithData(data as CFMutableData,UTType.jpeg.identifier as CFString,1,nil) else {throw ScanError.message("Не вдалося стиснути сторінку")}
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:compression.jpegQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination),let provider=CGDataProvider(data:data as CFData),
              let jpeg=CGImage(jpegDataProviderSource:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else {throw ScanError.message("Не вдалося записати стиснену сторінку")}
        return jpeg
    }
}

struct PDFExportSheet:View {
    @EnvironmentObject var store:ScannerStore
    @Environment(\.dismiss) private var dismiss
    let ids:Set<UUID>
    @State private var compression:PDFCompression = .balanced
    @State private var sharing=false
    var count:Int {store.documents.filter{ids.contains($0.id)}.reduce(0){$0+$1.pages.count}}
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    Label("\(ids.count) документів · \(count) стор.",systemImage:"doc.on.doc")
                }
                Section {
                    ForEach(PDFCompression.allCases) { option in
                        Button {compression=option;store.shareURLs=[]} label:{
                            HStack(alignment:.top,spacing:12) {
                                VStack(alignment:.leading,spacing:5) {
                                    Text(option.rawValue).font(.body.weight(.medium)).foregroundStyle(.primary)
                                    Text(option.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength:8)
                                Image(systemName:compression==option ? "checkmark.circle.fill":"circle").foregroundStyle(Color.accent)
                            }.padding(.vertical,4)
                        }.disabled(store.busy)
                } header:{Text("Розмір PDF")} footer:{Text("Стиснення створює окремий PDF. Оригінали залишаються без змін. У стисненому PDF сторінки зберігаються як зображення.")}
                if !store.shareURLs.isEmpty {
                    Section("Готовий файл") {
                        Label(store.exportSummary,systemImage:"checkmark.circle.fill").foregroundStyle(Color.accent)
                        Button {sharing=true} label:{Label("Зберегти або поділитися",systemImage:"square.and.arrow.up")}
                    }
                }
                Section {
                    Button {
                        Task {await store.export(ids,compression:compression)}
                    } label:{HStack{Spacer();if store.busy {ProgressView()};Text(store.busy ? "Підготовка…":"Створити PDF").fontWeight(.semibold);Spacer()}}
                    .disabled(store.busy || count==0)
                }
                if let error=store.error {Section{Text(error).font(.footnote).foregroundStyle(.red)}}
            }
            .navigationTitle("Експорт PDF").navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Готово"){dismiss()}.disabled(store.busy)}}
            .sheet(isPresented:$sharing){ShareSheet(urls:store.shareURLs)}
            .onAppear{store.shareURLs=[];store.error=nil}
            .interactiveDismissDisabled(store.busy)
        }
    }
}
