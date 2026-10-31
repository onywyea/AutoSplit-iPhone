import Foundation

enum NameFinder {
    static func candidates(_ text: String) -> [NameCandidate] {
        let upper = "[А-ЯІЇЄҐ]"
        let lower = "[а-яіїєґ’'ʼ-]"
        let word = "(?:\(upper)\(lower){1,}|\(upper){2,}(?:[-’'ʼ]\(upper)+)*)"
        let triple = "\(word)[ \\t]+\(word)[ \\t]+\(word)"
        guard let re = try? NSRegularExpression(pattern:triple) else { return [] }
        let lines=text.components(separatedBy:.newlines)
        var found: [String:NameCandidate] = [:]
        let excluded = ["міністерств", "військово", "експертн", "територіальн", "українськ", "державн", "банківськ", "реєстраційн", "одноразов", "свідоцтво", "головне управління", "районний", "обласний", "збройних", "військовий", "довідк", "командир", "паспорт", "громадян", "прізвище", "по батькові"]
        for (index,line) in lines.enumerated() {
            let ns=line as NSString
            let context=([index>0 ? lines[index-1] : "",line]).joined(separator:" ").lowercased()
            let explicit = context.range(of:"п[іi]б|ф[іi]о|прізвище.*ім.?я|отримувач|одержувач|військовослужбов(?:ець|ця)|загибл(?:ий|ого)",options:.regularExpression) != nil
            for match in re.matches(in:line,range:NSRange(location:0,length:ns.length)) {
                let raw=ns.substring(with:match.range)
                guard !excluded.contains(where:{raw.lowercased().contains($0)}) else { continue }
                let name=raw.split(whereSeparator:{$0.isWhitespace}).map { token -> String in
                    let s=String(token)
                    return s == s.uppercased() ? s.prefix(1).uppercased()+s.dropFirst().lowercased() : s
                }.joined(separator:" ")
                let candidate=NameCandidate(name:name,evidence:String(line.prefix(160)),explicit:explicit)
                if found[name] == nil || explicit { found[name]=candidate }
            }
        }
        // Passport forms often place the three fields on separate OCR lines.
        func field(_ pattern:String)->String? {
            guard let regex=try? NSRegularExpression(pattern:pattern,options:[.caseInsensitive]) else{return nil}
            for (i,line) in lines.enumerated() {
                let ns=line as NSString
                guard let match=regex.firstMatch(in:line,range:NSRange(location:0,length:ns.length)) else{continue}
                let tail=ns.substring(from:match.range.location+match.range.length).trimmingCharacters(in:CharacterSet(charactersIn:" :\t"))
                let value=tail.isEmpty && i+1<lines.count ? lines[i+1].trimmingCharacters(in:.whitespaces) : tail
                if value.range(of:"^[А-ЯІЇЄҐа-яіїєґ’'ʼ-]{2,}$",options:.regularExpression) != nil{return value}
            }
            return nil
        }
        if let surname=field("^\\s*прізвище"),let given=field("^\\s*ім[’'ʼ]?я"),let patronymic=field("^\\s*по батькові") {
            let name=[surname,given,patronymic].map{$0.prefix(1).uppercased()+$0.dropFirst().lowercased()}.joined(separator:" ")
            found[name]=NameCandidate(name:name,evidence:"Окремі поля: прізвище, ім’я, по батькові",explicit:true)
        }
        return found.values.sorted {
            if $0.explicit != $1.explicit { return $0.explicit && !$1.explicit }
            return $0.name < $1.name
        }
    }
    static func safeName(_ text: String) -> String {
        let bad=CharacterSet(charactersIn:"/\\:*?\"<>|\n\r")
        let value=text.components(separatedBy:bad).joined(separator:"_").trimmingCharacters(in:.whitespacesAndNewlines)
        return value.isEmpty ? "Скан" : String(value.prefix(100))
    }
}


