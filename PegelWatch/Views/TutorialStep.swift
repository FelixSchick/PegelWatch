import SwiftUI

// MARK: - Models

private struct TutorialStep: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let badge: String?
    let title: String
    let body: String
    let hint: String?
    let illustrationKind: IllustrationKind
    let action: (() async -> Void)?

    enum IllustrationKind {
        case welcome
        case watchlist
        case search
        case detail
        case alarm
        case notification
        case widget
    }

    init(
        icon: String,
        iconColor: Color,
        badge: String? = nil,
        title: String,
        body: String,
        hint: String? = nil,
        illustrationKind: IllustrationKind,
        action: (() async -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.badge = badge
        self.title = title
        self.body = body
        self.hint = hint
        self.illustrationKind = illustrationKind
        self.action = action
    }
}

private let tutorialSteps: [TutorialStep] = [
    TutorialStep(
        icon: "water.waves",
        iconColor: .blue,
        title: "Willkommen bei PegelWatch",
        body: "Behalte Wasserstände an deinen Lieblingsgewässern jederzeit im Blick – direkt auf deinem iPhone und als Widget.",
        illustrationKind: .welcome
    ),
    TutorialStep(
        icon: "list.star",
        iconColor: .teal,
        badge: "Tab 1",
        title: "Deine Watchlist",
        body: "Alle beobachteten Messstationen landen hier. Du siehst auf einen Blick den aktuellen Pegelstand und den Alarmstatus jeder Station.",
        hint: "Wische nach links, um eine Station zu entfernen.",
        illustrationKind: .watchlist
    ),
    TutorialStep(
        icon: "magnifyingglass",
        iconColor: .indigo,
        badge: "Tab 2",
        title: "Stationen suchen & hinzufügen",
        body: "Suche aus über 4.000 Messstationen bundesweit. Filtere nach Gewässer oder tippe den Namen der Station ein – dann einfach auf \"+\" tippen.",
        hint: "Wähle ein Gewässer aus dem Menü, um alle Stationen auf einem Fluss auf einer Karte zu sehen.",
        illustrationKind: .search
    ),
    TutorialStep(
        icon: "chart.xyaxis.line",
        iconColor: .cyan,
        badge: "Detailansicht",
        title: "Pegelstand & Verlauf",
        body: "Tippe auf eine Station in der Watchlist, um den genauen Pegelstand, einen 7-Tage-Verlauf und alle Metadaten zu sehen.",
        illustrationKind: .detail
    ),
    TutorialStep(
        icon: "bell.badge",
        iconColor: .orange,
        badge: "Alarm",
        title: "Alarm-Schwellen setzen",
        body: "In der Detailansicht kannst du eigene Alarme anlegen. Wird ein Schwellenwert überschritten, bekommst du eine Push-Benachrichtigung.",
        hint: "Du kannst mehrere Alarme mit verschiedenen Farben und Namen anlegen – z. B. \"Bootsanleger\" oder \"Keller\".",
        illustrationKind: .alarm
    ),
    TutorialStep(
        icon: "bell.badge.fill",
        iconColor: .mint,
        badge: "Berechtigung",
        title: "Alarme nie verpassen",
        body: "PegelWatch benötigt die Erlaubnis für Push-Benachrichtigungen, damit du sofort informiert wirst, wenn ein Pegel deinen Schwellenwert überschreitet.",
        hint: "Du kannst Benachrichtigungen jederzeit in den iOS-Einstellungen verwalten.",
        illustrationKind: .notification,
        action: { await NotificationManager.shared.requestPermission() }
    ),
    TutorialStep(
        icon: "square.grid.2x2",
        iconColor: .purple,
        badge: "Widget",
        title: "Live-Widget & Dynamic Island",
        body: "Füge ein PegelWatch-Widget zum Home Screen hinzu. Aktive Alarme erscheinen zusätzlich in der Dynamic Island und als Live Activity.",
        hint: "Halte den Home Screen gedrückt → \"+\" → PegelWatch, um ein Widget hinzuzufügen.",
        illustrationKind: .widget
    ),
]

// MARK: - Main View

struct TutorialView: View {
    var onFinish: () -> Void

    @State private var currentStep = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isAnimatingIn = false
    @State private var isPerformingAction = false

