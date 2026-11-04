import Foundation
var passed=0
func check(_ result:Bool,_ name:String) { if !result{print("FAIL: \(name)");exit(1)};passed+=1 }
func names(_ text:String)->[String] {NameFinder.candidates(text).map(\.name)}
check(names("ПІБ: Іваненко Іван Іванович")==["Іваненко Іван Іванович"],"explicit name")
check(names("Отримувач: КОВАЛЕНКО ОЛЕНА ПЕТРІВНА")==["Коваленко Олена Петрівна"],"uppercase")
check(names("Паспорт Громадянина України").isEmpty,"passport heading is not a name")
check(names("Міністерство Оборони України").isEmpty,"ministry is not a name")
check(names("Прізвище\nІВАНЕНКО\nІм’я\nІВАН\nПо батькові\nІВАНОВИЧ")==["Іваненко Іван Іванович"],"separate fields")
check(names("Іваненко Іван Іванович\nКоваленко Олена Петрівна").count==2,"keep both people")
check(names("Іваненко Іван Іванович\nІваненко Іван Іванович").count==1,"deduplicate")
check(names("Іваненко І. І.").isEmpty,"do not invent full name from initials")
check(names("Номер 1234567890").isEmpty,"no false name from number")
check(NameFinder.candidates("Загиблого військовослужбовця: Іваненко Іван Іванович").first?.explicit == true,"person context")
check(NameFinder.safeName("Іваненко/Іван:Іванович")=="Іваненко_Іван_Іванович","safe PDF path")
check(NameFinder.safeName("   ")=="Скан","empty name")
check(Quad.full.valid,"default corners")
check(!Quad(points:[.init(x:0,y:0),.init(x:1,y:1),.init(x:1,y:0),.init(x:0,y:1)]).valid,"reject crossed corners")
check(!Quad(points:[.init(x:-0.1,y:0),.init(x:1,y:0),.init(x:1,y:1),.init(x:0,y:1)]).valid,"reject outside image")
check(!Quad(points:[.init(x:0,y:0),.init(x:0.01,y:0),.init(x:0.01,y:0.01),.init(x:0,y:0.01)]).valid,"reject near-zero crop")
check(!Quad(points:[]).valid,"reject missing corners")
print("\(passed) core checks passed")
// Synthetic glyph raster: no user document text or images in the repository.
let rw=200,rh=220
var raster=[UInt8](repeating:255,count:rw*rh)
for row in 0..<10 { for col in 0..<10 {
    let x=10+col*18,y=10+row*20
    for dy in 0..<11 { for dx in 0..<5 where dx==0 || dx==4 || dy==5 {raster[(y+dy)*rw+x+dx]=0} }
} }
let upright=RasterAxis.estimate(raster,width:rw,height:rh)
check(upright.reliable && upright.evidence>0.8,"recognize horizontal glyph axis")
var sideways=[UInt8](repeating:255,count:rw*rh)
for y in 0..<rh {for x in 0..<rw {sideways[x*rh+(rh-1-y)]=raster[y*rw+x]}}
let side=RasterAxis.estimate(sideways,width:rh,height:rw)
check(side.reliable && side.evidence < -0.8,"recognize sideways glyph axis")
check(!RasterAxis.estimate([UInt8](repeating:255,count:100),width:10,height:10).reliable,"blank page has no direction")
check(RasterAxis.choose(scores:[200,500,210,600],axis:upright,manual:nil).turns==0,"upright table cannot be rotated sideways by OCR")
check(RasterAxis.choose(scores:[600,300,590,450],axis:side,manual:nil).turns==3,"sideways text rotates despite misleading OCR character count")
check(RasterAxis.choose(scores:[100,110,105,108],axis:TextAxis(horizontal:0,vertical:0,components:0),manual:nil).turns==0,"ambiguous evidence preserves original")
check(RasterAxis.choose(scores:[100,300,200,400],axis:side,manual:0).turns==0,"manual zero is respected")
check(RasterAxis.choose(scores:[100,300,200,400],axis:side,manual:2).turns==2,"manual rotation is respected")
check(RasterAxis.choose(scores:[10,0,100,0],axis:upright,manual:nil).turns==2,"clear upside-down page can rotate 180")
// Regression geometry statistics from the supplied 11-page scan; no personal data.
let suppliedEvidence:[(Int,Int,Int)]=[(650,284,1365),(302,610,1419),(782,189,1716),(828,155,1783),(731,174,1563),(434,209,1072),(480,310,1280),(285,219,705),(276,215,695),(779,141,1407),(580,182,1247)]
for (index,counts) in suppliedEvidence.enumerated() {
    let axis=TextAxis(horizontal:counts.0,vertical:counts.1,components:counts.2)
    // Deliberately misleading OCR numbers: glyph geometry must still prevent the wrong axis.
    let scores=index==1 ? [600.0,200,500,400] : [400.0,700,300,600]
    let choice=RasterAxis.choose(scores:scores,axis:axis,manual:nil)
    if axis.reliable {check(choice.turns%2 == (index==1 ? 1 : 0),"supplied page \(index+1) axis regression")}
}
print("All \(passed) core/rotation checks passed")
// Border repair regressions use generated pixels only, no private document images.
let pw=100,ph=120
func paperImage(_ border:Bool)->[UInt8] {
    var image=[UInt8](repeating:255,count:pw*ph*4)
    for y in 0..<ph {for x in 0..<pw {
        let wood=border && (x<5 || x>=pw-5 || y<5 || y>=ph-5)
        let rgb=wood ? [110,70,35] : [190+y/20,190+y/20,188+y/20]
        for c in 0..<3 {image[(y*pw+x)*4+c]=UInt8(rgb[c])}
    }}
    return image
}
let cleanPaper=paperImage(false)
check(!PaperRaster.mask(cleanPaper,width:pw,height:ph).contains(255),"clean paper is not background")
let woodPaper=paperImage(true)
let woodMask=PaperRaster.mask(woodPaper,width:pw,height:ph)
check(woodMask[0]==255 && woodMask[pw*ph/2+pw/2]==0,"wood border separated from paper")
let filledPaper=PaperRaster.extend(woodPaper,width:pw,height:ph,mask:woodMask)
check(filledPaper[0]>150 && filledPaper[2]>150,"wood replaced by local paper")
var unmaskedPixelsExact=true
for pixel in 0..<(pw*ph) where woodMask[pixel]==0 {
    let base:Int=pixel*4
    for channel in 0..<4 {
        if filledPaper[base+channel] != woodPaper[base+channel] {unmaskedPixelsExact=false}
    }
}
check(unmaskedPixelsExact,"pixels outside mask remain exact")
check(filledPaper==PaperRaster.extend(woodPaper,width:pw,height:ph,mask:woodMask),"repair is deterministic")
var blueEdge=woodPaper
for y in 0..<ph {for c in 0..<3 {blueEdge[(y*pw+2)*4+c]=[UInt8(35),40,120][c]}}
let blueMask=PaperRaster.mask(blueEdge,width:pw,height:ph)
check((0..<ph).allSatisfy {blueMask[$0*pw+2]==0},"blue ink at page edge is protected")
check(PaperRaster.extend(cleanPaper,width:pw,height:ph,mask:[UInt8](repeating:0,count:pw*ph))==cleanPaper,"empty mask does not alter paper")
check(!PaperRaster.mask(cleanPaper,width:pw,height:ph,hint:[UInt8](repeating:0,count:pw*ph)).contains(255),"invalid all-background model is rejected")
check(PaperRaster.extend(cleanPaper,width:pw,height:ph,mask:[UInt8](repeating:255,count:pw*ph))==cleanPaper,"missing donor does not fabricate paper")
print("All \(passed) core/rotation/paper checks passed")
// Wide glyphs reproduce the false-axis failure: glyph shape disagrees with whole text lines.
let fw=420,fh=320
var wideGlyphs=[UInt8](repeating:255,count:fw*fh)
for row in 0..<10 {for column in 0..<24 {
    let x=18+column*15,y=20+row*27
    for dy in 0..<6 {for dx in 0..<10 where dy==0 || dy==5 || dx==0 || dx==9 {wideGlyphs[(y+dy)*fw+x+dx]=20}}
}}
let flow=RasterFlow.estimate(wideGlyphs,width:fw,height:fh)
check(flow.reliable && flow.evidence>0.8,"wide glyph text rows remain horizontal")
check(RasterAxis.estimate(wideGlyphs,width:fw,height:fh).evidence<0,"fixture reproduces misleading individual glyph shape")
var quarterFlow=[UInt8](repeating:255,count:fw*fh)
for y in 0..<fh {for x in 0..<fw {quarterFlow[x*fh+fh-1-y]=wideGlyphs[y*fw+x]}}
let rotatedFlow=RasterFlow.estimate(quarterFlow,width:fh,height:fw)
check(rotatedFlow.reliable && rotatedFlow.evidence < -0.8,"text rows rotate with actual page direction")
check(RasterAxis.choose(scores:[100,500,90,400],axis:flow,manual:nil).turns==0,"OCR cannot rotate horizontal wide-glyph form sideways")
check(RasterAxis.choose(scores:[800,200,700,400],axis:rotatedFlow,manual:nil).turns==3,"sideways text line geometry overrides misleading OCR length")
check(!RasterFlow.estimate([UInt8](repeating:255,count:fw*fh),width:fw,height:fh).reliable,"blank page has no text-line direction")
// Same 5-page layout failure case: votes contain no text or personal data.
let newFlowStatistics=[(55256,6882),(453,160462),(77006,4167),(109392,2095),(41736,13325)]
for (index,votes) in newFlowStatistics.enumerated() {
    let a=TextAxis(horizontal:votes.0,vertical:votes.1,components:100)
    let decision=RasterAxis.choose(scores:[300,800,200,700],axis:a,manual:nil)
    check(decision.turns%2 == (index==1 ? 1:0),"current scan page \(index+1) line axis")
}
// Real overlap, not just blur inside the old background mask.
var borderMask=[UInt8](repeating:0,count:pw*ph)
for y in 0..<ph {for x in 0..<5 {borderMask[y*pw+x]=255}}
let alpha=PaperRaster.overlap(cleanPaper,width:pw,height:ph,mask:borderMask,radius:12)
check(alpha[ph/2*pw+2]==255,"background fully replaced")
check(alpha[ph/2*pw+6]==255,"solid overlap extends onto document")
check(alpha[ph/2*pw+12]>0 && alpha[ph/2*pw+12]<255,"transition feathers inside paper")
check(alpha[ph/2*pw+18]==0,"distant document interior unchanged")
var markedPaper=cleanPaper
let protectedPixel=(ph/2*pw+9)*4
markedPaper[protectedPixel]=35;markedPaper[protectedPixel+1]=40;markedPaper[protectedPixel+2]=120
let protectedAlpha=PaperRaster.overlap(markedPaper,width:pw,height:ph,mask:borderMask,radius:12)
check(protectedAlpha[protectedPixel/4]==0,"blue signature protected inside overlap")
let blend=PaperRaster.feathered(markedPaper,width:pw,height:ph,mask:borderMask)
check((0..<4).allSatisfy {blend[protectedPixel+$0]==markedPaper[protectedPixel+$0]},"protected signature survives final compositing")
check(PaperRaster.feathered(cleanPaper,width:pw,height:ph,mask:[UInt8](repeating:0,count:pw*ph))==cleanPaper,"empty repair leaves image byte-identical")
print("All \(passed) core/rotation/flow/overlap checks passed")
// Regression: an internal table must not be accepted as the complete sheet.
let tableCrop=Quad(points:[Point(x:0.10,y:0.19),Point(x:0.97,y:0.19),Point(x:0.97,y:0.61),Point(x:0.10,y:0.61)])
let heading=Quad(points:[Point(x:0.08,y:0.03),Point(x:0.84,y:0.03),Point(x:0.84,y:0.16),Point(x:0.08,y:0.16)])
let stamp=Quad(points:[Point(x:0.52,y:0.67),Point(x:0.91,y:0.67),Point(x:0.91,y:0.94),Point(x:0.52,y:0.94)])
check(!CropSafety.preserves([heading,stamp],inside:tableCrop),"internal table excludes heading and stamps")
check(!CropSafety.usable(tableCrop,content:[heading,stamp],camera:true),"reject destructive internal-frame crop")
check(CropSafety.preserves([heading,stamp],inside:.full),"full PDF page preserves all content")
let distantSheet=Quad(points:[Point(x:0.26,y:0.26),Point(x:0.62,y:0.26),Point(x:0.64,y:0.60),Point(x:0.22,y:0.60)])
check(CropSafety.usable(distantSheet,content:[],camera:true),"sheet below old 18 percent area cutoff is allowed")
check(!CropSafety.usable(.full,content:[],camera:true),"full photo is not silently reported as detected sheet")
check(CropSafety.usable(.full,content:[heading,stamp],camera:false),"complete imported PDF canvas is valid")
check(CropSafety.contains(Point(x:0.5,y:0.5),in:distantSheet),"perspective containment accepts sheet interior")
check(!CropSafety.contains(Point(x:0.9,y:0.5),in:distantSheet),"perspective containment rejects table outside sheet")
print("All \(passed) document-safety checks passed")
// Thin wooden rim must work without a Vision segmentation mask or source-kind gate.
let thinWood=paperImage(true)
let bandMask=EdgeBand.mask(thinWood,width:pw,height:ph)
check(bandMask[0]==255,"outer wooden rim is detected independently of document segmentation")
check(bandMask[ph/2*pw+pw/2]==0,"edge detector never changes document center")
check(!EdgeBand.mask(cleanPaper,width:pw,height:ph).contains(255),"clean PDF edge needs no fill")
var insetFrame=cleanPaper
for y in 12..<(ph-12) {for x in 12..<(pw-12) where y==12 || y==ph-13 || x==12 || x==pw-13 {
    let i=(y*pw+x)*4;insetFrame[i]=110;insetFrame[i+1]=70;insetFrame[i+2]=35
}}
check(!EdgeBand.mask(insetFrame,width:pw,height:ph).contains(255),"internal brown frame is not an outer background edge")
var inkBorder=cleanPaper
for y in 0..<ph {for c in 0..<3 {inkBorder[(y*pw)*4+c]=[UInt8(200),20,20][c]}}
check(!EdgeBand.mask(inkBorder,width:pw,height:ph).contains(255),"saturated red marks are not mistaken for wood")
// Larger alpha support is observable on the document side, not merely a changed UI number.
let alphaLarge=PaperRaster.overlap(cleanPaper,width:pw,height:ph,mask:borderMask,radius:24)
let alphaSmall=PaperRaster.overlap(cleanPaper,width:pw,height:ph,mask:borderMask,radius:8)
check(alphaLarge[ph/2*pw+18]>0 && alphaSmall[ph/2*pw+18]==0,"larger overlap actually extends farther onto paper")
let grainExtended=PaperRaster.feathered(thinWood,width:pw,height:ph,mask:bandMask,radius:12)
check(grainExtended[0]>150 && grainExtended[2]>150,"thin wood is replaced with nearby paper")
print("All \(passed) edge-band regressions passed")
// v0.2.7: neutral backgrounds and thin ink need different treatment.
var grayFloor=cleanPaper
for y in 0..<ph {for x in 0..<5 {for c in 0..<3 {grayFloor[(y*pw+x)*4+c]=125}}}
let grayMask=EdgeBand.mask(grayFloor,width:pw,height:ph)
check(grayMask[ph/2*pw+2]==255,"gray floor at outer edge is detected")
check(grayMask[ph/2*pw+pw/2]==0,"gray floor repair does not reach document center")
var grayRule=cleanPaper
for y in 0..<ph {for c in 0..<3 {grayRule[(y*pw)*4+c]=125}}
check(!EdgeBand.mask(grayRule,width:pw,height:ph).contains(255),"one-pixel neutral table rule is retained")
let safeBand=EdgeBand.mask(blueEdge,width:pw,height:ph)
check((0..<ph).allSatisfy{safeBand[$0*pw+2]==0},"outside envelope preserves blue ink at the boundary")
var paleWoodGap=woodPaper
for y in 0..<ph {for c in 0..<3 {paleWoodGap[(y*pw+1)*4+c]=195}}
let closedBand=EdgeBand.mask(paleWoodGap,width:pw,height:ph)
check(closedBand[ph/2*pw+1]==255,"pale gaps outside detected contour are fully covered")
check(PDFCompression.balanced.pixelLimit>PDFCompression.small.pixelLimit,"balanced export retains more pixels than small")
check(PDFCompression.original.jpegQuality>PDFCompression.balanced.jpegQuality && PDFCompression.balanced.jpegQuality>PDFCompression.small.jpegQuality,"compression quality decreases in documented order")
check(PDFCompression.allCases.allSatisfy{$0.jpegQuality>0 && $0.jpegQuality<=1 && $0.pixelLimit>=1500},"PDF profiles have valid encoding values")
print("All \(passed) core/rotation/edge/export checks passed")
// v0.2.8: colors sampled from the table fragments visible in the reported failure.
let realWoodColors:[[UInt8]]=[[151,104,85],[149,100,78],[168,116,89],[174,117,88],[158,101,70],[158,99,71],[172,123,104],[147,99,75]]
for (n,color) in realWoodColors.enumerated() {
    check(!EdgeBand.protectedInk(Int(color[0]),Int(color[1]),Int(color[2])),"real wood color \(n+1) is not a red stamp")
    var fixture=cleanPaper
    for y in 0..<ph {for x in 0..<5 {for c in 0..<3 {fixture[(y*pw+x)*4+c]=color[c]}}}
    check(EdgeBand.mask(fixture,width:pw,height:ph,margin:8)[ph/2*pw+2]==255,"real wood color \(n+1) is covered")
}
for color in [[200,20,20],[130,45,45],[35,40,120]] {
    check(EdgeBand.protectedInk(color[0],color[1],color[2]),"actual red or blue ink remains protected")
}
var fragments=cleanPaper
for y in 0..<ph {for x in 0..<5 {for c in 0..<3 {fragments[(y*pw+x)*4+c]=[UInt8(151),104,85][c]}}}
let fragment=ph/2*pw+10
for c in 0..<3 {fragments[fragment*4+c]=[UInt8(160),105,75][c]}
let marginZero=EdgeBand.mask(fragments,width:pw,height:ph,margin:0)
let marginEight=EdgeBand.mask(fragments,width:pw,height:ph,margin:8)
let marginSixteen=EdgeBand.mask(fragments,width:pw,height:ph,margin:16)
check(marginZero[fragment]==0 && marginEight[fragment]==255,"solid margin removes detached table fragment")
check(marginSixteen.filter{$0>0}.count>marginEight.filter{$0>0}.count,"margin control changes the actual replacement mask")
check(marginSixteen[ph/2*pw+pw/2]==0,"solid margin does not touch page center")
for c in 0..<3 {fragments[(ph/2*pw+9)*4+c]=20}
check(EdgeBand.mask(fragments,width:pw,height:ph,margin:8)[ph/2*pw+9]==0,"black text inside margin remains protected")
check(!EdgeBand.mask(cleanPaper,width:pw,height:ph,margin:24).contains(255),"largest margin does not activate on a clean sheet")
print("All \(passed) core/rotation/edge/export/color-regression checks passed")
// v0.2.9: cleaning cannot create a gray halo in a brighter source region.
var haloFixture=paperImage(true)
for y in 0..<ph {for x in 5..<24 {for c in 0..<3 {haloFixture[(y*pw+x)*4+c]=250}}}
let haloMask=EdgeBand.mask(haloFixture,width:pw,height:ph,margin:8)
let haloResult=PaperRaster.feathered(haloFixture,width:pw,height:ph,mask:haloMask,radius:24)
var noDarkenedChannels=true
for pixel in 0..<(pw*ph) {
    let base:Int=pixel*4
    for channel in 0..<3 {
        if haloResult[base+channel]<haloFixture[base+channel] {noDarkenedChannels=false}
    }
}
check(noDarkenedChannels,"edge repair never darkens any original color channel")
var brightStripPreserved=true
for row in 0..<ph {
    let base:Int=(row*pw+15)*4
    for channel in 0..<3 {
        if haloResult[base+channel]<250 {brightStripPreserved=false}
    }
}
check(brightStripPreserved,"bright paper inside the transition cannot turn into a gray strip")
var grainFixture=paperImage(true)
for y in 30..<70 {for c in 0..<3 {grainFixture[(y*pw+5)*4+c]=20}}
let grainMask=EdgeBand.mask(grainFixture,width:pw,height:ph,margin:8)
check(grainMask[50*pw+5]==255,"dark table grain beside warm wood is treated as background")
for y in 30..<70 {for c in 0..<3 {grainFixture[(y*pw+12)*4+c]=20}}
check(EdgeBand.mask(grainFixture,width:pw,height:ph,margin:8)[50*pw+12]==0,"a black stroke on neutral paper is still protected")
print("All \(passed) core/rotation/edge/export/color/halo checks passed")

