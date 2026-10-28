import SwiftUI

// MARK: - Models

private struct TutorialStep: Identifiable {
    let id = UUID()
    let icon: String
    let iconColor: Color
    let title: String
    let body: String
    let hint: String?
    let illustrationKind: IllustrationKind
    let action: (() async -> Void)?

    enum IllustrationKind {
        case welcome
        case notification
    }

    init(
        icon: String,
        iconColor: Color,
        title: String,
        body: String,
        hint: String? = nil,
        illustrationKind: IllustrationKind,
        action: (() async -> Void)? = nil
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.body = body
        self.hint = hint
        self.illustrationKind = illustrationKind
        self.action = action
    }
}

/// Bewusst kurz (HIG Onboarding): Alles Weitere erklären Tipps genau dort,
/// wo man sie braucht (Suche, Karte, Detailansicht, Widget-Tipp).
private let tutorialSteps: [TutorialStep] = [
    TutorialStep(
        icon: "water.waves",
        iconColor: .blue,
        title: "Willkommen bei PegelWatch",
        body: "Verfolge Wasserstände an deinen Gewässern und werde gewarnt, bevor es kritisch wird.",
        hint: "Tipps erscheinen dort, wo du sie brauchst – beim Suchen, auf der Karte und in der Detailansicht.",
        illustrationKind: .welcome
    ),
    TutorialStep(
        icon: "bell.badge.fill",
        iconColor: .mint,
        title: "Alarme nie verpassen",
        body: "Damit PegelWatch dich warnen kann, wenn ein Pegel deine Alarmschwelle erreicht, braucht die App die Erlaubnis für Mitteilungen.",
        hint: "Du kannst das jederzeit in den Einstellungen ändern.",
        illustrationKind: .notification,
        action: { await NotificationManager.shared.requestPermission() }
    ),
]

// MARK: - Main View

struct TutorialView: View {
    var onFinish: () -> Void

    @State private var currentStep = 0
    @State private var isPerformingAction = false

    private var step: TutorialStep { tutorialSteps[currentStep] }
    private var isLast: Bool { currentStep == tutorialSteps.count - 1 }

    private var primaryTitle: String {
        if step.action != nil { return "Mitteilungen erlauben" }
        return isLast ? "Los geht's" : "Weiter"
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Auf der Berechtigungsseite übernimmt „Später“ das Überspringen
                skipButton
                    .opacity(step.action == nil ? 1 : 0)
                    .disabled(step.action != nil)
                    .accessibilityHidden(step.action != nil)
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

                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        ForEach(0..<tutorialSteps.count, id: \.self) { i in
                            Capsule()
                                .fill(i == currentStep
                                      ? step.iconColor
                                      : Color.secondary.opacity(0.35))
                                .frame(width: i == currentStep ? 24 : 8, height: 8)
                        }
                    }
                    .animation(.snappy, value: currentStep)
                    // VoiceOver: Position statt unbeschrifteter Kapseln
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Seite \(currentStep + 1) von \(tutorialSteps.count)")

                    Button(action: advance) {
                        HStack(spacing: 8) {
                            if isPerformingAction {
                                ProgressView()
                            } else {
                                Text(primaryTitle)
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.blue)
                    .disabled(isPerformingAction)

                    if step.action != nil {
                        Button("Später", action: onFinish)
                            .font(.body.weight(.medium))
                            .disabled(isPerformingAction)
                    }
                }
                .padding(.horizontal, 24)
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
        LinearGradient(
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
            withAnimation(.snappy) {
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
        case .notification: NotificationIllustration(color: color)
        }
    }
}

// --- Welcome ---
private struct WelcomeIllustration: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)
        }
        // Endlosschleife nur ohne „Bewegung reduzieren“
        .onAppear { wave = !reduceMotion }
    }
}

// --- Notification ---
private struct NotificationIllustration: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var show = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 60, weight: .light))
                .foregroundStyle(color)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: !reduceMotion)

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
            .opacity(show ? 1 : 0)
            // Ohne Bewegung: nur einblenden statt hereinschieben
            .offset(y: show || reduceMotion ? 0 : 30)
            .animation(reduceMotion ? .easeIn(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.7).delay(0.4), value: show)
        }
        .padding(.horizontal, 24)
        .onAppear { show = true }
    }
}

#Preview {
    TutorialView(onFinish: {})
}
