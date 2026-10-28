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
    /// Nur für schwebende Elemente über farbigem Hintergrund (z.B. Einführung) —
    /// Inhalte gehören in Listen mit Standard-Zeilenhintergrund.
    func pegelCard(tint: Color? = nil, cornerRadius: CGFloat = PegelDesign.cardCornerRadius) -> some View {
        let glass: Glass = tint.map { .regular.tint($0) } ?? .regular
        return glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
    }
}

/// „vor 5 Minuten“ – aktualisiert sich minütlich statt sekündlich zu ticken.
struct RelativeTimeText: View {
    let date: Date
    var prefix: String = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            Text(prefix + date.formatted(.relative(presentation: .named)))
        }
    }
}