check(!EdgeBand.protectedInk(158,152,164),"bluish JPEG noise is not blue ink")
check(!EdgeBand.protectedInk(191,178,188),"table grain with JPEG tint is not blue ink")
check(EdgeBand.protectedInk(181,190,205),"faint but chromatically blue stamp is protected")
var faintStamp=cleanPaper
let faintPoint=ph/2*pw+9
for c in 0..<3 {faintStamp[faintPoint*4+c]=[UInt8(181),190,205][c]}
let faintAlpha=PaperRaster.overlap(faintStamp,width:pw,height:ph,mask:borderMask,radius:24)
check(faintAlpha[faintPoint]==0,"faint stamp is protected inside feather, not only in base mask")
print("All \(passed) core/rotation/edge/export/color/halo/stamp checks passed")
// v0.2.10: the last brown dots were weak reddish wood, not saturated red ink.
for rgb in [[125,74,66],[141,91,80],[177,143,136],[172,136,128],[180,155,150]] {
    check(!EdgeBand.protectedInk(rgb[0],rgb[1],rgb[2]),"weak brown residual is not protected as red ink")
    var dotFixture=cleanPaper
    for y in 0..<ph {for x in 0..<5 {for c in 0..<3 {dotFixture[(y*pw+x)*4+c]=[UInt8(151),104,85][c]}}}
    for c in 0..<3 {dotFixture[(ph/2*pw+8)*4+c]=UInt8(rgb[c])}
    check(EdgeBand.mask(dotFixture,width:pw,height:ph,margin:8)[ph/2*pw+8]==255,"weak brown isolated dot is included in the replacement mask")
}
check(EdgeBand.protectedInk(130,45,45),"dark saturated red mark remains protected")
check(EdgeBand.protectedInk(200,20,20),"bright saturated red stamp remains protected")
var faintRed=cleanPaper
for c in 0..<3 {faintRed[(ph/2*pw+9)*4+c]=[UInt8(185),125,125][c]}
check(PaperRaster.overlap(faintRed,width:pw,height:ph,mask:borderMask,radius:24)[ph/2*pw+9]==0,"faint red print on paper survives the feather")
print("All \(passed) core/rotation/edge/export/color/halo/stamp/residue checks passed")

