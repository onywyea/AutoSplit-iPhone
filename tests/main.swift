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
check((0..<(pw*ph)).allSatisfy {p in woodMask[p] != 0 || (0..<4).allSatisfy {filledPaper[p*4+$0]==woodPaper[p*4+$0]}},"pixels outside mask remain exact")
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
