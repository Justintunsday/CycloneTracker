import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct CycloneSelection: MapSelectable {
    let id: String
    var feature: MapFeature?

    init(id: String) {
        self.id = id
        self.feature = nil
    }

    init(_ feature: MapFeature?) {
        self.feature = feature
        self.id = feature?.title ?? ""
    }

    static func == (lhs: CycloneSelection, rhs: CycloneSelection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension CLLocationCoordinate2D {
    var formatted: String {
        String(format: "%.1f°%@ %.1f°%@",
               abs(latitude), latitude >= 0 ? "N" : "S",
               abs(longitude), longitude >= 0 ? "E" : "W")
    }
}
