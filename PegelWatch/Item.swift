//
//  Item.swift
//  PegelWatch
//
//  Created by Felix Schick on 24.03.26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