    private var isLast: Bool { currentStep == tutorialSteps.count - 1 }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                skipButton
                    .padding(.top, 12)
                    .padding(.trailing, 20)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                TabView(selection: $currentStep) {
                    ForEach(Array(tutorialSteps.enumerated()), id: \.offset) { index, step in
                        StepCard(step: step)
                            .tag(index)
                            .padding(.horizontal, 8)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.45, dampingFraction: 0.82), value: currentStep)

                VStack(spacing: 20) {
                    HStack(spacing: 8) {
                        ForEach(0..<tutorialSteps.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentStep
                                      ? tutorialSteps[currentStep].iconColor
                                      : Color.secondary.opacity(0.35))
                                .frame(width: i == currentStep ? 24 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentStep)
                        }
                    }

                    Button(action: advance) {
                        HStack(spacing: 8) {
                            if isPerformingAction {
                                ProgressView()
                                    .scaleEffect(0.85)
                            } else {
                                Text(isLast ? "Los geht's!" : "Weiter")
                                    .fontWeight(.semibold)
                                Image(systemName: isLast ? "checkmark" : "arrow.right")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.blue)
                    .padding(.horizontal, 24)
                    .disabled(isPerformingAction)
                }
                .padding(.bottom, 44)
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Subviews

    private var skipButton: some View {
        Button("Überspringen") {
            onFinish()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .buttonStyle(.glass)
    }

    private var backgroundGradient: some View {
        let step = tutorialSteps[currentStep]
        return LinearGradient(
            colors: [
                step.iconColor.opacity(0.22),
                step.iconColor.opacity(0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .animation(.easeInOut(duration: 0.5), value: currentStep)
    }

    // MARK: - Actions

    private func advance() {
        let step = tutorialSteps[currentStep]
        if let action = step.action {
            isPerformingAction = true
            Task {
                await action()
                isPerformingAction = false
                performAdvance()
            }
        } else {
            performAdvance()
        }
    }

    private func performAdvance() {
        if isLast {
            onFinish()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                currentStep += 1
            }
        }
    }
}

// MARK: - Step Card

private struct StepCard: View {
    let step: TutorialStep

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)

            StepIllustration(kind: step.illustrationKind, color: step.iconColor)
                .frame(height: 220)

            VStack(spacing: 12) {
                if let badge = step.badge {
                    Text(badge.uppercased())
                        .font(.caption2.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(step.iconColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(step.iconColor.opacity(0.15), in: Capsule())
                }

                Text(step.title)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                Text(step.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                if let hint = step.hint {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.top, 1)
                        Text(hint)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pegelCard(tint: .orange.opacity(0.1), cornerRadius: 12)
                }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 8)
        }
    }
}

// MARK: - Illustrations

private struct StepIllustration: View {
    let kind: TutorialStep.IllustrationKind
    let color: Color

    var body: some View {
        switch kind {
        case .welcome:      WelcomeIllustration(color: color)
        case .watchlist:    WatchlistIllustration(color: color)
        case .search:       SearchIllustration(color: color)
        case .detail:       DetailIllustration(color: color)
        case .alarm:        AlarmIllustration(color: color)
        case .notification: NotificationIllustration(color: color)
        case .widget:       WidgetIllustration(color: color)
        }
    }
}

// --- Welcome ---
private struct WelcomeIllustration: View {
    let color: Color
    @State private var wave = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 180, height: 180)

            Circle()
                .fill(color.opacity(0.08))
                .frame(width: 240, height: 240)
                .scaleEffect(wave ? 1.06 : 1.0)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: wave)

            Image(systemName: "water.waves")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(color)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        }
        .onAppear { wave = true }
    }
}

// --- Watchlist ---
private struct WatchlistIllustration: View {
    let color: Color

    private let rows: [(name: String, value: String, level: Color)] = [
        ("KÖLN",    "423 cm", .green),
        ("MAINZ",   "312 cm", .yellow),
        ("PASSAU",  "671 cm", .red),
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { i in
                let row = rows[i]
                HStack(spacing: 12) {
                    Circle()
                        .fill(row.level.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "water.waves")
                                .font(.system(size: 16))
                                .foregroundStyle(row.level)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("RHEIN · km 688")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(row.value)
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundStyle(row.level)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .pegelCard(cornerRadius: 12)
            }
        }
        .padding(.horizontal, 24)
    }
}