struct Point: Codable, Equatable { var x: Double; var y: Double }
struct Quad: Codable, Equatable {
    var points: [Point] // top left, top right, bottom right, bottom left, top-left origin
    static let full = Quad(points: [.init(x: 0.01,y: 0.01),.init(x: 0.99,y: 0.01),.init(x: 0.99,y: 0.99),.init(x: 0.01,y: 0.99)])
    var valid: Bool {
        guard points.count == 4 else { return false }
        var crosses: [Double] = []
        var area = 0.0
        for i in 0..<4 {
            let a=points[i], b=points[(i+1)%4], c=points[(i+2)%4]
            guard (0...1).contains(a.x), (0...1).contains(a.y) else { return false }
            crosses.append((b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x))
            area += a.x*b.y-b.x*a.y
        }
        return crosses.allSatisfy { $0 > 0.0001 } && area > 0.04
    }
}
struct NameCandidate: Codable, Hashable, Identifiable {
    var name: String
    var evidence: String
    var explicit: Bool
    var id: String { name }
}

// Geometry of small connected ink components distinguishes horizontal text
// from sideways text without assuming that the sheet itself must be portrait.
struct TextAxis {
    var horizontal: Int
    var vertical: Int
    var components: Int
    var evidence: Double { Double(horizontal-vertical)/Double(max(1,horizontal+vertical)) }
    var reliable: Bool { components>=60 && abs(evidence)>=0.18 }
}
enum RasterAxis {
    static func estimate(_ gray:[UInt8],width:Int,height:Int)->TextAxis {
        guard width>0,height>0,gray.count==width*height else {return TextAxis(horizontal:0,vertical:0,components:0)}
        var histogram=[Int](repeating:0,count:256)
        for pixel in gray {histogram[Int(pixel)]+=1}
        var cumulative=0,background=255
        for i in 0..<256 {cumulative+=histogram[i];if cumulative>=gray.count*4/5{background=i;break}}
        let threshold=min(185,background-45)
        var visited=[UInt8](repeating:0,count:gray.count)
        var queue:[Int]=[]
        var horizontal=0,vertical=0,components=0
        for start in gray.indices where visited[start]==0 && Int(gray[start])<threshold {
            queue.removeAll(keepingCapacity:true);queue.append(start);visited[start]=1
            var cursor=0,minX=width,minY=height,maxX=0,maxY=0
            while cursor<queue.count {
                let p=queue[cursor];cursor+=1
                let x=p%width,y=p/width
                minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
                func add(_ next:Int) {
                    if visited[next]==0 && Int(gray[next])<threshold {visited[next]=1;queue.append(next)}
                }
                if x>0 {add(p-1)};if x+1<width {add(p+1)}
                if y>0 {add(p-width)};if y+1<height {add(p+width)}
            }
            let w=maxX-minX+1,h=maxY-minY+1,area=queue.count
            guard min(w,h)>=3,max(w,h)<=40,area>=8,area<=500 else{continue}
            let ratio=Double(w)/Double(h),fill=Double(area)/Double(w*h)
            guard ratio>=0.2,ratio<=5,fill>=0.12,fill<=0.85 else{continue}
            components+=1
            if Double(h)>Double(w)*1.22 {horizontal+=1}
            else if Double(w)>Double(h)*1.22 {vertical+=1}
        }
        return TextAxis(horizontal:horizontal,vertical:vertical,components:components)
    }
    static func choose(scores:[Double],axis:TextAxis,manual:Int?)->(turns:Int,uncertain:Bool) {
        if let manual {return ((manual%4+4)%4,false)}
        guard scores.count==4 else{return (0,true)}
        let allowed: [Int]
        if axis.reliable {allowed=axis.evidence>0 ? [0,2] : [1,3]}
        else {allowed=[0,1,2,3]}
        let ordered=allowed.sorted { scores[$0]==scores[$1] ? $0<$1 : scores[$0]>scores[$1] }
        let best=ordered[0],second=ordered[1]
        let uncertain=scores[best]<25 || scores[second]>scores[best]*0.88
        if axis.reliable && axis.evidence<0 {return (best,uncertain)}
        // Keep an already horizontal page unless upside-down OCR is clearly better.
        if best != 0 && (uncertain || scores[best]<scores[0]*1.30+12) {return (0,true)}
        return (best,uncertain)
    }
}

