import Foundation
struct Fixture: Decodable { let text: String; let kind: String; let starts: Bool }
let cases = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: "tests/cases.json")))
var failed = 0
for (i, item) in cases.enumerated() {
    let result = Rules.classify(item.text)
    if result.kind != item.kind || result.starts != item.starts {
        print("FAIL \(i + 1): \(result.kind), starts=\(result.starts); expected \(item.kind), starts=\(item.starts)")
        failed += 1
    }
}
// A generated synthetic UA account with a correct checksum, no real person's data.
let bban = String(repeating: "0", count: 22) + "1"
let payload = bban + "301000"
var mod = 0
for digit in payload { mod = (mod * 10 + digit.wholeNumberValue!) % 97 }
let valid = "UA" + String(format: "%02d", 98 - mod) + bban
if !Rules.validIBAN(valid) { failed += 1; print("FAIL valid checksum") }
let invalid = "UA00" + bban
if Rules.validIBAN(invalid) { failed += 1; print("FAIL invalid checksum") }
let spaced = valid.map(String.init).joined(separator: " ")
if Rules.ibans("IBAN: " + spaced) != [valid] { failed += 1; print("FAIL spaced IBAN extraction") }
if Rules.safe("дочка/Аліна") != "дочка_Аліна" { failed += 1; print("FAIL unsafe name") }
print("\(cases.count + 4) rule checks, failures: \(failed)")
if failed > 0 { exit(1) }
