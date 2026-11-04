import SwiftUI
import UIKit

enum ScanAccent:String,CaseIterable,Identifiable {
    case coral,blue,violet,green,rose
    var id:String {rawValue}
    var title:String {
        switch self {case .coral:return "Кораловий";case .blue:return "Синій";case .violet:return "Фіолетовий";case .green:return "Зелений";case .rose:return "Рожевий"}
    }
    var color:Color {
        let choice=self
        return Color(uiColor:UIColor {trait in
            let dark=trait.userInterfaceStyle == .dark
            switch choice {
            case .coral:return dark ? UIColor(red:1,green:0.63,blue:0.43,alpha:1):UIColor(red:0.71,green:0.22,blue:0.07,alpha:1)
            case .blue:return dark ? UIColor(red:0.40,green:0.70,blue:1,alpha:1):UIColor(red:0.05,green:0.33,blue:0.74,alpha:1)
            case .violet:return dark ? UIColor(red:0.74,green:0.61,blue:1,alpha:1):UIColor(red:0.43,green:0.22,blue:0.73,alpha:1)
            case .green:return dark ? UIColor(red:0.41,green:0.84,blue:0.61,alpha:1):UIColor(red:0.08,green:0.42,blue:0.25,alpha:1)
            case .rose:return dark ? UIColor(red:1,green:0.56,blue:0.72,alpha:1):UIColor(red:0.71,green:0.15,blue:0.37,alpha:1)
            }
        })
    }
}
