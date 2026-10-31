import Foundation

struct Detection {
    let kind: String
    let starts: Bool
    let warning: String?
}

enum Rules {
    static let unknown = "Не визначено"
    static let types = [unknown, "Заява", "Свідоцтво про смерть", "Свідоцтво про хворобу", "Протокол ВЛК", "Довідка ВЛК", "Витяг з рішення експертної команди", "Довідка МСЕК", "Паспорт", "РНОКПП", "Військовий квиток", "Довідка про обставини травми", "Реквізити", "Згода", "Інше"]
    static func norm(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "і", with: "i")
            .replacingOccurrences(of: "’", with: "'")
    }
    static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }
    static func classify(_ text: String) -> Detection {
        let lines = text.split(separator: "\n").map { norm(String($0)) }.filter { !$0.isEmpty }
        let head = lines.prefix(16).joined(separator: " ")
        let top = lines.prefix(8).joined(separator: " ")
        func hit(_ name: String, _ warning: String? = nil) -> Detection {
            Detection(kind: name, starts: true, warning: warning)
        }
        if matches(head, "додат(?:ок|ку|ка)\\s+до\\s+протокол") {
            return Detection(kind: "Протокол ВЛК", starts: false, warning: "Перевірте, до якого протоколу належить додаток")
        }
        // A protocol heading takes precedence over an illness certificate mentioned inside it.
        if matches(head, "протокол.{0,120}(влк|рвлк|засiданн|вiйськово.?лiкарськ|комiсi)") {
            return hit("Протокол ВЛК")
        }
        if matches(top, "свiдоцтв.{0,35}хвороб") { return hit("Свідоцтво про хворобу") }
        if matches(top, "свiдоцтв.{0,35}смерт") { return hit("Свідоцтво про смерть") }
        if matches(head, "витяг.{0,90}реєстр.{0,60}територiальн") {
            return Detection(kind: "Паспорт", starts: false, warning: "Приєднати до паспорта: перевірте власника")
        }
        if matches(top, "витяг.{0,40}рiшенн.{0,90}експертн") ||
            (matches(head, "номер (витягу|рiшення)|дата прийняття рiшення") && matches(head, "експертн")) {
            return hit("Витяг з рішення експертної команди")
        }
        var candidates: [String] = []
        let patterns: [(String, String)] = [
            ("Заява", "\\bзаява\\b"),
            ("Довідка МСЕК", "довiдк.{0,75}мсек|мсек.{0,75}довiдк"),
            ("Паспорт", "паспорт.{0,50}(громадян|укра|серiя)"),
            ("РНОКПП", "рнокпп|реєстрацiйн.{0,55}картк.{0,55}платник|iдентифiкацiйн.{0,35}номер"),
            ("Військовий квиток", "вiйськов.{0,20}квиток"),
            ("Довідка про обставини травми", "довiдка.{0,90}обставин.{0,65}травм"),
            ("Довідка ВЛК", "довiдк.{0,80}влк"),
            ("Реквізити", "банкiвськ.{0,20}реквiзит|реквiзити.{0,45}(рахунк|отримувач|одержувач)|iban"),
            ("Згода", "згода.{0,90}(персональн|обробк)")
        ]
        for (kind, pattern) in patterns where matches(head, pattern) { candidates.append(kind) }
        if candidates.contains("Заява") { return hit("Заява", candidates.count > 1 ? "У заяві згадані інші документи — перевірте межу" : nil) }
        if candidates.contains("Паспорт") && candidates.contains("РНОКПП") {
            return hit("Паспорт", "Паспорт і РНОКПП на одному аркуші: потрібна окрема обробка фрагментів")
        }
        if candidates.count == 1 { return hit(candidates[0]) }
        return Detection(kind: unknown, starts: false, warning: candidates.isEmpty ? "Не знайдено надійного заголовка" : "Кілька типів документа на сторінці")
    }
    static func ibans(_ text: String) -> [String] {
       let pattern = #"(?i)U[ \t\r\n-]*A(?:[ \t\r\n-]*[0-9]){27}(?![0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return Array(Set(regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range).uppercased().filter { $0.isLetter || $0.isNumber }
        })).sorted()
    }
    static func validIBAN(_ value: String) -> Bool {
        guard value.count == 29, value.hasPrefix("UA") else { return false }
        let shifted = String(value.dropFirst(4)) + String(value.prefix(4))
        var remainder = 0
        for ch in shifted {
            guard let ascii = ch.asciiValue else { return false }
            let digits = ascii >= 65 && ascii <= 90 ? String(Int(ascii) - 55) : String(ch)
            for digit in digits {
                guard let n = digit.wholeNumberValue else { return false }
                remainder = (remainder * 10 + n) % 97
            }
        }
        return remainder == 1
    }
    static func safe(_ s: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r")
        let name = s.components(separatedBy: bad).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Без_назви" : String(name.prefix(120))
    }
}
