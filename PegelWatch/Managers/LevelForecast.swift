import Foundation

/// Simple linear-regression forecast for water levels.
///
/// The German water agencies publish measurements in ~15-minute intervals.
/// A regression over the last 6h gives a stable slope while still reacting to
/// recent changes — long enough to smooth noise, short enough to detect
/// approaching flood peaks.
///
/// The result should be treated as a rough indicator, not a hydrological model.
enum LevelForecast {

    /// Result of a regression-based short-term forecast.
    struct Result {
        /// Estimated slope in cm/hour (positive = rising).
        let slopePerHour: Double
        /// Coefficient of determination (0…1) — how well the line fits.
        let rSquared: Double
        /// Predicted values for the next N hours after the last sample.
        let projected: [(timestamp: Date, value: Double)]
        /// Confidence band (± cm) that grows with distance from the fit window
        /// and shrinks with a better R².
        let confidence: [(timestamp: Date, upper: Double, lower: Double)]

        /// Projected value in `hoursAhead` hours (relative to last sample),
        /// or nil if the forecast is empty.
        func value(hoursAhead: Double) -> Double? {
            guard let last = projected.last, let first = projected.first else { return nil }
            let span = last.timestamp.timeIntervalSince(first.timestamp) / 3600.0
            guard span > 0 else { return first.value }
            let t = min(max(hoursAhead / span, 0), 1)
            let idx = Int(Double(projected.count - 1) * t)
            return projected[idx].value
        }
    }

    /// Fits a line to the last `windowHours` of history and projects
    /// `forecastHours` into the future in ~10-minute steps.
    ///
    /// Returns `nil` if there is not enough data (< 4 points in the window).
    static func forecast(
        history: [(timestamp: Date, value: Double)],
        windowHours: Double = 6,
        forecastHours: Double = 3
    ) -> Result? {
        guard let last = history.last else { return nil }

        let cutoff = last.timestamp.addingTimeInterval(-windowHours * 3600)
        let window = history.filter { $0.timestamp >= cutoff }
        guard window.count >= 4 else { return nil }

        let t0 = window.first!.timestamp
        let xs = window.map { $0.timestamp.timeIntervalSince(t0) / 3600.0 } // hours
        let ys = window.map(\.value)
        let n = Double(window.count)

        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var num = 0.0
        var denX = 0.0
        var denY = 0.0
        for i in 0..<window.count {
            let dx = xs[i] - meanX
            let dy = ys[i] - meanY
            num  += dx * dy
            denX += dx * dx
            denY += dy * dy
        }

        guard denX > 0 else { return nil }
        let slope = num / denX
        let intercept = meanY - slope * meanX

        // R² = 1 - SS_res / SS_tot
        var ssRes = 0.0
        for i in 0..<window.count {
            let predicted = intercept + slope * xs[i]
            ssRes += (ys[i] - predicted) * (ys[i] - predicted)
        }
        let rSquared = denY > 0 ? max(0, 1 - ssRes / denY) : 0
        let stdErr = window.count > 2 ? sqrt(ssRes / Double(window.count - 2)) : 0

        // Project forward from last sample.
        let lastX = last.timestamp.timeIntervalSince(t0) / 3600.0
        let stepMinutes = 10.0
        let steps = Int((forecastHours * 60.0) / stepMinutes)

        var projected: [(timestamp: Date, value: Double)] = []
        var confidence: [(timestamp: Date, upper: Double, lower: Double)] = []
        projected.reserveCapacity(steps + 1)
        confidence.reserveCapacity(steps + 1)

        for step in 0...steps {
            let deltaHours = Double(step) * stepMinutes / 60.0
            let x = lastX + deltaHours
            let value = intercept + slope * x
            let ts = last.timestamp.addingTimeInterval(deltaHours * 3600)
            projected.append((ts, value))
            // Cone widens ~1.96*stdErr at 1h, quadratic growth as we go further.
            let widening = 1.96 * stdErr * (1 + deltaHours * 0.5)
            confidence.append((ts, value + widening, value - widening))
        }

        return Result(
            slopePerHour: slope,
            rSquared: rSquared,
            projected: projected,
            confidence: confidence
        )
    }
}
