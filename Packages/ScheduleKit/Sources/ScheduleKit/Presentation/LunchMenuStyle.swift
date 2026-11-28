import SwiftUI

public extension LunchMenuStation {
    var title: String {
        switch self {
        case .comfort: return "Comfort Food"
        case .mindful: return "Mindful"
        case .sides: return "Sides"
        case .soup: return "Soup"
        case .international: return "International"
        case .special: return "Special"
        }
    }
}