let trackingQuad=Quad(points:[Point(x:0.2,y:0.15),Point(x:0.8,y:0.15),Point(x:0.8,y:0.85),Point(x:0.2,y:0.85)])
func shiftedQuad(_ amount:Double)->Quad {Quad(points:trackingQuad.points.map {Point(x:$0.x+amount,y:$0.y)})}
let cameraSignature=(0..<256).map {UInt8(80+$0%40)}
let brighterSignature=cameraSignature.map {$0+35}
check(CaptureStability.motion(cameraSignature,brighterSignature)<0.00001,"exposure change is not page motion")
var captureTracker=CaptureStability()
var fired=false
for step in 0...5 {
    fired=captureTracker.update(shiftedQuad(step%2==0 ? 0:0.009),signature:step%2==0 ? cameraSignature:brighterSignature,time:Double(step)*0.21,focusing:false) || fired
}
check(fired,"small hand jitter and exposure changes still allow capture")
captureTracker.didCapture()
for step in 6...18 {
    check(!captureTracker.update(shiftedQuad(step%2==0 ? 0:0.009),signature:brighterSignature,time:Double(step)*0.21,focusing:false),"same page cannot trigger duplicate capture")
}
_ = captureTracker.update(nil,signature:[],time:4.0,focusing:false)
check(captureTracker.quad != nil && !captureTracker.armed,"one contour dropout retains outline and does not rearm")
for step in 1...4 {_ = captureTracker.update(nil,signature:[],time:4.0+Double(step)*0.21,focusing:false)}
check(captureTracker.quad==nil && captureTracker.armed,"removing the sheet rearms camera")
var focusTracker=CaptureStability()
var focusedCapture=false
for step in 0...9 {focusedCapture=focusTracker.update(trackingQuad,signature:cameraSignature,time:Double(step)*0.21,focusing:true) || focusedCapture}
check(!focusedCapture,"active autofocus never times out into capture")
var shakyTracker=CaptureStability()
for step in 0...12 {
    check(!shakyTracker.update(shiftedQuad(step%2==0 ? 0:0.15),signature:cameraSignature,time:Double(step)*0.21,focusing:false),"large movement must not auto capture")
}
var droppedTracker=CaptureStability()
_ = droppedTracker.update(trackingQuad,signature:cameraSignature,time:0,focusing:false)
_ = droppedTracker.update(trackingQuad,signature:cameraSignature,time:0.21,focusing:false)
_ = droppedTracker.update(trackingQuad,signature:cameraSignature,time:0.42,focusing:false)
_ = droppedTracker.update(nil,signature:[],time:0.63,focusing:false)
_ = droppedTracker.update(trackingQuad,signature:cameraSignature,time:0.84,focusing:false)
check(droppedTracker.update(trackingQuad,signature:cameraSignature,time:1.05,focusing:false),"single missed frame does not restart stable hold")
print("All \(passed) checks including camera hysteresis passed")

