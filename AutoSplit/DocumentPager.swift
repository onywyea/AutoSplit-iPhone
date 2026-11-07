import SwiftUI

struct BrowserPage:Hashable {let id:UUID;let file:String}
struct DocumentPager:UIViewControllerRepresentable {
    let pages:[BrowserPage]
    @Binding var selection:UUID
    func makeCoordinator()->Coordinator {Coordinator(self)}
    func makeUIViewController(context:Context)->UIPageViewController {
        let pager=UIPageViewController(transitionStyle:.scroll,navigationOrientation:.horizontal)
        pager.view.backgroundColor = .clear
        pager.dataSource=context.coordinator;pager.delegate=context.coordinator
        context.coordinator.controller=pager
        for case let pan as UIPanGestureRecognizer in pager.gestureRecognizers {pan.maximumNumberOfTouches=1}
        context.coordinator.reconcile(animated:false)
        return pager
    }
    func updateUIViewController(_ pager:UIPageViewController,context:Context) {
        context.coordinator.owner=self
        context.coordinator.reconcile(animated:true)
    }
    @MainActor final class Coordinator:NSObject,UIPageViewControllerDataSource,UIPageViewControllerDelegate {
        var owner:DocumentPager
        weak var controller:UIPageViewController?
        private var loaded:[UUID:DocumentPageController]=[:]
        private var transitioning=false
        private var requestedDuringSwipe=false
        private var transitionSelection:UUID?
        init(_ owner:DocumentPager){self.owner=owner}
        func page(_ descriptor:BrowserPage)->DocumentPageController {
            if let old=loaded[descriptor.id] {old.updateDescriptor(descriptor);return old}
            let page=DocumentPageController(descriptor)
            page.zoomChanged={ [weak self,weak page] zoomed in
                guard let self,let page,self.controller?.viewControllers?.first === page else {return}
                self.controller?.dataSource=zoomed ? nil:self
                for gesture in self.controller?.gestureRecognizers ?? [] {gesture.isEnabled = !zoomed}
            }
            loaded[descriptor.id]=page;return page
        }
        func reconcile(animated:Bool) {
            guard let controller,!owner.pages.isEmpty else {return}
            if transitioning {if owner.selection != transitionSelection {requestedDuringSwipe=true};return}
            let target=owner.pages.first(where:{$0.id==owner.selection}) ?? owner.pages[0]
            let visible=controller.viewControllers?.first as? DocumentPageController
            if visible?.descriptor.id==target.id {visible?.updateDescriptor(target);trim();return}
            let old=owner.pages.firstIndex(where:{$0.id==visible?.descriptor.id}) ?? 0
            let next=owner.pages.firstIndex(where:{$0.id==target.id}) ?? 0
            transitioning=true;requestedDuringSwipe=false;transitionSelection=owner.selection
            controller.dataSource=self
            controller.setViewControllers([page(target)],direction:next>=old ? .forward:.reverse,animated:animated && visible != nil) { [weak self] _ in
                guard let self else {return}
                self.transitioning=false
                controller.dataSource=self
                for gesture in controller.gestureRecognizers {gesture.isEnabled=true}
                self.trim()
                // Rapid arrow/thumbnail taps are queued, never discarded mid-transition.
                self.reconcile(animated:true)
            }
        }
        func trim() {
            guard let visible=(controller?.viewControllers?.first as? DocumentPageController)?.descriptor.id,
                  let index=owner.pages.firstIndex(where:{$0.id==visible}) else {return}
            let nearby=Set(owner.pages[max(0,index-1)...min(owner.pages.count-1,index+1)].map(\.id))
            loaded=loaded.filter {nearby.contains($0.key)}
        }
        func pageViewController(_ pageViewController:UIPageViewController,viewControllerBefore viewController:UIViewController)->UIViewController? {
            guard let page=viewController as? DocumentPageController,let index=owner.pages.firstIndex(where:{$0.id==page.descriptor.id}),index>0 else {return nil}
            return self.page(owner.pages[index-1])
        }
        func pageViewController(_ pageViewController:UIPageViewController,viewControllerAfter viewController:UIViewController)->UIViewController? {
            guard let page=viewController as? DocumentPageController,let index=owner.pages.firstIndex(where:{$0.id==page.descriptor.id}),index+1<owner.pages.count else {return nil}
            return self.page(owner.pages[index+1])
        }
        func pageViewController(_ pageViewController:UIPageViewController,willTransitionTo pendingViewControllers:[UIViewController]) {
            transitioning=true;requestedDuringSwipe=false;transitionSelection=owner.selection
        }
        func pageViewController(_ pageViewController:UIPageViewController,didFinishAnimating finished:Bool,previousViewControllers:[UIViewController],transitionCompleted completed:Bool) {
            transitioning=false
            if requestedDuringSwipe {requestedDuringSwipe=false;reconcile(animated:true);return}
            if completed,let page=pageViewController.viewControllers?.first as? DocumentPageController {owner.selection=page.descriptor.id}
            trim()
        }
    }
}
@MainActor final class DocumentPageController:UIViewController,UIScrollViewDelegate {
    private(set) var descriptor:BrowserPage
    var zoomChanged:((Bool)->Void)?
    private let scroll=UIScrollView(),picture=UIImageView()
    private let spinner=UIActivityIndicatorView(style:.medium)
    private var fitted=CGSize.zero
    private var requestedDetail=false
    init(_ descriptor:BrowserPage){self.descriptor=descriptor;super.init(nibName:nil,bundle:nil)}
    required init?(coder:NSCoder){fatalError("init(coder:) is not supported")}
    override func viewDidLoad() {
        super.viewDidLoad();view.backgroundColor = .clear
        scroll.delegate=self;scroll.minimumZoomScale=1;scroll.maximumZoomScale=5
        scroll.showsHorizontalScrollIndicator=false;scroll.showsVerticalScrollIndicator=false
        scroll.alwaysBounceHorizontal=false;scroll.alwaysBounceVertical=false
        // At normal scale only the parent pager handles one-finger horizontal drags.
        scroll.panGestureRecognizer.isEnabled=false
        picture.contentMode = .scaleAspectFit;scroll.addSubview(picture);view.addSubview(scroll)
        spinner.color = .white;view.addSubview(spinner);spinner.startAnimating()
        let tap=UITapGestureRecognizer(target:self,action:#selector(doubleTap(_:)));tap.numberOfTapsRequired=2;scroll.addGestureRecognizer(tap)
        loadImage(limit:1600)
    }
    func updateDescriptor(_ descriptor:BrowserPage) {
        guard self.descriptor != descriptor else {return}
        self.descriptor=descriptor;requestedDetail=false
        if isViewLoaded {loadImage(limit:scroll.zoomScale>1.01 ? 3000:1600)}
    }
    private func loadImage(limit:Int) {
        let file=descriptor.file
        ScanImageLoader.shared.load(file,limit:limit) { [weak self] image in
            DispatchQueue.main.async {
                guard let self,self.descriptor.file==file else {return}
                let first=self.picture.image==nil
                let oldAspect=self.picture.image.map {$0.size.width/$0.size.height}
                self.picture.image=image;self.spinner.stopAnimating()
                let changedAspect=oldAspect != nil && image != nil && abs(oldAspect!-image!.size.width/image!.size.height)>0.02
                if first || changedAspect {self.fitted = .zero;self.view.setNeedsLayout()}
            }
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews();scroll.frame=view.bounds;spinner.center=CGPoint(x:view.bounds.midX,y:view.bounds.midY)
        guard let image=picture.image else {return}
        let size=view.bounds.size
        if fitted != size {
            fitted=size;scroll.setZoomScale(1,animated:false)
            let factor=min(size.width/image.size.width,size.height/image.size.height)
            picture.frame=CGRect(origin:.zero,size:CGSize(width:image.size.width*factor,height:image.size.height*factor))
            scroll.contentSize=picture.bounds.size;centerImage()
        }
    }
    private func centerImage() {
        scroll.contentInset=UIEdgeInsets(top:max(0,(scroll.bounds.height-scroll.contentSize.height)/2),left:max(0,(scroll.bounds.width-scroll.contentSize.width)/2),bottom:0,right:0)
    }
    func viewForZooming(in scrollView:UIScrollView)->UIView? {picture}
    func scrollViewWillBeginZooming(_ scrollView:UIScrollView,with view:UIView?){zoomChanged?(true)}
    func scrollViewDidZoom(_ scrollView:UIScrollView) {
        centerImage()
        let zoomed=scrollView.zoomScale>1.01
        scroll.panGestureRecognizer.isEnabled=zoomed;zoomChanged?(zoomed)
        if zoomed && !requestedDetail {requestedDetail=true;loadImage(limit:3000)}
    }
    @objc private func doubleTap(_ recognizer:UITapGestureRecognizer) {
        if scroll.zoomScale>1.01 {scroll.setZoomScale(1,animated:true);return}
        let p=recognizer.location(in:picture),factor:CGFloat=2.5
        scroll.zoom(to:CGRect(x:p.x-scroll.bounds.width/factor/2,y:p.y-scroll.bounds.height/factor/2,width:scroll.bounds.width/factor,height:scroll.bounds.height/factor),animated:true)
    }
}