// Deterministic raster stage. Does not infer or generate document contents.
// rgba and hints share the same row order. A hint is a Vision foreground probability.
enum PaperRaster {
    static func mask(_ rgba:[UInt8],width w:Int,height h:Int,hint:[UInt8]?=nil)->[UInt8] {
        let n=w*h
        guard w>16,h>16,rgba.count==n*4 else { return [UInt8](repeating:0,count:max(0,n)) }
        var rb=[Int](),gb=[Int]()
        let step=max(1,min(w,h)/100)
        for y in stride(from:h/5,to:h*4/5,by:step) {
            for x in stride(from:w/5,to:w*4/5,by:step) {
                let i=(y*w+x)*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
                if max(r,max(g,b))-min(r,min(g,b))<40 && r+g+b>210 {rb.append(r-b);gb.append(g-b)}
            }
        }
        guard rb.count>30 else {return [UInt8](repeating:0,count:n)}
        rb.sort();gb.sort();let redOffset=rb[rb.count/2],greenOffset=gb[gb.count/2]
        var hasHint=false
        if let hint,hint.count==n {
            var total=0,count=0
            for y in stride(from:h/3,to:h*2/3,by:step) {for x in stride(from:w/3,to:w*2/3,by:step){total+=Int(hint[y*w+x]);count+=1}}
            hasHint=count>0 && total/count>180
        }
        var warmCount=0,borderCount=0
        for y in stride(from:0,to:h,by:step) {for x in stride(from:0,to:w,by:step) where x<step || y<step || x>=w-step || y>=h-step {
            let i=(y*w+x)*4
            if Int(rgba[i])-Int(rgba[i+2])-redOffset>14 && Int(rgba[i+1])-Int(rgba[i+2])-greenOffset>2 {warmCount+=1}
            borderCount+=1
        }}
        let warmScene=warmCount*20>borderCount
        let band=max(3,Int(Double(min(w,h))*0.22))
        var candidate=[UInt8](repeating:0,count:n)
        for y in 0..<h {for x in 0..<w where min(x,min(y,min(w-1-x,h-1-y)))<band {
            let p=y*w+x,i=p*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
            // Blue/purple handwriting and stamps are never used as background.
            if b-r>4 || b-g>8 {continue}
            let warm=r-b-redOffset>14 && g-b-greenOffset>2
            let shadow=warmScene && r+g+b<330
            let outside=hasHint && (hint?[p] ?? 255)<35
            if warm || shadow || outside {candidate[p]=1}
        }}
        var result=[UInt8](repeating:0,count:n),queue=[Int32]()
        func seed(_ p:Int) {if candidate[p] != 0 && result[p]==0 {result[p]=255;queue.append(Int32(p))}}
        for x in 0..<w {seed(x);seed((h-1)*w+x)}
        for y in 0..<h {seed(y*w);seed(y*w+w-1)}
        var head=0
        while head<queue.count {
            let p=Int(queue[head]);head+=1;let x=p%w,y=p/w
            if x>0 {seed(p-1)};if x+1<w {seed(p+1)};if y>0 {seed(p-w)};if y+1<h {seed(p+w)}
        }
        // Reject a model failure that classifies too much of the page as background.
        guard queue.count<n/3 else {return hasHint ? mask(rgba,width:w,height:h,hint:nil) : [UInt8](repeating:0,count:n)}
        // Expand only through pixels consistent with background or its dark contact shadow.
        for _ in 0..<3 {
            let old=result
            for y in 1..<(h-1) {for x in 1..<(w-1) {
                let p=y*w+x
                if old[p] != 0 || (old[p-1]==0 && old[p+1]==0 && old[p-w]==0 && old[p+w]==0) {continue}
                let i=p*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
                if b-r>4 || b-g>8 {continue}
                if (r-b-redOffset>3 && g-b-greenOffset > -2) || r+g+b<240 {result[p]=255}
            }}
        }
        return result
    }
    // Feather goes INTO the document, so the original paper edge is not a hard compositing seam.
    static func overlap(_ rgba:[UInt8],width w:Int,height h:Int,mask:[UInt8],radius:Int?=nil)->[UInt8] {
        guard w>2,h>2,rgba.count==w*h*4,mask.count==w*h else {return mask}
        let feather=max(3,min(64,radius ?? max(8,min(w,h)/80)))
        let inset=max(1,feather/5)
        var alpha=mask,distance=[UInt16](repeating:UInt16.max,count:w*h),queue=[Int32]()
        for p in mask.indices where mask[p]>0 {
            distance[p]=0
            let x=p%w,y=p/w
            if (x>0 && mask[p-1]==0) || (x+1<w && mask[p+1]==0) || (y>0 && mask[p-w]==0) || (y+1<h && mask[p+w]==0) {queue.append(Int32(p))}
        }
        var head=0
        while head<queue.count {
            let p=Int(queue[head]);head+=1
            guard Int(distance[p])<feather else {continue}
            let x=p%w,y=p/w,next=distance[p]+1
            func add(_ q:Int) {if distance[q]>next {distance[q]=next;queue.append(Int32(q))}}
            if x>0 {add(p-1)};if x+1<w {add(p+1)};if y>0 {add(p-w)};if y+1<h {add(p+w)}
        }
        for p in mask.indices where mask[p]==0 && distance[p]<UInt16(feather) {
            let i=p*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
            // Keep ink, signatures and colored stamps inside the overlap intact.
            var brightest=r+g+b
            let x=p%w,y=p/w
            for dy in [-4,0,4] {for dx in [-4,0,4] {
                let sx=min(w-1,max(0,x+dx)),sy=min(h-1,max(0,y+dy)),q=(sy*w+sx)*4
                brightest=max(brightest,Int(rgba[q])+Int(rgba[q+1])+Int(rgba[q+2]))
            }}
            let ink=r+g+b<240 || (r+g+b<450 && brightest-r-g-b>60)
            if ink || max(r,max(g,b))-min(r,min(g,b))>24 {continue}
            let t=max(0,min(1,Double(Int(distance[p])-inset)/Double(feather-inset)))
            let smooth=t*t*(3-2*t)
            alpha[p]=UInt8((1-smooth)*255)
        }
        return alpha
    }
    static func feathered(_ rgba:[UInt8],width w:Int,height h:Int,mask:[UInt8])->[UInt8] {
        let alpha=overlap(rgba,width:w,height:h,mask:mask)
        guard alpha.count==w*h,rgba.count==w*h*4 else {return rgba}
        let support=alpha.map {UInt8($0>0 ? 255:0)}
        let fill=extend(rgba,width:w,height:h,mask:support)
        var output=rgba
        for p in alpha.indices where alpha[p]>0 {
            let a=Int(alpha[p])
            for c in 0..<3 {output[p*4+c]=UInt8((Int(fill[p*4+c])*a+Int(rgba[p*4+c])*(255-a)+127)/255)}
        }
        return output
    }
    static func extend(_ rgba:[UInt8],width w:Int,height h:Int,mask:[UInt8])->[UInt8] {
        guard w>16,h>16,rgba.count==w*h*4,mask.count==w*h,mask.contains(255) else {return rgba}
        let scale=max(1,Int(ceil(Double(max(w,h))/320)))
        let gw=(w+scale-1)/scale,gh=(h+scale-1)/scale,n=gw*gh
        var field=[Float](repeating:0,count:n*3),missing=[Bool](repeating:false,count:n)
        for gy in 0..<gh {for gx in 0..<gw {
            let p=gy*gw+gx;var counts=0,bg=0,sums=[Int](repeating:0,count:3),samples=0
            for y in stride(from:gy*scale,to:min(h,(gy+1)*scale),by:max(1,scale/3)) {
                for x in stride(from:gx*scale,to:min(w,(gx+1)*scale),by:max(1,scale/3)) {
                    let q=y*w+x;samples+=1
                    if mask[q]>0 {bg+=1;continue}
                    let i=q*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
                    if r+g+b<330 || max(r,max(g,b))-min(r,min(g,b))>30 {continue}
                    counts+=1;for c in 0..<3 {sums[c]+=Int(rgba[q*4+c])}
                }
            }
            missing[p]=bg*5>samples || counts==0
            if counts>0 {for c in 0..<3 {field[p*3+c]=Float(sums[c])/Float(counts)}}
        }}
        // Multi-source propagation initializes a local paper donor for each missing cell.
        var donor=[Int32](repeating:-1,count:n),queue=[Int32]()
        for p in 0..<n where !missing[p] {donor[p]=Int32(p);queue.append(Int32(p))}
        guard !queue.isEmpty else {return rgba}
        var head=0
        while head<queue.count {
            let p=Int(queue[head]);head+=1;let x=p%gw,y=p/gw
            var neighbours=[Int]()
            if x>0 {neighbours.append(p-1)};if x+1<gw {neighbours.append(p+1)}
            if y>0 {neighbours.append(p-gw)};if y+1<gh {neighbours.append(p+gw)}
            for q in neighbours where donor[q]<0 {donor[q]=donor[p];queue.append(Int32(q))}
        }
        let holes=(0..<n).filter {missing[$0]}
        for p in holes {for c in 0..<3 {field[p*3+c]=field[Int(donor[p])*3+c]}}
        // Harmonic continuation matches nearby lighting instead of one global paper color.
        for _ in 0..<500 {
            for p in holes {
                let x=p%gw,y=p/gw
                let l=x>0 ? p-1:p,r=x+1<gw ? p+1:p,t=y>0 ? p-gw:p,b=y+1<gh ? p+gw:p
                for c in 0..<3 {field[p*3+c]=(field[l*3+c]+field[r*3+c]+field[t*3+c]+field[b*3+c])*0.25}
            }
        }
        var output=rgba
        for y in 0..<h {for x in 0..<w where mask[y*w+x]>0 {
            let fx=max(0,min(Float(gw-1),Float(x)/Float(scale)-0.5)),fy=max(0,min(Float(gh-1),Float(y)/Float(scale)-0.5))
            let x0=Int(fx),y0=Int(fy),x1=min(gw-1,x0+1),y1=min(gh-1,y0+1),ax=fx-Float(x0),ay=fy-Float(y0)
            let d=Int(donor[min(gh-1,y/scale)*gw+min(gw-1,x/scale)])
            // Deterministic local grain; no mirrored letters or repeated crease patterns.
            let hash=(UInt32(truncatingIfNeeded:x) &* 73856093) ^ (UInt32(truncatingIfNeeded:y) &* 19349663)
            var sx=min(w-3,max(2,(d%gw)*scale+Int(hash%23)-11))
            var sy=min(h-3,max(2,(d/gw)*scale+Int((hash>>8)%23)-11))
            if mask[sy*w+sx]>0 {sx=min(w-3,max(2,(d%gw)*scale));sy=min(h-3,max(2,(d/gw)*scale))}
            for c in 0..<3 {
                let top=field[(y0*gw+x0)*3+c]*(1-ax)+field[(y0*gw+x1)*3+c]*ax
                let bottom=field[(y1*gw+x0)*3+c]*(1-ax)+field[(y1*gw+x1)*3+c]*ax
                var grain:Float=0
                let i=(sy*w+sx)*4
                let r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
                if mask[sy*w+sx]==0 && max(r,max(g,b))-min(r,min(g,b))<25 && r+g+b>240 {
                    var local:Float=0
                    for dy in -2...2 {for dx in -2...2 {local+=Float(rgba[((sy+dy)*w+sx+dx)*4+c])}}
                    grain=max(-5,min(5,Float(rgba[i+c])-local/25))
                }
                output[(y*w+x)*4+c]=UInt8(max(0,min(255,top*(1-ay)+bottom*ay+grain)))
            }
            output[(y*w+x)*4+3]=255
        }}
        return output
    }
}

