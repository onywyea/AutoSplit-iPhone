import SwiftUI

struct LibraryBrandSection:View {
    var body:some View {
        Section {
            HStack(spacing:12) {
                ScanMark()
                VStack(alignment:.leading,spacing:3) {
                    Text("ScanFlow").font(.headline)
                    Text("Скануйте серією. Перевіряйте вибірково.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical,4)
        }.listRowBackground(Color.clear)
    }
}
struct LibraryResumeSection:View {
    let document:ScanDocument
    let disabled:Bool
    let open:()->Void
    private var summary:String {
        let count=document.pages.count
        let pending=document.pages.filter {$0.reviewReason != nil}.count
        return "\(count) стор. · \(pending) до перевірки"
    }
    var body:some View {
        Section("Продовжити комплект") {
            Button(action:open) {
                VStack(alignment:.leading,spacing:9) {
                    Text(document.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                    Label("Продовжити перевірку",systemImage:"arrow.right.circle.fill").font(.subheadline.weight(.semibold))
                }.padding(.vertical,6)
            }.disabled(disabled)
        }
    }
}
struct LibraryEmptyState:View {
    let searching:Bool
    var body:some View {
        ContentUnavailableView(searching ? "Нічого не знайдено":"Поки немає сканів",systemImage:searching ? "magnifyingglass":"doc.viewfinder",description:Text(searching ? "Спробуйте іншу назву.":"Скануйте камерою або імпортуйте PDF і фото."))
            .listRowBackground(Color.clear)
    }
}
struct LibraryDocumentRow:View {
    let document:ScanDocument
    let selecting:Bool
    let selected:Bool
    private var summary:String {
        let date=document.created.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier:"uk_UA")))
        return "\(document.pages.count) стор. · \(date)"
    }
    var body:some View {
        HStack(spacing:12) {
            if selecting {Image(systemName:selected ? "checkmark.circle.fill":"circle").font(.title3).foregroundStyle(Color.accent)}
            Thumb(file:document.pages.first?.output).frame(width:52,height:70).clipShape(RoundedRectangle(cornerRadius:6))
            VStack(alignment:.leading,spacing:5) {
                Text(document.title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Text(summary).font(.caption).foregroundStyle(.secondary)
                if !document.nameConfirmed && !document.candidates.isEmpty {Text("ПІБ знайдено · перевірте назву").font(.caption2).foregroundStyle(Color.accent)}
            }
            Spacer(minLength:0)
            if !selecting {Image(systemName:"chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)}
        }.padding(.vertical,5).contentShape(Rectangle())
    }
}