let lw=120,lh=160
var uniformSheet=[UInt8](repeating:255,count:lw*lh*4)
for pixel in 0..<(lw*lh) {for c in 0..<3 {uniformSheet[pixel*4+c]=200}}
let uniformCorrected=PaperLighting.correct(uniformSheet,width:lw,height:lh)
check(uniformCorrected[0]==255 && uniformCorrected[(lh/2*lw+lw/2)*4]==255,"uniform paper becomes white")
var shadowSheet=uniformSheet
for y in 0..<lh {for x in 0..<lw {
    let value:UInt8=y>lh/2 ? 170:220
    for c in 0..<3 {shadowSheet[(y*lw+x)*4+c]=value}
}}
let shadowCorrected=PaperLighting.correct(shadowSheet,width:lw,height:lh)
check(shadowCorrected[(lh/4*lw+lw/2)*4]>245 && shadowCorrected[(lh*3/4*lw+lw/2)*4]>245,"both sides of broad shadow normalize")
var denseCopy=uniformSheet
for y in 12..<(lh-12) {for x in 10..<(lw-10) {
    let value:UInt8=(x+y)%2==0 ? 140:180
    for c in 0..<3 {denseCopy[(y*lw+x)*4+c]=value}
}}
let denseCorrected=PaperLighting.correct(denseCopy,width:lw,height:lh)
check(denseCorrected[(lh/2*lw+lw/2)*4]<200,"dense photocopy is not mistaken for white paper")
var blueSheet=uniformSheet
let mark=(lh/2*lw+lw/2)*4
blueSheet[mark]=20;blueSheet[mark+1]=40;blueSheet[mark+2]=140
let blueCorrected=PaperLighting.correct(blueSheet,width:lw,height:lh)
check(Int(blueCorrected[mark+2])-Int(blueCorrected[mark])>100,"blue ink remains blue under illumination correction")
var lightOnly=true,alphaExact=true
for pixel in 0..<(lw*lh) {
    for c in 0..<3 {if denseCorrected[pixel*4+c]<denseCopy[pixel*4+c] {lightOnly=false}}
    if denseCorrected[pixel*4+3] != denseCopy[pixel*4+3] {alphaExact=false}
}
check(lightOnly && alphaExact,"lighting does not add dark halos or alter alpha")
check(PaperLighting.correct([0,1,2],width:120,height:160)==[0,1,2],"invalid lighting buffer is rejected")
print("All \(passed) checks including local paper lighting passed")