// Line direction is inferred from connected text runs, not glyph width/height.
// A sideways form may contain many wide Cyrillic glyphs even when the text is upright.
enum RasterFlow {
    static func estimate(_ gray:[UInt8],width w:Int,height h:Int)->TextAxis {
        guard w>32,h>32,gray.count==w*h else {return TextAxis(horizontal:0,vertical:0,components:0)}
        var histogram=[Int](repeating:0,count:256)
        for v in gray {histogram[Int(v)]+=1}
        var sum=0,background=255
        for i in 0..<256 {sum+=histogram[i];if sum>=gray.count*4/5 {background=i;break}}
        let threshold=min(185,background-45)
        var visited=[UInt8](repeating:0,count:w*h),ink=[UInt8](repeating:0,count:w*h),queue=[Int]()
        var glyphs=0
        for start in gray.indices where visited[start]==0 && Int(gray[start])<threshold {
            queue.removeAll(keepingCapacity:true);queue.append(start);visited[start]=1
            var head=0,minX=w,minY=h,maxX=0,maxY=0
            while head<queue.count {
                let p=queue[head];head+=1;let x=p%w,y=p/w
                minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
                func add(_ next:Int) {if visited[next]==0 && Int(gray[next])<threshold {visited[next]=1;queue.append(next)}}
                if x>0 {add(p-1)};if x+1<w {add(p+1)};if y>0 {add(p-w)};if y+1<h {add(p+w)}
            }
            let cw=maxX-minX+1,ch=maxY-minY+1,area=queue.count
            let fill=Double(area)/Double(cw*ch)
            // Long table rules, decorative frames and large stamps must not vote as text lines.
            if min(cw,ch)>=2 && max(cw,ch)<=40 && area>=4 && area<=500 && fill>0.08 && fill<0.9 {
                for p in queue {ink[p]=1};glyphs+=1
            }
        }
        let horizontal=runWeight(ink,width:w,height:h,horizontal:true)
        let vertical=runWeight(ink,width:w,height:h,horizontal:false)
        let e=Double(horizontal-vertical)/Double(max(1,horizontal+vertical))
        let reliable=glyphs>=40 && max(horizontal,vertical)>=1000 && abs(e)>=0.22
        return TextAxis(horizontal:horizontal,vertical:vertical,components:reliable ? max(60,glyphs) : 0)
    }
    private static func runWeight(_ ink:[UInt8],width w:Int,height h:Int,horizontal:Bool)->Int {
        let lines=horizontal ? h:w,length=horizontal ? w:h,radius=6
        var closed=[UInt8](repeating:0,count:w*h)
        for line in 0..<lines {
            func index(_ position:Int)->Int {horizontal ? line*w+position : position*w+line}
            var prefix=[Int](repeating:0,count:length+1)
            for x in 0..<length {prefix[x+1]=prefix[x]+Int(ink[index(x)])}
            var dilated=[Int](repeating:0,count:length+1)
            for x in 0..<length {
                let present=prefix[min(length,x+radius+1)]-prefix[max(0,x-radius)]>0
                dilated[x+1]=dilated[x]+(present ? 1:0)
            }
            for x in radius..<(length-radius) where dilated[x+radius+1]-dilated[x-radius]==radius*2+1 {closed[index(x)]=1}
        }
        var queue=[Int](),weight=0
        for start in closed.indices where closed[start]==1 {
            closed[start]=0;queue.removeAll(keepingCapacity:true);queue.append(start)
            var head=0,minX=w,minY=h,maxX=0,maxY=0
            while head<queue.count {
                let p=queue[head];head+=1;let x=p%w,y=p/w
                minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)
                func add(_ next:Int) {if closed[next]==1 {closed[next]=0;queue.append(next)}}
                if x>0 {add(p-1)};if x+1<w {add(p+1)};if y>0 {add(p-w)};if y+1<h {add(p+w)}
            }
            let a=horizontal ? maxX-minX+1:maxY-minY+1,b=horizontal ? maxY-minY+1:maxX-minX+1
            if a>=30 && b>=3 && b<=26 && a>b*3 {weight+=min(a,250)*min(b,15)}
        }
        return weight
    }
}

