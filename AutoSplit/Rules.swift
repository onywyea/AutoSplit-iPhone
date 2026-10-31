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
