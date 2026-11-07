import Foundation

// Display-only formatting. The stored document title and exported filename stay intact.
struct StudioDocumentText: Equatable {
    let title: String
    let detail: String

    init(title storedTitle: String, personName: String?, suffix storedSuffix: String?) {
        var base = storedTitle
        var suffix = ScanNaming.suffix(storedSuffix ?? "")
        if !suffix.isEmpty, base.hasSuffix("_" + suffix) {
            base = String(base.dropLast(suffix.count + 1))
        } else if suffix.isEmpty {
            let tokens = base.split(separator: "_").map(String.init)
            if let boundary = tokens.indices.dropFirst().first(where: { index in
                let token = tokens[index]
                return token.range(of: "^ПКМУ[0-9]+$", options: .regularExpression) != nil
                    || NameSuffixParts.relations.contains(token.lowercased())
            }) {
                suffix = tokens[boundary...].joined(separator: "_")
                base = tokens[..<boundary].joined(separator: "_")
            }
        }
        if let personName, !personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = ScanNaming.shortName(personName)
        }
        let words = base.split(whereSeparator: { $0 == "_" || $0.isWhitespace }).map(String.init)
        if words.count == 2, let initials = words.last, (1...3).contains(initials.count),
           initials.allSatisfy({ $0.isLetter && $0.isUppercase }) {
            title = words[0] + " " + initials.map { String($0) + "." }.joined(separator: " ")
        } else {
            title = words.joined(separator: " ")
        }
        let parts = NameSuffixParts.parse(suffix)
        let relation = [parts.relation, parts.childName].filter { !$0.isEmpty }.joined(separator: " ")
        detail = [parts.base.replacingOccurrences(of: "_", with: " "), relation]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
