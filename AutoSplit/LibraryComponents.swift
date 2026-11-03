import SwiftUI

struct LibraryBrandSection:View {
    var body:some View {
        HStack(alignment:.top,spacing:12) {
            VStack(alignment:.leading,spacing:5) {
                Text("Ваші документи").font(.system(.title,design:.rounded,weight:.bold)).tracking(-0.7)
                Text("Від кадру до готового PDF").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
            ScanMark()
        }.padding(.vertical,6)
    }
}
struct LibraryResumeSection:View {
    let document:ScanDocument
    let disabled:Bool
    let open:()->Void
    private var pending:Int {document.pages.filter {$0.reviewReason != nil}.count}
    var body:some View {
        Button(action:open) {
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    Label("ПРОДОВЖИТИ",systemImage:"clock.arrow.circlepath").font(.caption2.weight(.bold)).tracking(0.8)
                    Spacer(minLength:0)
                    Text("\(document.pages.count) стор.").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(document.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                HStack {
                    Text(pending>0 ? "Можна уточнити · \(pending)":"Повернутися до комплекту").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength:0)
                    Image(systemName:"arrow.right").font(.subheadline.weight(.semibold)).frame(width:36,height:36).background(Color.accent.opacity(0.12),in:Circle())
                }
            }.padding(18).scanCard(radius:24)
        }.buttonStyle(.plain).foregroundStyle(Color.accent).disabled(disabled)
    }
}
struct LibraryEmptyState:View {
    let searching:Bool
    var body:some View {
        VStack(spacing:14) {
            Image(systemName:searching ? "magnifyingglass":"doc.viewfinder").font(.system(size:42,weight:.light)).foregroundStyle(Color.accent)
            Text(searching ? "Нічого не знайдено":"Перший скан — один дотик").font(.headline)
            Text(searching ? "Спробуйте іншу назву.":"Натисніть «Новий скан» або імпортуйте готовий файл.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth:.infinity).padding(.vertical,42).padding(.horizontal,20).scanCard()
    }
}
struct LibraryDocumentRow:View {
    let document:ScanDocument
    let selecting:Bool
    let selected:Bool
    private var date:String {document.created.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier:"uk_UA")))}
    private var pending:Int {document.pages.filter {$0.reviewReason != nil}.count}
    var body:some View {
        HStack(spacing:15) {
            thumbnail
            VStack(alignment:.leading,spacing:8) {
                Text(document.title).font(.headline).tracking(-0.2).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing:6) {
                    Text("\(document.pages.count) стор.").font(.caption.weight(.medium)).padding(.horizontal,8).padding(.vertical,4).background(Color.canvas,in:Capsule())
                    Text(date).font(.caption).foregroundStyle(.secondary)
                }
                if !document.nameConfirmed && !document.candidates.isEmpty {
                    Text("Перевірте ПІБ").font(.caption).foregroundStyle(Color.accent)
                } else if pending>0 {
                    Text("Можна уточнити · \(pending)").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth:.infinity,alignment:.leading)
            Image(systemName:selecting ? (selected ? "checkmark.circle.fill":"circle"):"arrow.up.right")
                .font(selecting ? .title2:.subheadline.weight(.medium)).foregroundStyle(selecting ? Color.accent:Color.secondary)
                .frame(width:28)
        }.padding(15).scanCard(radius:24)
            .overlay(RoundedRectangle(cornerRadius:24).stroke(selected && selecting ? Color.accent:.clear,lineWidth:2))
            .contentShape(RoundedRectangle(cornerRadius:24))
    }
    private var thumbnail:some View {
        ZStack {
            RoundedRectangle(cornerRadius:10).fill(Color.accent.opacity(0.12)).frame(width:57,height:78).rotationEffect(.degrees(-5)).offset(x:-2)
            Thumb(file:document.pages.first?.output).frame(width:57,height:78).background(Color.card).clipShape(RoundedRectangle(cornerRadius:9))
                .shadow(color:.black.opacity(0.14),radius:3,y:2)
        }.frame(width:62,height:84)
    }
}
