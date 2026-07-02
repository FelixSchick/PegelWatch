import SwiftUI

/// Zentrale Design-Bausteine, damit alle Karten und Container
/// der App einheitlich aussehen.
enum PegelDesign {
    /// Einheitlicher Eckenradius für Karten und Container.
    static let cardCornerRadius: CGFloat = 16
}

extension View {
    /// Einheitlicher Kartenhintergrund im Liquid-Glass-Stil.
    /// `tint` färbt das Glas ein, z.B. für Alarmzustände.
    func pegelCard(tint: Color? = nil, cornerRadius: CGFloat = PegelDesign.cardCornerRadius) -> some View {
        let glass: Glass = tint.map { .regular.tint($0) } ?? .regular
        return glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }
}