var qualityHold=FocusQualityHold()
let sharpDetail=TextDetail(acutance:0.7,patches:6),blurredDetail=TextDetail(acutance:0.2,patches:6)
check(!qualityHold.update(position:0.5,adjusting:false,detail:sharpDetail,time:0),"first lens reading cannot confirm focus")
check(!qualityHold.update(position:0.5,adjusting:false,detail:sharpDetail,time:0.21),"focus needs consecutive quiet frames")
check(qualityHold.update(position:0.5,adjusting:false,detail:sharpDetail,time:0.42),"quiet lens and clear detail become ready")
check(!qualityHold.update(position:0.5,adjusting:true,detail:sharpDetail,time:0.63),"active autofocus invalidates quality")
check(!qualityHold.update(position:0.5,adjusting:false,detail:blurredDetail,time:0.84),"blurred detail cannot confirm focus")
check(!qualityHold.update(position:0.5,adjusting:false,detail:sharpDetail,time:2),"stale frames cannot confirm focus")
check(!TextDetail.measure([UInt8](repeating:220,count:120*160),width:120,height:160,quad:.full).clear,"blank paper is not proof of sharp text")
print("All \(passed) checks including focus quality passed")

qualityHold.reset()
_ = qualityHold.update(position:0.5,adjusting:false,detail:sharpDetail,time:0)
_ = qualityHold.update(position:0.5,adjusting:false,detail:sharpDetail,time:0.21)
check(!qualityHold.update(position:0.52,adjusting:false,detail:sharpDetail,time:0.42),"lens movement invalidates a quiet hardware flag")
check(!qualityHold.update(position:0.52,adjusting:false,detail:TextDetail(acutance:0.9,patches:1),time:0.63),"single sharp patch is insufficient")
var edgeChart=[UInt8](repeating:230,count:120*160)
for y in 0..<160 {for x in 0..<120 {if y%16<8 && x%8<3 {edgeChart[y*120+x]=40}}}
let clearChart=TextDetail.measure(edgeChart,width:120,height:160,quad:.full)
var blurredChart=edgeChart
for _ in 0..<5 {
    let previous=blurredChart
    for y in 1..<159 {for x in 1..<119 {
        var sum=0
        for dy in -1...1 {for dx in -1...1 {sum+=Int(previous[(y+dy)*120+x+dx])}}
        blurredChart[y*120+x]=UInt8(sum/9)
    }}
}
let softChart=TextDetail.measure(blurredChart,width:120,height:160,quad:.full)
check(clearChart.clear && !softChart.clear,"sharp text-like strokes pass; broadened strokes fail")
check(PDFCompression.original.pixelLimit==4096,"maximum-quality loading retains new capture detail")
print("All \(passed) checks including detail chart passed")