// --- Search ---
private struct SearchIllustration: View {
    let color: Color
    @State private var typed = ""
    private let target = "KÖLN"

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text(typed.isEmpty ? "Station oder Gewässer…" : typed)
                    .font(.subheadline)
                    .foregroundStyle(typed.isEmpty ? .secondary : .primary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .pegelCard(cornerRadius: 12)

            VStack(spacing: 8) {
                ForEach(["KÖLN", "KOBLENZ", "KREFELD"].prefix(typed.isEmpty ? 3 : 1), id: \.self) { name in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("RHEIN")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: name == "KÖLN" && !typed.isEmpty ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 22))
                            .foregroundStyle(name == "KÖLN" && !typed.isEmpty ? .green : color)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .pegelCard(cornerRadius: 10)
                }
            }
        }
        .padding(.horizontal, 24)
        .onAppear { animateTyping() }
    }

    private func animateTyping() {
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            for char in target {
                try? await Task.sleep(for: .milliseconds(180))
                typed.append(char)
            }
        }
    }
}

// --- Detail ---
private struct DetailIllustration: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(animate ? "423" : "400")
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 1.0), value: animate)
                    Text("cm")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                Label("Normal", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(.green.opacity(0.15), in: Capsule())
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .pegelCard(cornerRadius: 14)

            HStack(alignment: .bottom, spacing: 6) {
                ForEach([0.45, 0.55, 0.5, 0.65, 0.7, 0.6, 0.75], id: \.self) { h in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: animate ? 60 * h : 4)
                        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.3), value: animate)
                }
            }
            .frame(height: 60)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .pegelCard(cornerRadius: 12)
        }
        .padding(.horizontal, 24)
        .onAppear { animate = true }
    }
}

// --- Alarm ---
private struct AlarmIllustration: View {
    let color: Color
    @State private var ring = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(color)
                .rotationEffect(.degrees(ring ? 18 : -18))
                .animation(.easeInOut(duration: 0.15).repeatCount(8, autoreverses: true), value: ring)
                .task {
                    try? await Task.sleep(for: .milliseconds(500))
                    ring = true
                }

            ForEach([
                ("Bootsanleger", "350 cm", Color.yellow),
                ("Keller",       "500 cm", Color.orange),
                ("Kritisch",     "650 cm", Color.red),
            ], id: \.0) { name, val, col in
                HStack {
                    Circle().fill(col.opacity(0.2)).frame(width: 10, height: 10)
                        .overlay(Circle().fill(col).frame(width: 5, height: 5))
                    Text(name)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(val)
                        .font(.system(.footnote, design: .monospaced, weight: .bold))
                        .foregroundStyle(col)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .pegelCard(cornerRadius: 10)
            }
        }
        .padding(.horizontal, 24)
    }
}

// --- Notification ---
private struct NotificationIllustration: View {
    let color: Color
    @State private var show = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(color)
                .symbolEffect(.variableColor.iterative, options: .repeating)

            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "water.waves")
                            .font(.system(size: 18))
                            .foregroundStyle(color)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text("⚠️ Pegel-Alarm: KÖLN")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("RHEIN · Aktuell: 650 cm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .pegelCard(cornerRadius: 14)
            .offset(y: show ? 0 : 30)
            .opacity(show ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.4), value: show)
        }
        .padding(.horizontal, 24)
        .onAppear { show = true }
    }
}

// --- Widget ---
private struct WidgetIllustration: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "water.waves")
                    .font(.system(size: 20))
                    .foregroundStyle(color)
                Spacer()
                Text("423")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                Text("cm · KÖLN")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(width: 120, height: 120)
            .pegelCard(cornerRadius: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(color.opacity(pulse ? 0.7 : 0.2), lineWidth: 2)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "water.waves")
                        .font(.system(size: 16))
                        .foregroundStyle(color)
                    Text("PegelWatch")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("423")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .minimumScaleFactor(0.7)
                    Text("cm")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("KÖLN · Normal")
                    .font(.caption2)
                    .foregroundStyle(.green)
                Text("Aktualisiert gerade eben")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(width: 160, height: 120)
            .pegelCard(cornerRadius: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(color.opacity(pulse ? 0.4 : 0.1), lineWidth: 2)
                    .animation(.easeInOut(duration: 1.5).delay(0.4).repeatForever(autoreverses: true), value: pulse)
            )
        }
        .onAppear { pulse = true }
    }
}

#Preview {
    TutorialView(onFinish: {})
}
