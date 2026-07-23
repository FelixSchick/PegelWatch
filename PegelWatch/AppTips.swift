import TipKit
import SwiftUI

struct WidgetTip: Tip {
    @Parameter static var hasWatchedStation: Bool = false

    var rules: [Rule] {
        #Rule(Self.$hasWatchedStation) { $0 == true }
    }

    var title: Text { Text("Widget auf dem Home Screen") }
    var message: Text? { Text("Halte den Home Screen gedrückt, tippe auf \"+\" und wähle PegelWatch, um den Pegel immer im Blick zu behalten.") }
    var image: Image? { Image(systemName: "square.grid.2x2") }
}

struct AlarmCreationTip: Tip {
    var title: Text { Text("Eigene Alarme anlegen") }
    var message: Text? { Text("Tippe auf \"+\", um eine eigene Alarmschwelle zu setzen – du wirst benachrichtigt, sobald der Pegel sie überschreitet.") }
    var image: Image? { Image(systemName: "bell.badge") }
}