var faintStroke=[UInt8](repeating:255,count:40*40*4)
for y in 5..<35 {for c in 0..<3 {faintStroke[(y*40+20)*4+c]=170}}
let detailedStroke=DocumentDetail.enhance(faintStroke,width:40,height:40)
check(detailedStroke[(20*40+20)*4]<170,"faint thin stroke receives bounded dark-side detail")
check(detailedStroke[(20*40+19)*4]==255,"white side remains white without a bright halo")
check(DocumentDetail.enhance([UInt8](repeating:210,count:40*40*4),width:40,height:40)==[UInt8](repeating:210,count:40*40*4),"flat paper is unchanged by detail enhancement")
var bounded=true
for p in 0..<(40*40) {
    for c in 0..<3 {let i=p*4+c;let delta=Int(faintStroke[i])-Int(detailedStroke[i]);if delta<0 || delta>20 {bounded=false}}
    if faintStroke[p*4+3] != detailedStroke[p*4+3] {bounded=false}
}
check(bounded,"detail cannot brighten RGB, darken by over 20, or change alpha")
check(!CaptureSampling.sufficient(Quad(points:[Point(x:0.3,y:0.3),Point(x:0.7,y:0.3),Point(x:0.7,y:0.7),Point(x:0.3,y:0.7)])),"distant small sheet does not pass sampling check")
check(CaptureSampling.sufficient(Quad(points:[Point(x:0.1,y:0.08),Point(x:0.9,y:0.08),Point(x:0.9,y:0.92),Point(x:0.1,y:0.92)])),"frame-filling sheet passes sampling check")
check(!TextDetail(acutance:0.45,patches:6).clear,"borderline soft detail is no longer auto-accepted")
print("All \(passed) checks including bounded text detail passed")

var fastLens=LensSettleHold()
check(!fastLens.update(position:0.5,adjusting:false,time:0),"fast lens first sample cannot confirm readiness")
check(fastLens.update(position:0.5,adjusting:false,time:0.21),"fixed-focus camera settles without text or size input")
check(!fastLens.update(position:0.6,adjusting:false,time:0.42),"real lens movement still delays auto capture")
check(!fastLens.update(position:0.6,adjusting:true,time:0.63),"active autofocus still delays automatic exposure")
fastLens.reset()
_ = fastLens.update(position:0,adjusting:false,time:0)
check(fastLens.update(position:0,adjusting:false,time:1.1),"slower contour analysis does not indefinitely stall a quiet lens")
check(!fastLens.update(position:0,adjusting:false,time:3.0),"very stale lens observations reset readiness")
var noTextTracker=CaptureStability()
var noTextReady=false
for n in 0...6 {noTextReady=noTextTracker.update(trackingQuad,signature:[],time:Double(n)*0.21,focusing:false) || noTextReady}
check(noTextReady,"a stable document can auto capture with no text signature")
print("All \(passed) checks including fast capture passed")

let fringeW=240,fringeH=320
let fringeBlank=[UInt8](repeating:255,count:fringeW*fringeH*4)
var fringeSheet=fringeBlank
for x in 8..<232 where x<80 || (x>88 && x<156) || x>165 {
    let p=((fringeH-7)*fringeW+x)*4
    fringeSheet[p]=150;fringeSheet[p+1]=165;fringeSheet[p+2]=185
}
let fringeMask=EdgeFringe.mask(fringeSheet,width:fringeW,height:fringeH,margin:24)
check(fringeMask[(fringeH-7)*fringeW+40]==255,"detached gray blue edge fragments seed their own cleanup")
check(fringeMask[(fringeH/2)*fringeW+40]==0,"interior remains outside fringe cleanup")
check(!EdgeFringe.mask(fringeBlank,width:fringeW,height:fringeH).contains(255),"blank paper does not create a fringe")
var localizedStamp=fringeBlank
for y in (fringeH-10)..<fringeH {for x in 80..<110 {let p=(y*fringeW+x)*4;localizedStamp[p]=35;localizedStamp[p+1]=70;localizedStamp[p+2]=180}}
check(!EdgeFringe.mask(localizedStamp,width:fringeW,height:fringeH).contains(255),"localized saturated blue stamp is retained")
var thickContent=fringeBlank
for y in (fringeH-20)..<fringeH {for x in 0..<fringeW {for c in 0..<3 {thickContent[(y*fringeW+x)*4+c]=120}}}
check(!EdgeFringe.mask(thickContent,width:fringeW,height:fringeH).contains(255),"thick content is not a hairline")
check(DocumentDetail.enhance(faintStroke,width:40,height:40,amount:0)==faintStroke,"zero detail strength preserves exact pixels")
let gentleDetail=DocumentDetail.enhance(faintStroke,width:40,height:40,amount:0.25)
let strongDetail=DocumentDetail.enhance(faintStroke,width:40,height:40,amount:1.5)
check(strongDetail[(20*40+20)*4]<gentleDetail[(20*40+20)*4],"detail slider changes stroke intensity")
let certificateNames=NameFinder.candidates("Прізвище Коваленко\nім’я Іван   по батькові Петрович")
check(certificateNames.contains {$0.name=="Коваленко Іван Петрович" && $0.explicit},"certificate fields sharing a row form a named candidate")
check(NameFinder.plausiblePerson("Коваленко Іван Петрович"),"complete patronymic is a provisional person candidate")
check(!NameFinder.plausiblePerson("Державна Податкова Служба"),"organization is not a person candidate")
print("All \(passed) checks including edge fringe, detail controls and certificate fields passed")
var insetFringe=fringeBlank
for x in 8..<232 {for c in 0..<3 {insetFringe[((fringeH-21)*fringeW+x)*4+c]=160}}
check(!EdgeFringe.mask(insetFringe,width:fringeW,height:fringeH,margin:0).contains(255),"zero fringe margin does not reach an inset line")
check(EdgeFringe.mask(insetFringe,width:fringeW,height:fringeH,margin:24)[(fringeH-21)*fringeW+100]==255,"fringe margin slider extends the actual search depth")

