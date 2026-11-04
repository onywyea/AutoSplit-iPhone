import Foundation

struct RimSealResult {let pixels:[UInt8];let changed:Int}
// Final raster-only pass, after illumination and detail. Handles disconnected,
// faint edge fragments. Components with glyph/stamp thickness or contact with
// the inner boundary are retained; only thin residues in the outer rim qualify.
enum RimSeal {
    private static func luma(_ r:Int,_ g:Int,_ b:Int)->Int {
        let red:Int=54*r
        let green:Int=183*g
        let blue:Int=19*b
        return red+green+blue
    }
    static func apply(_ rgba:[UInt8],width w:Int,height h:Int)->RimSealResult {
        guard w>=80,h>=80,rgba.count==w*h*4 else {return RimSealResult(pixels:rgba,changed:0)}
        let depth=max(6,min(24,min(w,h)/80))
        let thin=max(2,min(6,depth/3))
        var output=rgba
        var changed=0
        for side in 0..<4 {
            let length=side<2 ? w:h
            func index(_ a:Int,_ d:Int)->Int {
                switch side {
                case 0:return d*w+a
                case 1:return (h-1-d)*w+a
                case 2:return a*w+d
                default:return a*w+w-1-d
                }
            }
            var donor=[Int](repeating:0,count:length*3)
            var valid=[Bool](repeating:false,count:length)
            // Sample paper behind the narrow strip. Textured or colored donors
            // invalidate the column; never copy a neighboring letter into it.
            for a in 0..<length {
                var red=[Int](),green=[Int](),blue=[Int]()
                for delta in [3,7,11] {
                    let p=index(a,depth+delta)*4
                    red.append(Int(rgba[p]));green.append(Int(rgba[p+1]));blue.append(Int(rgba[p+2]))
                }
                red.sort();green.sort();blue.sort()
                let r=red[1],g=green[1],b=blue[1]
                let spread=max(r,max(g,b))-min(r,min(g,b))
                let variation=max(red[2]-red[0],max(green[2]-green[0],blue[2]-blue[0]))
                if r+g+b>=420 && spread<=45 && variation<=24 {
                    valid[a]=true;donor[a*3]=r;donor[a*3+1]=g;donor[a*3+2]=b
                }
            }
            // Separate glyph-shaped local contrast from a smooth contact shadow.
            // This protects faint text before continuing flat paper into the rim.
            var ink=[UInt8](repeating:0,count:length*depth)
            for a in 0..<length {
                for d in 0..<depth {
                    let p=index(a,d)*4
                    let sum=Int(rgba[p])+Int(rgba[p+1])+Int(rgba[p+2])
                    var bright=sum
                    for (aa,dd) in [(max(0,a-4),d),(min(length-1,a+4),d),(a,max(0,d-4)),(a,d+4)] {
                        let q=index(aa,dd)*4
                        bright=max(bright,Int(rgba[q])+Int(rgba[q+1])+Int(rgba[q+2]))
                    }
                    if bright-sum>=24 {ink[d*length+a]=1}
                }
            }
            var protected=[Bool](repeating:false,count:length*depth)
            for seed in ink.indices where ink[seed]==1 {
                var queue=[seed],head=0
                ink[seed]=2
                var low=depth,high=0
                while head<queue.count {
                    let p=queue[head];head+=1
                    let a=p%length,d=p/length
                    low=min(low,d);high=max(high,d)
                    for dd in max(0,d-1)...min(depth-1,d+1) {for aa in max(0,a-1)...min(length-1,a+1) {
                        let q=dd*length+aa
                        if ink[q]==1 {ink[q]=2;queue.append(q)}
                    }}
                }
                // A sloping hairline is protected here during the soft-paper step,
                // then evaluated by local thickness in the residue step below.
                if high-low+1>thin || high==depth-1 {
                    for p in queue {
                        let a=p%length,d=p/length
                        for dd in max(0,d-1)...min(depth-1,d+1) {for aa in max(0,a-1)...min(length-1,a+1) {protected[dd*length+aa]=true}}
                    }
                }
            }
            for a in 0..<length where valid[a] {
                for d in 0..<depth where !protected[d*length+a] {
                    let p=index(a,d)*4
                    let r=Int(output[p]),g=Int(output[p+1]),b=Int(output[p+2])
                    let spread=max(r,max(g,b))-min(r,min(g,b))
                    let dark=max(donor[a*3]-r,max(donor[a*3+1]-g,donor[a*3+2]-b))
                    guard dark>0,dark<=35,spread<=45 else {continue}
                    let oldLuma=luma(r,g,b)
                    let newLuma=luma(donor[a*3],donor[a*3+1],donor[a*3+2])
                    guard newLuma>=oldLuma else {continue}
                    let start=depth/2
                    let alpha=d<=start ? 1.0:Double(depth-d)/Double(depth-start)
                    for c in 0..<3 {
                        let mixed=Double(output[p+c])*(1-alpha)+Double(donor[a*3+c])*alpha
                        output[p+c]=UInt8(max(0,min(255,Int(mixed.rounded()))))
                    }
                    let mixedLuma=luma(Int(output[p]),Int(output[p+1]),Int(output[p+2]))
                    if mixedLuma<oldLuma {output[p]=UInt8(r);output[p+1]=UInt8(g);output[p+2]=UInt8(b)}
                    else {changed+=1}
                }
            }
            var candidate=[UInt8](repeating:0,count:length*depth)
            for a in 0..<length where valid[a] {
                for d in 0..<depth {
                    let p=index(a,d)*4
                    let r=Int(output[p]),g=Int(output[p+1]),b=Int(output[p+2])
                    let spread=max(r,max(g,b))-min(r,min(g,b))
                    let dark=max(donor[a*3]-r,max(donor[a*3+1]-g,donor[a*3+2]-b))
                    let warm=r-b>15 && g-b>1 && !EdgeBand.protectedInk(r,g,b)
                    if dark>=5 && (spread<65 || warm) {candidate[d*length+a]=1}
                }
            }
            for seed in candidate.indices where candidate[seed]==1 {
                var queue=[seed],head=0
                candidate[seed]=2
                var lowA=length,highA=0
                var columns:[Int:(low:Int,high:Int)]=[:]
                while head<queue.count {
                    let p=queue[head];head+=1
                    let a=p%length,d=p/length
                    lowA=min(lowA,a);highA=max(highA,a)
                    let old=columns[a] ?? (low:d,high:d)
                    columns[a]=(min(old.low,d),max(old.high,d))
                    for dd in max(0,d-1)...min(depth-1,d+1) {
                        for aa in max(0,a-1)...min(length-1,a+1) {
                            let q=dd*length+aa
                            if candidate[q]==1 {candidate[q]=2;queue.append(q)}
                        }
                    }
                }
                // Measure thickness perpendicular to the edge at each column.
                // A curved/slanted one-pixel border is still a thin border.
                let safeColumns=columns.filter {$0.value.high<depth-1 && $0.value.high-$0.value.low+1<=thin}
                let thickness=safeColumns.values.map {$0.high-$0.low+1}.max() ?? depth
                let width=highA-lowA+1
                // A compact spot of <=4 pixels or a long thin fragment qualifies.
                let residue=queue.count<=4 || width>=thickness*3
                // A thin bottom edge may meet a vertical edge at a corner. Do not
                // let a few corner columns veto the complete horizontal strip.
                guard !columns.isEmpty,safeColumns.count*100>=columns.count*95,residue else {continue}
                for p in queue {
                    let a=p%length,d=p/length,q=index(a,d)*4
                    guard safeColumns[a] != nil else {continue}
                    let oldR=Int(output[q]),oldG=Int(output[q+1]),oldB=Int(output[q+2])
                    let newR=donor[a*3],newG=donor[a*3+1],newB=donor[a*3+2]
                    let oldLuma=luma(oldR,oldG,oldB)
                    let newLuma=luma(newR,newG,newB)
                    guard newLuma>=oldLuma else {continue}
                    // Replace all RGB channels together. max(original,donor) can
                    // retain a warm wood channel as a pale colored edge fragment.
                    output[q]=UInt8(newR);output[q+1]=UInt8(newG);output[q+2]=UInt8(newB)
                    changed+=1
                }
            }
        }
        return RimSealResult(pixels:output,changed:changed)
    }
}
