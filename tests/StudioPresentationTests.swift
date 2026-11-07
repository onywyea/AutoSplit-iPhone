import Foundation

@main struct StudioPresentationTests {
    static func main() {
        let samples: [(String, String?, String?, String, String)] = [
            ("Ткач_СО_ПКМУ168_дочка_Юлія", nil, nil, "Ткач С. О.", "ПКМУ168 · дочка Юлія"),
            ("Ткач_СО_ПКМУ168_син_Іван_Петро", nil, nil, "Ткач С. О.", "ПКМУ168 · син Іван Петро"),
            ("Шевченко-Коваль_АВ_ПКМУ975", nil, nil, "Шевченко-Коваль А. В.", "ПКМУ975"),
            ("Ткач_СО_ПКМУ168_мати", nil, "ПКМУ168_мати", "Ткач С. О.", "ПКМУ168 · мати"),
            ("Іванов_ОМ_ПКМУ168", "Іванов Олег Миколайович", "ПКМУ168", "Іванов О. М.", "ПКМУ168"),
            ("Акт_обстеження", nil, nil, "Акт обстеження", ""),
            ("Новий скан", nil, nil, "Новий скан", ""),
            ("Довідка", nil, "Пенсійна_справа", "Довідка", "Пенсійна справа")
        ]
        for (stored, person, suffix, title, detail) in samples {
            let result = StudioDocumentText(title: stored, personName: person, suffix: suffix)
            precondition(result.title == title, "Display title: \(stored) → \(result.title)")
            precondition(result.detail == detail, "Display detail: \(stored) → \(result.detail)")
        }
        print("16 checks: readable home titles, legacy filenames, relatives, custom names: OK")
    }
}