var lastPass=[UInt8](repeating:255,count:240*320*4)
for x in [8,9,40,41,42,100,101,102] {for c in 0..<3 {lastPass[((320-4)*240+x)*4+c]=244}}
let lastPassResult=RimSeal.apply(lastPass,width:240,height:320)
check(lastPassResult.changed>0,"final seal finds isolated faint fragments without a long-line vote")
check(lastPassResult.pixels[((320-4)*240+40)*4]==255,"faint bottom residue is replaced with actual nearby paper")
check(lastPassResult.pixels[(100*240+40)*4]==lastPass[(100*240+40)*4],"final seal leaves the interior exact")
var rimGlyph=[UInt8](repeating:255,count:240*320*4)
for y in 314..<320 {for x in 100..<103 {for c in 0..<3 {rimGlyph[(y*240+x)*4+c]=40}}}
check(RimSeal.apply(rimGlyph,width:240,height:320).pixels==rimGlyph,"glyph thickness and inner-rim contact are protected")
var rimBlue=[UInt8](repeating:255,count:240*320*4)
for x in 20..<200 {let p=((320-3)*240+x)*4;rimBlue[p]=20;rimBlue[p+1]=60;rimBlue[p+2]=180}
check(RimSeal.apply(rimBlue,width:240,height:320).pixels==rimBlue,"saturated colored stamp line is not a paper residue")
let rimBlank=[UInt8](repeating:220,count:240*320*4)
check(RimSeal.apply(rimBlank,width:240,height:320).pixels==rimBlank,"uniform natural paper is not brightened into a band")
check(RimSeal.apply(lastPassResult.pixels,width:240,height:320).pixels==lastPassResult.pixels,"final edge seal is idempotent on isolated fragments")
check(RimSeal.apply([1,2,3],width:240,height:320).pixels==[1,2,3],"invalid seal buffer is unchanged")
var sealSafe=true
for i in lastPass.indices {
    if i%4==3 {if lastPass[i] != lastPassResult.pixels[i] {sealSafe=false}}
    
}
for p in 0..<(240*320) {
    let i=p*4
    let before=54*Int(lastPass[i])+183*Int(lastPass[i+1])+19*Int(lastPass[i+2])
    let after=54*Int(lastPassResult.pixels[i])+183*Int(lastPassResult.pixels[i+1])+19*Int(lastPassResult.pixels[i+2])
    if after<before {sealSafe=false}
}
check(sealSafe,"final seal cannot lower luminance or change alpha")
print("All \(passed) checks including final rim seal passed")
var warmResidue=[UInt8](repeating:240,count:240*320*4)
let warmPixel=((320-3)*240+80)*4
warmResidue[warmPixel]=250;warmResidue[warmPixel+1]=220;warmResidue[warmPixel+2]=200
let neutralized=RimSeal.apply(warmResidue,width:240,height:320)
check(Array(neutralized.pixels[warmPixel..<(warmPixel+3)])==[240,240,240],"warm residue replaces all channels without keeping a red wood channel")
var slopingResidue=[UInt8](repeating:255,count:960*1280*4)
for x in 20..<940 {let d=2+x/160;for c in 0..<3 {slopingResidue[((1280-1-d)*960+x)*4+c]=240}}
let sealedSlope=RimSeal.apply(slopingResidue,width:960,height:1280)
check(sealedSlope.pixels[((1280-1-5)*960+500)*4]==255,"a slanted one-pixel edge uses local thickness instead of a tall bounding box")
print("All \(passed) checks including warm and slanted rim residues passed")
var faintRimGlyph=[UInt8](repeating:255,count:240*320*4)
for y in 314..<320 {for x in 100..<103 {for c in 0..<3 {faintRimGlyph[(y*240+x)*4+c]=235}}}
check(RimSeal.apply(faintRimGlyph,width:240,height:320).pixels==faintRimGlyph,"local contrast preserves faint glyph-shaped content in the rim")

print("All \(passed) checks passed, including final edge protection")

