import SwiftUI
import ImageIO

// All disk I/O and ImageIO decompression, including thumbnails, happen off main.
final class ScanImageLoader {
    static let shared=ScanImageLoader()
    private let cache=NSCache<NSString,UIImage>()
    private let queue=OperationQueue()
    private let lock=NSLock()
    private var pending:[String:[(UIImage?)->Void]]=[:]
    private init() {
        cache.totalCostLimit=48*1024*1024;cache.countLimit=80
        queue.maxConcurrentOperationCount=2;queue.qualityOfService = .userInitiated
    }
    func image(_ file:String,limit:Int) async -> UIImage? {
        await withCheckedContinuation {continuation in
            load(file,limit:limit){continuation.resume(returning:$0)}
        }
    }
    func load(_ file:String,limit:Int,completion:@escaping(UIImage?)->Void) {
        let key=file+"@"+String(limit)
        if let found=cache.object(forKey:key as NSString) {completion(found);return}
        lock.lock()
        if pending[key] != nil {pending[key]?.append(completion);lock.unlock();return}
        pending[key]=[completion];lock.unlock()
        queue.addOperation { [self] in
            let image:UIImage?=autoreleasepool {
                let options=[kCGImageSourceShouldCache:false] as CFDictionary
                guard let source=CGImageSourceCreateWithURL(Disk.url(file) as CFURL,options),
                      let cg=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:limit,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary) else {return nil}
                return UIImage(cgImage:cg)
            }
            if let image,let cg=image.cgImage {cache.setObject(image,forKey:key as NSString,cost:cg.bytesPerRow*cg.height)}
            lock.lock();let callbacks=pending.removeValue(forKey:key) ?? [];lock.unlock()
            for callback in callbacks {callback(image)}
        }
    }
}
struct CachedScanThumbnail:View {
    let file:String?
    @State private var image:UIImage?
    var body:some View {
        ZStack {
            Color.white
            if let image {Image(uiImage:image).resizable().scaledToFit()}
            else {Image(systemName:"doc.text").foregroundStyle(Color.accent.opacity(0.5))}
        }.task(id:file) {
            image=nil
            guard let file else {return}
            let decoded=await ScanImageLoader.shared.image(file,limit:220)
            guard !Task.isCancelled else {return}
            image=decoded
        }
    }
}
