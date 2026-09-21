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

    var icon: String {
        switch self {
        case .comfort: return "takeoutbag.and.cup.and.straw.fill"
        case .mindful: return "leaf.fill"
        case .sides: return "carrot.fill"
        case .soup: return "cup.and.saucer.fill"
        case .international: return "globe.americas.fill"
        case .special: return "sparkles"
        }
    }

}

public extension LunchMenuStation {
    var color: Color {
        switch self {
        case .comfort: return .orange
        case .mindful: return .green
        case .sides: return .yellow
        case .soup: return .red
        case .international: return .blue
        case .special: return .purple
        }
    }
}