// Fast swaps: identical sheet geometry and desk, changed text inside paper.
func pageFixture(_ variant:Int,shift:Int=0,exposure:Int=0)->[UInt8] {
    let w=PageFingerprint.width,h=PageFingerprint.height
    var gray=[UInt8](repeating:UInt8(210+exposure),count:w*h)
    for y in 10..<(h-10) {for x in 10..<(w-10) {
        let xx=x-shift
        let ink=variant==0 ? (y%7==0 && xx%11<7):(y%5==0 && xx%13<9)
        if ink {gray[y*w+x]=UInt8(70+exposure)}
    }}
    return PageFingerprint.make(gray)
}
let pageA=pageFixture(0),pageB=pageFixture(1)
check(PageFingerprint.changed(pageA,pageB),"different text at the same corners is a new page")
check(!PageFingerprint.changed(pageA,pageFixture(0,exposure:25)),"exposure pulse alone is not a page swap")
check(!PageFingerprint.changed(pageA,pageFixture(0,shift:1)),"one-pixel registration jitter is not a page swap")
check(!PageFingerprint.changed([],pageB),"missing fingerprint is not permission to duplicate")
let blankFingerprint=PageFingerprint.make([UInt8](repeating:230,count:96*128))
check(!PageFingerprint.changed(blankFingerprint,blankFingerprint),"blank paper stays disarmed")
var fastSwap=CaptureStability()
for step in 0...5 {_ = fastSwap.update(trackingQuad,signature:cameraSignature,time:Double(step)*0.21,focusing:false,pageContent:pageA)}
fastSwap.didCapture()
var swappedReady=false
for step in 6...12 {
    swappedReady=fastSwap.update(trackingQuad,signature:cameraSignature,time:Double(step)*0.21,focusing:false,pageContent:pageB) || swappedReady
}
check(swappedReady,"fast swap rearms without missing contour or changing desk signature")
fastSwap.didCapture()
for step in 13...23 {
    check(!fastSwap.update(trackingQuad,signature:cameraSignature,time:Double(step)*0.21,focusing:false,pageContent:pageB),"newly captured replacement is not duplicated")
}
print("All \(passed) checks including fast page replacement passed")

func bodyEvidence(_ lines:[String])->OrientationReading {
    var result=OrientationReading()
    for text in lines {
        let line=OrientationText.line(text,confidence:0.92)
        result.score+=line.score;result.anchors+=line.anchors;result.lines+=line.lines
    }
    return result
}
let sparseBody=bodyEvidence(["Командир військової частини", "Підтверджую достовірність внесення персональних даних", "Власне ім’я та прізвище", "Начальника штабу заступника командира"])
let noisySeal=bodyEvidence(["України код Україна", "абвгдеж зийклмноп рстуфхцч", "України", "код 26651975"])
check(OrientationText.choose([sparseBody,OrientationReading(),noisySeal,OrientationReading()],manual:nil).turns==0,"signature page keeps readable body upright despite seal")
check(OrientationText.choose([noisySeal,sparseBody,OrientationReading(),OrientationReading()],manual:nil).turns==1,"sideways form follows body vocabulary clockwise")
check(OrientationText.choose([noisySeal,OrientationReading(),OrientationReading(),sparseBody],manual:nil).turns==3,"sideways signature page follows body counterclockwise")
check(OrientationText.choose([noisySeal,OrientationReading(),sparseBody,OrientationReading()],manual:nil).turns==2,"genuinely upside-down text still turns upright")
check(OrientationText.choose([sparseBody,OrientationReading(),sparseBody,OrientationReading()],manual:nil).turns==0,"tied readings do not silently flip the page")
check(OrientationText.choose([OrientationReading(),OrientationReading(),noisySeal,OrientationReading()],manual:nil).turns==0,"isolated seal cannot invert a page")
check(OrientationText.choose([sparseBody,sparseBody,sparseBody,sparseBody],manual:3).turns==3,"manual direction is preserved")
print("All \(passed) checks including sparse and stamped page orientation passed")

let sidewaysAxis=TextAxis(horizontal:15,vertical:120,components:200)
var leftReading=OrientationReading();leftReading.rawScore=300
var rightReading=OrientationReading();rightReading.rawScore=20
check(OrientationText.choose([OrientationReading(),leftReading,OrientationReading(),rightReading],axis:sidewaysAxis,manual:nil).turns==1,"sideways text rotates without dictionary anchors")
check(OrientationText.choose([OrientationReading(),rightReading,OrientationReading(),leftReading],axis:sidewaysAxis,manual:nil).turns==3,"raw OCR resolves opposite quarter-turn")
check(OrientationText.choose([OrientationReading(),OrientationReading(),OrientationReading(),OrientationReading()],axis:sidewaysAxis,manual:nil).turns==1,"ambiguous words cannot cancel reliable sideways axis")
check(OrientationText.choose([OrientationReading(),leftReading,OrientationReading(),rightReading],axis:sidewaysAxis,manual:0).turns==0,"manual upright overrides sideways analysis")
check(ScanNaming.compose("Дяпкін Денис Володимирович",suffix:"_ПКМУ168_мати")=="Дяпкін_ДВ_ПКМУ168_мати","Ukrainian surname initials and relative suffix")
check(ScanNaming.compose("Дяпкін_ДВ",suffix:" ПКМУ975  ")=="Дяпкін_ДВ_ПКМУ975","short name stays stable")
check(ScanNaming.suffix("__ПКМУ168__мати / дочка ")=="ПКМУ168_мати_дочка","suffix normalization removes spaces and invalid separators")
check(ScanNaming.shortName("Мій власний скан")=="Мій власний скан","custom title stays intact")
print("All \(passed) checks including naming and sideways regression passed")

// Wide glyphs deliberately contradict the simplistic letter-aspect heuristic.
let lineW=320,lineH=320
var wideLetters=[UInt8](repeating:255,count:lineW*lineH)
for row in 0..<8 {for col in 0..<14 {
    let x=12+col*20,y=12+row*35
    for dy in 0..<7 {for dx in 0..<12 where dy==0 || dy==6 || dx==5 {wideLetters[(y+dy)*lineW+x+dx]=0}}
}}
let wideAxis=RasterAxis.estimate(wideLetters,width:lineW,height:lineH)
check(wideAxis.reliable && wideAxis.evidence>0,"line spacing overrides wide upright letter shapes")
var sideLetters=[UInt8](repeating:255,count:lineW*lineH)
for y in 0..<lineH {for x in 0..<lineW {sideLetters[x*lineH+(lineH-1-y)]=wideLetters[y*lineW+x]}}
let sideAxis=RasterAxis.estimate(sideLetters,width:lineH,height:lineW)
check(sideAxis.reliable && sideAxis.evidence<0,"sideways line spacing overrides tall rotated letter shapes")
print("All \(passed) scanner checks passed")