// A rectangle inside a document is not necessarily the sheet. Reject automatic
// crops that exclude reliable text; PDF pages keep their full canvas by default.
enum CropSafety {
    static func area(_ quad:Quad)->Double {
        guard quad.points.count==4 else {return 0}
        var a=0.0
        for i in 0..<4 {let p=quad.points[i],q=quad.points[(i+1)%4];a+=p.x*q.y-q.x*p.y}
        return abs(a)*0.5
    }
    static func contains(_ point:Point,in quad:Quad,tolerance:Double=0.008)->Bool {
        guard quad.valid else {return false}
        for i in 0..<4 {
            let a=quad.points[i],b=quad.points[(i+1)%4]
            let cross=(b.x-a.x)*(point.y-a.y)-(b.y-a.y)*(point.x-a.x)
            let length=hypot(b.x-a.x,b.y-a.y)
            if cross < -tolerance*length {return false}
        }
        return true
    }
    static func preserves(_ content:[Quad],inside crop:Quad)->Bool {
        crop.valid && content.allSatisfy {box in box.points.allSatisfy {contains($0,in:crop)}}
    }
    static func usable(_ crop:Quad,content:[Quad],camera:Bool)->Bool {
        let a=area(crop)
        return crop.valid && a>=0.055 && (!camera || a<0.94) && preserves(content,inside:crop)
    }
}
