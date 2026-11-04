import Foundation

// Time-based hysteresis. A missed contour or exposure pulse is not a new page.
struct CaptureStability {
    private(set) var quad:Quad?
    private(set) var armed=true
    private(set) var ready=false
    private var credit=0.0
    private var lastTime:Double?
    private var missing=0
    private var changeFrames=0
    private var signature:[UInt8]=[]
    private var capturedQuad:Quad?
    private var capturedSignature:[UInt8]=[]
    private var focusTime=0.0
    mutating func resetStability() {credit=0;ready=false;focusTime=0}
    mutating func didCapture() {
        armed=false;capturedQuad=quad;capturedSignature=signature
        changeFrames=0;resetStability()
    }
    static func distance(_ a:Quad,_ b:Quad)->Double {
        guard a.points.count==4,b.points.count==4 else {return 1.0}
        var total:Double=0.0
        for index in 0..<4 {
            let dx:Double=a.points[index].x-b.points[index].x
            let dy:Double=a.points[index].y-b.points[index].y
            total += hypot(dx,dy)
        }
        return total/4.0
    }
    static func motion(_ a:[UInt8],_ b:[UInt8])->Double {
        guard !a.isEmpty,a.count==b.count else {return 0}
        var sumA:Double=0.0
        var sumB:Double=0.0
        for index in a.indices {
            sumA += Double(a[index])
            sumB += Double(b[index])
        }
        let count:Double=Double(a.count)
        let meanA:Double=sumA/count
        let meanB:Double=sumB/count
        var difference:Double=0.0
        for index in a.indices {
            let centeredA:Double=Double(a[index])-meanA
            let centeredB:Double=Double(b[index])-meanB
            difference += abs(centeredA-centeredB)
        }
        return difference/(255.0*count)
    }
    mutating func update(_ candidate:Quad?,signature current:[UInt8],time:Double,focusing:Bool)->Bool {
        let dt=min(0.3,max(0,time-(lastTime ?? time)))
        lastTime=time;ready=false
        guard let candidate,candidate.valid else {
            missing+=1;credit=max(0,credit-0.10)
            if missing>=4 {quad=nil;armed=true;credit=0}
            return false
        }
        missing=0
        let delta=quad.map {Self.distance($0,candidate)} ?? 1
        let movement=Self.motion(signature,current)
        if !armed {
            let changed=capturedQuad.map {Self.distance($0,candidate)>0.09} ?? true
            let differentContent=Self.motion(capturedSignature,current)>0.065
            changeFrames=(changed || differentContent) ? changeFrames+1:0
            if changeFrames>=2 {armed=true;credit=0}
        }
        // Follow real motion, smooth small jitter only; never reuse stale corners
        // for the high-resolution photograph's independent crop check.
        if let previous=quad,delta<0.05 {
            var smoothed:[Point]=[]
            for index in 0..<4 {
                let old=previous.points[index]
                let new=candidate.points[index]
                let x:Double=old.x*0.35+new.x*0.65
                let y:Double=old.y*0.35+new.y*0.65
                smoothed.append(Point(x:x,y:y))
            }
            quad=Quad(points:smoothed)
        } else {quad=candidate}
        signature=current
        if delta>0.09 || movement>0.08 {credit=0;focusTime=0}
        else if delta<0.04 && movement<0.045 {credit+=dt}
        else {credit=max(0,credit-dt*0.5)}
        // Exposure may fluctuate, but active autofocus never times out into capture.
        focusTime=focusing ? focusTime+dt:0
        ready=armed && credit>=0.65 && !focusing
        return ready
    }
}

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
                let raw=tail.isEmpty && i+1<lines.count ? lines[i+1].trimmingCharacters(in:.whitespaces) : tail
                let otherLabel=raw.range(of:"\\s+(?:по\\s+батькові|ім[’'ʼ]?я|прізвище)",options:[.regularExpression,.caseInsensitive])
                let value=String(raw[..<(otherLabel?.lowerBound ?? raw.endIndex)]).trimmingCharacters(in:.whitespacesAndNewlines)
                if value.range(of:"^[А-ЯІЇЄҐа-яіїєґ’'ʼ-]{2,}$",options:.regularExpression) != nil{return value}
            }
            return nil
        }
        if let surname=field("^\\s*прізвище"),let given=field("^\\s*ім[’'ʼ]?я"),let patronymic=field("(?:^|\\s)по\\s+батькові") {
            let name=[surname,given,patronymic].map{$0.prefix(1).uppercased()+$0.dropFirst().lowercased()}.joined(separator:" ")
            found[name]=NameCandidate(name:name,evidence:"Окремі поля: прізвище, ім’я, по батькові",explicit:true)
        }
        return found.values.sorted {
            if $0.explicit != $1.explicit { return $0.explicit && !$1.explicit }
            return $0.name < $1.name
        }
    }
    static func plausiblePerson(_ name:String)->Bool {
        let parts=name.split(separator:" ")
        guard parts.count==3 else {return false}
        let last=String(parts[2]).lowercased()
        return ["вич","вна","ич","івна","овна"].contains {last.hasSuffix($0)}
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
        var rb=[Int](),gb=[Int](),brightness=[Int]()
        let step=max(1,min(w,h)/100)
        for y in stride(from:h/5,to:h*4/5,by:step) {
            for x in stride(from:w/5,to:w*4/5,by:step) {
                let i=(y*w+x)*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
                if max(r,max(g,b))-min(r,min(g,b))<40 && r+g+b>210 {rb.append(r-b);gb.append(g-b);brightness.append((r+g+b)/3)}
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
        let feather=max(3,min(512,radius ?? max(12,min(w,h)/25)))
        let inset=max(1,feather/3)
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
            let ink=r+g+b<240 || brightest-r-g-b>45
            if ink || EdgeBand.protectedInk(r,g,b) || max(r,max(g,b))-min(r,min(g,b))>24 {continue}
            let t=max(0,min(1,Double(Int(distance[p])-inset)/Double(feather-inset)))
            let smooth=t*t*(3-2*t)
            alpha[p]=UInt8((1-smooth)*255)
        }
        return alpha
    }
    static func feathered(_ rgba:[UInt8],width w:Int,height h:Int,mask:[UInt8],radius:Int?=nil)->[UInt8] {
        let alpha=overlap(rgba,width:w,height:h,mask:mask,radius:radius)
        guard alpha.count==w*h,rgba.count==w*h*4 else {return rgba}
        let support=alpha.map {UInt8($0>0 ? 255:0)}
        let fill=extend(rgba,width:w,height:h,mask:support)
        var output=rgba
        for p in alpha.indices where alpha[p]>0 {
            let a=Int(alpha[p])
            for c in 0..<3 {
                let original=Int(rgba[p*4+c])
                let mixed=(Int(fill[p*4+c])*a+original*(255-a)+127)/255
                // Cleaning must never introduce a darker halo into the original paper.
                output[p*4+c]=UInt8(max(original,mixed))
            }
        }
        return output
    }
    static func extend(_ rgba:[UInt8],width w:Int,height h:Int,mask:[UInt8])->[UInt8] {
        guard w>16,h>16,rgba.count==w*h*4,mask.count==w*h,mask.contains(255) else {return rgba}
        // Estimate the paper itself, excluding dark print, portraits and colored marks.
        var paperLevels=[Int]()
        let paperStep=max(1,min(w,h)/100)
        for y in stride(from:0,to:h,by:paperStep) {for x in stride(from:0,to:w,by:paperStep) {
            let p=y*w+x,i=p*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
            if mask[p]==0 && max(r,max(g,b))-min(r,min(g,b))<=25 && r+g+b>330 {paperLevels.append((r+g+b)/3)}
        }}
        guard !paperLevels.isEmpty else {return rgba}
        paperLevels.sort()
        let paperFloor=max(110,paperLevels[paperLevels.count*85/100]-25)
        // A coarse illumination surface cannot copy letter-shaped dark patches.
        let scale=max(1,Int(ceil(Double(max(w,h))/64)))
        let gw=(w+scale-1)/scale,gh=(h+scale-1)/scale,n=gw*gh
        var field=[Float](repeating:0,count:n*3),missing=[Bool](repeating:false,count:n)
        for gy in 0..<gh {for gx in 0..<gw {
            let p=gy*gw+gx;var bg=0,samples=0,donors=[Int]()
            for y in stride(from:gy*scale,to:min(h,(gy+1)*scale),by:max(1,scale/6)) {
                for x in stride(from:gx*scale,to:min(w,(gx+1)*scale),by:max(1,scale/6)) {
                    let q=y*w+x;samples+=1
                    if mask[q]>0 {bg+=1;continue}
                    let i=q*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
                    if (r+g+b)/3<paperFloor || max(r,max(g,b))-min(r,min(g,b))>25 {continue}
                    donors.append(q)
                }
            }
            missing[p]=bg*5>samples || donors.isEmpty
            if !donors.isEmpty {
                donors.sort {a,b in
                    Int(rgba[a*4])+Int(rgba[a*4+1])+Int(rgba[a*4+2]) > Int(rgba[b*4])+Int(rgba[b*4+1])+Int(rgba[b*4+2])
                }
                let bright=donors.prefix(max(1,donors.count/3))
                for c in 0..<3 {
                    field[p*3+c]=Float(bright.reduce(0){$0+Int(rgba[$1*4+c])})/Float(bright.count)
                }
            }
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
        for _ in 0..<160 {
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
            for c in 0..<3 {
                let top=field[(y0*gw+x0)*3+c]*(1-ax)+field[(y0*gw+x1)*3+c]*ax
                let bottom=field[(y1*gw+x0)*3+c]*(1-ax)+field[(y1*gw+x1)*3+c]*ax
                // Continue the local illumination, without synthetic noise or copied ink.
                output[(y*w+x)*4+c]=UInt8(max(0,min(255,top*(1-ay)+bottom*ay)))
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

// Outer background detection with an explicit pixel margin around its contour.
// No document segmentation mask and no internal rectangle is used here.
enum EdgeBand {
    static func protectedInk(_ r:Int,_ g:Int,_ b:Int)->Bool {
        // Red ink has little green-yellow component. Brown wood contains both.
        let red=r-g>60 && r-b>=80 && g-b<max(12,(r-g)/5)
        let blue=(b-r>14 && b-g>10) || (b-g>22 && b-r>5)
        return blue || red
    }
    static func mask(_ rgba:[UInt8],width w:Int,height h:Int,bandFraction:Double=0.12,margin:Int=8)->[UInt8] {
        let n=w*h
        guard w>20,h>20,rgba.count==n*4 else {return [UInt8](repeating:0,count:max(0,n))}
        var rb=[Int](),gb=[Int](),brightness=[Int]()
        let step=max(1,min(w,h)/90)
        for y in stride(from:h/5,to:h*4/5,by:step) {for x in stride(from:w/5,to:w*4/5,by:step) {
            let i=(y*w+x)*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
            if max(r,max(g,b))-min(r,min(g,b))<35 && r+g+b>300 {rb.append(r-b);gb.append(g-b);brightness.append((r+g+b)/3)}
        }}
        guard rb.count>25 else {return [UInt8](repeating:0,count:n)}
        rb.sort();gb.sort();brightness.sort();let ro=rb[rb.count/2],go=gb[gb.count/2],paper=brightness[brightness.count*3/4]
        let band=max(3,min(256,Int(Double(min(w,h))*max(0.06,min(0.12,bandFraction))))),seedDepth=max(2,min(8,min(w,h)/400))
        var candidate=[UInt8](repeating:0,count:n),result=candidate,queue=[Int32]()
        for y in 0..<h {
            let ranges=y<band || y>=h-band ? [0..<w] : [0..<band,(w-band)..<w]
            for range in ranges {for x in range {
                let p=y*w+x,i=p*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
                // Blue ink and saturated red ink are content, not wooden background.
                if protectedInk(r,g,b) {continue}
                let warm=r-b-ro>9 && g-b-go>1
                let neutral=max(r,max(g,b))-min(r,min(g,b))<25
                let grayFloor=neutral && (r+g+b)/3>65 && paper-(r+g+b)/3>35
                if warm || grayFloor {
                    candidate[p]=1
                    if min(x,min(y,min(w-1-x,h-1-y)))<seedDepth {
                        if warm {result[p]=255;queue.append(Int32(p))}
                        else {
                            // A 3x3 neighborhood distinguishes a floor patch from a fine table rule.
                            var dark=0
                            for dy in -1...1 {for dx in -1...1 {
                                let q=(min(h-1,max(0,y+dy))*w+min(w-1,max(0,x+dx)))*4
                                if paper-(Int(rgba[q])+Int(rgba[q+1])+Int(rgba[q+2]))/3>35 {dark+=1}
                            }}
                            if dark>=8 {result[p]=255;queue.append(Int32(p))}
                        }
                    }
                }
            }}
        }
        var head=0
        while head<queue.count {
            let p=Int(queue[head]);head+=1;let x=p%w,y=p/w
            func add(_ q:Int){if candidate[q]>0 && result[q]==0 {result[q]=255;queue.append(Int32(q))}}
            if x>0 {add(p-1)};if x+1<w {add(p+1)};if y>0 {add(p-w)};if y+1<h {add(p+w)}
        }
        // Cover the OUTSIDE up to the detected contour as well as the inside feather.
        // Wood grain can contain pale gaps: do not leave those gaps as isolated islands.
        func cover(_ p:Int) {
            let i=p*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
            if protectedInk(r,g,b) {return}
            result[p]=255
        }
        for y in 0..<h {
            if let last=(0..<band).last(where:{result[y*w+$0]>0}) {for x in 0...last {cover(y*w+x)}}
            if let first=((w-band)..<w).first(where:{result[y*w+$0]>0}) {for x in first..<w {cover(y*w+x)}}
        }
        for x in 0..<w {
            if let last=(0..<band).last(where:{result[$0*w+x]>0}) {for y in 0...last {cover(y*w+x)}}
            if let first=((h-band)..<h).first(where:{result[$0*w+x]>0}) {for y in first..<h {cover(y*w+x)}}
        }
        return padded(rgba,width:w,height:h,mask:result,pixels:margin)
    }
    static func padded(_ rgba:[UInt8],width w:Int,height h:Int,mask:[UInt8],pixels:Int)->[UInt8] {
        guard mask.count==w*h,rgba.count==w*h*4 else {return mask}
        let radius=max(0,min(24,pixels))
        guard radius>0,mask.contains(255) else {return mask}
        var result=mask,distance=[UInt8](repeating:255,count:w*h),queue=[Int32]()
        for p in mask.indices where mask[p]>0 {
            distance[p]=0
            let x=p%w,y=p/w
            if (x>0 && mask[p-1]==0) || (x+1<w && mask[p+1]==0) || (y>0 && mask[p-w]==0) || (y+1<h && mask[p+w]==0) {queue.append(Int32(p))}
        }
        var head=0
        while head<queue.count {
            let p=Int(queue[head]);head+=1
            guard Int(distance[p])<radius else {continue}
            let x=p%w,y=p/w,next=distance[p]+1
            func add(_ q:Int) {if distance[q]>next {distance[q]=next;queue.append(Int32(q))}}
            if x>0 {add(p-1)};if x+1<w {add(p+1)};if y>0 {add(p-w)};if y+1<h {add(p+w)}
        }
        for p in mask.indices where mask[p]==0 && distance[p]<=UInt8(radius) {
            let i=p*4,r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
            if protectedInk(r,g,b) {continue}
            let warm=r-b>12 && g-b>2
            let x=p%w,y=p/w
            var warmNeighbours=0
            for dy in [-3,0,3] {for dx in [-3,0,3] {
                let q=(min(h-1,max(0,y+dy))*w+min(w-1,max(0,x+dx)))*4
                let nr=Int(rgba[q]),ng=Int(rgba[q+1]),nb=Int(rgba[q+2])
                if nr-nb>12 && ng-nb>2 && !protectedInk(nr,ng,nb) {warmNeighbours+=1}
            }}
            let woodGrain=warmNeighbours>=3
            if !warm && !woodGrain {
                if r+g+b<240 {continue}
                var brightest=r+g+b
                let x=p%w,y=p/w
                for dy in [-2,0,2] {for dx in [-2,0,2] {
                    let q=(min(h-1,max(0,y+dy))*w+min(w-1,max(0,x+dx)))*4
                    brightest=max(brightest,Int(rgba[q])+Int(rgba[q+1])+Int(rgba[q+2]))
                }}
                if brightest-r-g-b>45 {continue}
            }
            // Solid replacement around the contour closes detached JPEG/wood fragments.
            result[p]=255
        }
        return result
    }
}

// Export settings never alter the stored scan or its original image.
enum PDFCompression:String,CaseIterable,Identifiable {
    case original="Максимальна якість",balanced="Збалансовано",small="Малий файл"
    var id:String {rawValue}
    var pixelLimit:Int {switch self {case .original:return 4096;case .balanced:return 2200;case .small:return 1500}}
    var jpegQuality:Double {switch self {case .original:return 0.94;case .balanced:return 0.78;case .small:return 0.6}}
    var detail:String {
        switch self {
        case .original:return "Без додаткового стиснення фото. Незмінені PDF зберігають текстовий шар."
        case .balanced:return "До 2200 px · для звичайних документів і пересилання."
        case .small:return "До 1500 px · менший розмір, дрібний текст може втратити чіткість."
        }
    }
}

// Illumination is estimated from flat paper, not from portraits or glyphs.
// This changes only a smooth multiplicative lighting field; no image synthesis.
enum PaperLighting {
    static func correct(_ rgba:[UInt8],width:Int,height:Int)->[UInt8] {
        guard width>=32,height>=32,rgba.count==width*height*4 else {return rgba}
        let factor=min(1.0,900.0/Double(max(width,height)))
        let w=max(1,Int(Double(width)*factor)),h=max(1,Int(Double(height)*factor))
        var pixels=[Double](repeating:0,count:w*h*3)
        var gray=[Double](repeating:0,count:w*h)
        for y in 0..<h {for x in 0..<w {
            let sx=min(width-1,Int((Double(x)+0.5)*Double(width)/Double(w)))
            let sy=min(height-1,Int((Double(y)+0.5)*Double(height)/Double(h)))
            let source=(sy*width+sx)*4,target=(y*w+x)*3
            var sum=0.0
            for c in 0..<3 {let value=Double(rgba[source+c]);pixels[target+c]=value;sum+=value}
            gray[y*w+x]=sum/3.0
        }}
        func percentile(_ values:[Double],_ fraction:Double)->Double {
            guard !values.isEmpty else {return 230.0}
            let sorted=values.sorted()
            let rank=max(0,min(sorted.count-1,Int(ceil(Double(sorted.count)*fraction))-1))
            return sorted[rank]
        }
        let knots=32,gw=36,gh=48
        func edge(_ horizontal:Bool,_ far:Bool)->[[Double]] {
            var profile=[[Double]]()
            for index in 0..<knots {
                let t=Double(index)/Double(knots-1)
                var red:[Double]=[],green:[Double]=[],blue:[Double]=[]
                for delta in [-0.012,-0.006,0.0,0.006,0.012] {
                    for depth in [0.016,0.022,0.028,0.034,0.040] {
                        let along=min(1.0,max(0.0,t+delta))
                        let x=horizontal ? along:(far ? 1.0-depth:depth)
                        let y=horizontal ? (far ? 1.0-depth:depth):along
                        let ix=min(w-1,Int(x*Double(w-1))),iy=min(h-1,Int(y*Double(h-1)))
                        let base=(iy*w+ix)*3
                        let r=pixels[base],g=pixels[base+1],b=pixels[base+2]
                        let spread=max(r,max(g,b))-min(r,min(g,b))
                        if r+g+b>240.0 && spread<55.0 {red.append(r);green.append(g);blue.append(b)}
                    }
                }
                profile.append([percentile(red,0.70),percentile(green,0.70),percentile(blue,0.70)])
            }
            return profile
        }
        var top=edge(true,false),bottom=edge(true,true),left=edge(false,false),right=edge(false,true)
        for c in 0..<3 {
            let tl=(top[0][c]+left[0][c])/2.0,tr=(top[knots-1][c]+right[0][c])/2.0
            let bl=(bottom[0][c]+left[knots-1][c])/2.0,br=(bottom[knots-1][c]+right[knots-1][c])/2.0
            top[0][c]=tl;left[0][c]=tl;top[knots-1][c]=tr;right[0][c]=tr
            bottom[0][c]=bl;left[knots-1][c]=bl;bottom[knots-1][c]=br;right[knots-1][c]=br
        }
        func interpolate(_ profile:[[Double]],_ t:Double,_ c:Int)->Double {
            let p=t*Double(knots-1),a=min(knots-1,Int(p)),b=min(knots-1,a+1)
            let f=p-Double(a)
            return profile[a][c]*(1.0-f)+profile[b][c]*f
        }
        var field=[Double](repeating:230.0,count:gw*gh*3)
        for y in 0..<gh {for x in 0..<gw {
            let u=Double(x)/Double(gw-1),v=Double(y)/Double(gh-1)
            for c in 0..<3 {
                let horizontal=(1.0-v)*interpolate(top,u,c)+v*interpolate(bottom,u,c)
                let vertical=(1.0-u)*interpolate(left,v,c)+u*interpolate(right,v,c)
                let upper=(1.0-u)*top[0][c]+u*top[knots-1][c]
                let lower=(1.0-u)*bottom[0][c]+u*bottom[knots-1][c]
                let corner=(1.0-v)*upper+v*lower
                field[(y*gw+x)*3+c]=min(255.0,max(80.0,horizontal+vertical-corner))
            }
        }}
        let initial=field
        // Integral moments keep the flat-paper test cheap and bounded in memory.
        let stride=w+1
        var sums=[Double](repeating:0,count:(w+1)*(h+1)),squares=sums
        for y in 0..<h {
            var row=0.0,rowSquared=0.0
            for x in 0..<w {
                let value=gray[y*w+x];row+=value;rowSquared+=value*value
                sums[(y+1)*stride+x+1]=sums[y*stride+x+1]+row
                squares[(y+1)*stride+x+1]=squares[y*stride+x+1]+rowSquared
            }
        }
        func areaSum(_ integral:[Double],_ x0:Int,_ y0:Int,_ x1:Int,_ y1:Int)->Double {
            return integral[y1*stride+x1]-integral[y0*stride+x1]-integral[y1*stride+x0]+integral[y0*stride+x0]
        }
        var flat=[Bool](repeating:false,count:w*h)
        for y in 0..<h {for x in 0..<w {
            let x0=max(0,x-3),x1=min(w,x+4),y0=max(0,y-3),y1=min(h,y+4)
            let count=Double((x1-x0)*(y1-y0))
            let mean=areaSum(sums,x0,y0,x1,y1)/count
            let variance=max(0.0,areaSum(squares,x0,y0,x1,y1)/count-mean*mean)
            let base=(y*w+x)*3
            let r=pixels[base],g=pixels[base+1],b=pixels[base+2]
            let spread=max(r,max(g,b))-min(r,min(g,b))
            flat[y*w+x]=variance<9.0 && spread<45.0 && gray[y*w+x]>90.0
        }}
        let radius=max(4,Int(Double(min(w,h))*0.018))
        var known=[Bool](repeating:false,count:gw*gh)
        var donors=0
        for y in 0..<gh {for x in 0..<gw {
            let cx=x*(w-1)/(gw-1),cy=y*(h-1)/(gh-1)
            let x0=max(0,cx-radius),x1=min(w,cx+radius+1),y0=max(0,cy-radius),y1=min(h,cy+radius+1)
            var red:[Double]=[],green:[Double]=[],blue:[Double]=[]
            for yy in y0..<y1 {for xx in x0..<x1 where flat[yy*w+xx] {
                let base=(yy*w+xx)*3
                red.append(pixels[base]);green.append(pixels[base+1]);blue.append(pixels[base+2])
            }}
            guard red.count*4>=(x1-x0)*(y1-y0) else {continue}
            let paper=[percentile(red,0.75),percentile(green,0.75),percentile(blue,0.75)]
            let base=(y*gw+x)*3
            let expected=(field[base]+field[base+1]+field[base+2])/3.0
            let measured=(paper[0]+paper[1]+paper[2])/3.0
            let ratio=measured/expected
            if ratio>0.86 && ratio<1.15 {
                for c in 0..<3 {field[base+c]=paper[c]}
                known[y*gw+x]=true;donors+=1
            }
        }}
        // Dense copies and portraits: use only outer paper illumination.
        // Letting their gray content act as white paper produces bleached faces.
        if Double(donors)<Double(gw*gh)*0.60 {field=initial;known=[Bool](repeating:false,count:gw*gh)}
        for _ in 0..<150 {
            var next=field
            for y in 1..<(gh-1) {for x in 1..<(gw-1) where !known[y*gw+x] {
                let base=(y*gw+x)*3
                for c in 0..<3 {
                    let upper=field[base-gw*3+c],lower=field[base+gw*3+c]
                    let before=field[base-3+c],after=field[base+3+c]
                    next[base+c]=(upper+lower+before+after)/4.0
                }
            }}
            field=next
        }
        var output=rgba
        for y in 0..<height {
            let py=max(0.0,min(Double(gh-1),(Double(y)+0.5)*Double(gh)/Double(height)-0.5))
            let y0=Int(py),y1=min(gh-1,y0+1),fy=py-Double(y0)
            for x in 0..<width {
                let px=max(0.0,min(Double(gw-1),(Double(x)+0.5)*Double(gw)/Double(width)-0.5))
                let x0=Int(px),x1=min(gw-1,x0+1),fx=px-Double(x0)
                let base=(y*width+x)*4
                for c in 0..<3 {
                    let upper=field[(y0*gw+x0)*3+c]*(1.0-fx)+field[(y0*gw+x1)*3+c]*fx
                    let lower=field[(y1*gw+x0)*3+c]*(1.0-fx)+field[(y1*gw+x1)*3+c]*fx
                    let light=min(255.0,max(80.0,upper*(1.0-fy)+lower*fy))
                    let value=Double(rgba[base+c])*255.0/light
                    output[base+c]=UInt8(min(255.0,max(0.0,value.rounded())))
                }
            }
        }
        return output
    }
}


// Relative edge acutance, not raw Laplacian variance: broad blurred edges
// must not pass just because text is dark. Inspect several interior patches.
struct TextDetail {
    let acutance:Double
    let patches:Int
    var clear:Bool {patches>=2 && acutance>=0.48}
    static func measure(_ gray:[UInt8],width:Int,height:Int,quad:Quad)->TextDetail {
        guard width>=32,height>=32,gray.count==width*height,quad.valid else {return TextDetail(acutance:0,patches:0)}
        let xs=quad.points.map {$0.x},ys=quad.points.map {$0.y}
        let left=xs.min() ?? 0,right=xs.max() ?? 1,top=ys.min() ?? 0,bottom=ys.max() ?? 1
        var scores:[Double]=[],centralScores:[Double]=[]
        for row in 0..<5 {for column in 0..<5 {
            let u=left+(right-left)*(0.12+Double(column)*0.15)
            let v=top+(bottom-top)*(0.12+Double(row)*0.15)
            let du=(right-left)*0.12,dv=(bottom-top)*0.12
            let corners=[Point(x:u,y:v),Point(x:u+du,y:v),Point(x:u,y:v+dv),Point(x:u+du,y:v+dv)]
            guard corners.allSatisfy({CropSafety.contains($0,in:quad,tolerance:0)}) else {continue}
            let x0=max(1,Int(u*Double(width))),x1=min(width-1,Int((u+du)*Double(width)))
            let y0=max(1,Int(v*Double(height))),y1=min(height-1,Int((v+dv)*Double(height)))
            guard x1>x0,y1>y0 else {continue}
            var lap=0.0,gradient=0.0,count=0
            for y in y0..<y1 {for x in x0..<x1 {
                let i=y*width+x
                let c=Int(gray[i]),l=Int(gray[i-1]),r=Int(gray[i+1]),t=Int(gray[i-width]),b=Int(gray[i+width])
                let edge=abs(r-l)+abs(b-t)
                if edge>18 {lap+=Double(abs(4*c-l-r-t-b));gradient+=Double(edge);count+=1}
            }}
            if count>=30 && gradient>0 {
                let value=lap/gradient;scores.append(value)
                if row>=1 && row<=3 && column>=1 && column<=3 {centralScores.append(value)}
            }
        }}
        scores.sort()
        var middle=scores.isEmpty ? 0:scores[scores.count/2]
        centralScores.sort()
        if centralScores.count>=2 {middle=min(middle,centralScores[centralScores.count/2])}
        return TextDetail(acutance:middle,patches:scores.count)
    }
}

// A quiet lens is necessary, but not sufficient: require readable edge detail
// in consecutive fresh frames as well. No deadline bypasses either condition.
struct FocusQualityHold {
    private var lens:Float?
    private var previousTime:Double?
    private var credit=0.0
    mutating func reset() {lens=nil;previousTime=nil;credit=0}
    mutating func update(position:Float,adjusting:Bool,detail:TextDetail,time:Double)->Bool {
        let gap=time-(previousTime ?? time)
        let moved=lens.map {abs($0-position)>0.004} ?? true
        lens=position;previousTime=time
        if adjusting || moved || !detail.clear || gap>0.6 || gap<0 {credit=0;return false}
        credit+=min(0.3,max(0,gap))
        return credit>=0.4
    }
}

// Bounded dark-side detail enhancement. Never generates glyphs, bright halos
// or new resolution. Flat regions and low-amplitude paper grain stay unchanged.
enum DocumentDetail {
    static func enhance(_ rgba:[UInt8],width:Int,height:Int,amount:Double=0.85)->[UInt8] {
        let strength=max(0,min(1.5,amount))
        if strength==0 {return rgba}
        guard width>=5,height>=5,rgba.count==width*height*4 else {return rgba}
        let count=width*height
        var luminance=[UInt16](repeating:0,count:count)
        for p in 0..<count {
            let i=p*4
            let red:Int=Int(rgba[i])
            let green:Int=Int(rgba[i+1])
            let blue:Int=Int(rgba[i+2])
            let redPart:Int=54*red
            let greenPart:Int=183*green
            let bluePart:Int=19*blue
            let redGreen:Int=redPart+greenPart
            let weighted:Int=redGreen+bluePart
            let rounded:Int=weighted+128
            let gray:Int=rounded/256
            luminance[p]=UInt16(gray)
        }
        var horizontal=[UInt16](repeating:0,count:count)
        for y in 0..<height {for x in 0..<width {
            let p=y*width+x,l=y*width+max(0,x-1),r=y*width+min(width-1,x+1)
            let left:Int=Int(luminance[l])
            let middle:Int=Int(luminance[p])*2
            let right:Int=Int(luminance[r])
            let partial:Int=left+middle
            horizontal[p]=UInt16(partial+right)
        }}
        var output=rgba
        for y in 1..<(height-1) {for x in 1..<(width-1) {
            let p=y*width+x
            let center=Int(luminance[p])
            guard center>18 else {continue}
            let upper:Int=Int(horizontal[p-width])
            let middle:Int=Int(horizontal[p])*2
            let lower:Int=Int(horizontal[p+width])
            let firstSum:Int=upper+middle
            let total:Int=firstSum+lower
            let mean:Double=Double(total)/16.0
            let detail=mean-Double(center)
            guard detail>2.0 else {continue}
            let l:Int=Int(luminance[p-1])
            let r:Int=Int(luminance[p+1])
            let t:Int=Int(luminance[p-width])
            let b:Int=Int(luminance[p+width])
            let horizontalEdge:Int=abs(r-l)
            let verticalEdge:Int=abs(b-t)
            let gradient:Int=horizontalEdge+verticalEdge
            let low:Int=min(min(l,r),min(t,b))
            let high:Int=max(max(l,r),max(t,b))
            let span:Int=high-low
            guard gradient>=12 || span>=12 else {continue}
            let adjustment=Int(min(20.0,(detail-2.0)*strength).rounded())
            guard adjustment>0 else {continue}
            for c in 0..<3 {let i=p*4+c;output[i]=UInt8(max(0,Int(rgba[i])-adjustment))}
        }}
        return output
    }
}


enum CaptureSampling {
    static func sufficient(_ quad:Quad)->Bool {
        guard quad.valid,CropSafety.area(quad)>=0.28 else {return false}
        let xs=quad.points.map {$0.x},ys=quad.points.map {$0.y}
        let width=(xs.max() ?? 0)-(xs.min() ?? 0)
        let height=(ys.max() ?? 0)-(ys.min() ?? 0)
        return max(width,height)>=0.65
    }
}

// Capture readiness is independent of OCR, glyph size and paper coverage.
// Only hardware settling is gated; page motion is handled by CaptureStability.
struct LensSettleHold {
    private var previousPosition:Float?
    private var previousTime:Double?
    private var credit=0.0
    mutating func reset() {previousPosition=nil;previousTime=nil;credit=0}
    mutating func update(position:Float,adjusting:Bool,time:Double)->Bool {
        let elapsed=time-(previousTime ?? time)
        let moved=previousPosition.map {abs($0-position)>0.004} ?? true
        previousPosition=position;previousTime=time
        if adjusting || moved || elapsed<0 || elapsed>1.5 {credit=0;return false}
        credit+=min(0.3,max(0,elapsed))
        return credit>=0.20
    }
}

// A disconnected hairline cannot seed the old flood fill. Inspect each of the
// four outer margins independently, requiring a long thin run AND clean paper
// behind it. A localized stamp or glyph never provides enough support.
enum EdgeFringe {
    static func mask(_ rgba:[UInt8],width w:Int,height h:Int,margin:Int=8)->[UInt8] {
        guard w>=80,h>=80,rgba.count==w*h*4 else {return [UInt8](repeating:0,count:max(0,w*h))}
        var result=[UInt8](repeating:0,count:w*h)
        let depth=min(72,max(8,min(w,h)/90)+max(0,min(24,margin)))
        let extra=max(1,min(24,margin))
        for side in 0..<4 {
            let length=side<2 ? w:h
            func index(_ along:Int,_ inward:Int)->Int {
                switch side {
                case 0:return inward*w+along
                case 1:return (h-1-inward)*w+along
                case 2:return along*w+inward
                default:return along*w+w-1-inward
                }
            }
            func light(_ p:Int)->Int {let i=p*4;return (Int(rgba[i])+Int(rgba[i+1])+Int(rgba[i+2]))/3}
            let step=max(1,length/400)
            let start=length/30,end=length-length/30
            var selected:[Int]=[]
            for d in 0..<depth {
                var votes=0,total=0,minHit=length,maxHit=0,run=0,longest=0
                for a in stride(from:start,to:end,by:step) {
                    total+=1
                    let p=index(a,d),i=p*4
                    let r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
                    let back=light(index(a,min(depth+10,d+7)))
                    let value=(r+g+b)/3
                    // Pale gray/blue JPEG fragments count, saturated ink does not.
                    var thick=0
                    if back>=185 && back-value>=22 {
                        for cross in max(0,d-4)...(d+4) {if back-light(index(a,cross))>=22 {thick+=1}}
                    }
                    if back>=185 && back-value>=22 && thick<6 && max(r,max(g,b))-min(r,min(g,b))<65 {
                        votes+=1;minHit=min(minHit,a);maxHit=max(maxHit,a);run+=step;longest=max(longest,run)
                    } else {run=0}
                }
                if total>0 && votes*100>=total*32 && maxHit-minHit>length*3/5 && longest>=length/12 {selected.append(d)}
            }
            // Thick content blocks/photographs are not a paper edge.
            guard !selected.isEmpty,selected.count<=max(5,depth/3) else {continue}
            for d in selected {
                let behind=min(h,w)-1
                for a in 0..<length {
                    let p=index(a,d),i=p*4
                    let r=Int(rgba[i]),g=Int(rgba[i+1]),b=Int(rgba[i+2])
                    let back=light(index(a,min(behind,d+7)))
                    guard back>=185,back-(r+g+b)/3>=14,max(r,max(g,b))-min(r,min(g,b))<65 else {continue}
                    // Widen only the supported line. Never erase a whole page margin.
                    for dd in max(0,d-1)...min(depth-1,d+min(3,extra)) {
                        let q=index(a,dd),j=q*4
                        if !EdgeBand.protectedInk(Int(rgba[j]),Int(rgba[j+1]),Int(rgba[j+2])) || dd==d {result[q]=255}
                    }
                }
            }
        }
        return result
    }
}
