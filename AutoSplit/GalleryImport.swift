import SwiftUI
import PhotosUI

extension ScannerStore {
    func importGallery(_ items:[PhotosPickerItem],to id:UUID) async {
        guard !busy else {return}
        busy=true;error=nil
        defer {busy=false;save()}
        for (position,item) in items.enumerated() {
            status="Фото з галереї \(position+1)/\(items.count)"
            do {
                guard let bytes=try await item.loadTransferable(type:Data.self) else {throw ScanError.message("Фото недоступне. Якщо воно в iCloud, перевірте інтернет.")}
                let image=try await Task.detached(priority:.userInitiated) {() throws -> UIImage in
                    guard let image=UIImage(data:bytes) else {throw ScanError.message("Не вдалося відкрити вибране фото")}
                    return Imaging.resized(image,limit:4096)
                }.value
                await addImage(image,to:id,sourceKind:"image")
            } catch {self.error=error.localizedDescription;break}
        }
    }
}
