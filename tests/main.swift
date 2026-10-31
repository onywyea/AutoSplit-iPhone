import Foundation
var passed=0
func check(_ result:Bool,_ name:String) { if !result{print("FAIL: \(name)");exit(1)};passed+=1 }
func names(_ text:String)->[String] {NameFinder.candidates(text).map(\.name)}
check(names("ПІБ: Іваненко Іван Іванович")==["Іваненко Іван Іванович"],"explicit name")
check(names("Отримувач: КОВАЛЕНКО ОЛЕНА ПЕТРІВНА")==["Коваленко Олена Петрівна"],"uppercase")
check(names("Паспорт Громадянина України").isEmpty,"passport heading is not a name")
check(names("Міністерство Оборони України").isEmpty,"ministry is not a name")
check(names("Прізвище\nІВАНЕНКО\nІм’я\nІВАН\nПо батькові\nІВАНОВИЧ")==["Іваненко Іван Іванович"],"separate fields")
check(names("Іваненко Іван Іванович\nКоваленко Олена Петрівна").count==2,"keep both people")
check(names("Іваненко Іван Іванович\nІваненко Іван Іванович").count==1,"deduplicate")
check(names("Іваненко І. І.").isEmpty,"do not invent full name from initials")
check(names("Номер 1234567890").isEmpty,"no false name from number")
check(NameFinder.candidates("Загиблого військовослужбовця: Іваненко Іван Іванович").first?.explicit == true,"person context")
check(NameFinder.safeName("Іваненко/Іван:Іванович")=="Іваненко_Іван_Іванович","safe PDF path")
check(NameFinder.safeName("   ")=="Скан","empty name")
check(Quad.full.valid,"default corners")
check(!Quad(points:[.init(x:0,y:0),.init(x:1,y:1),.init(x:1,y:0),.init(x:0,y:1)]).valid,"reject crossed corners")
check(!Quad(points:[.init(x:-0.1,y:0),.init(x:1,y:0),.init(x:1,y:1),.init(x:0,y:1)]).valid,"reject outside image")
check(!Quad(points:[.init(x:0,y:0),.init(x:0.01,y:0),.init(x:0.01,y:0.01),.init(x:0,y:0.01)]).valid,"reject near-zero crop")
check(!Quad(points:[]).valid,"reject missing corners")
print("\(passed) core checks passed")
