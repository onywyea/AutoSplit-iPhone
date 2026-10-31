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
