import SwiftUI

// MARK: - Sheet container

struct SectorSnapshotView: View {
    let stations: [WatchedStation]
    private let generatedAt = Date()

    @State private var pdfURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView {
                SnapshotPageView(stations: sortedStations, generatedAt: generatedAt)
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Lageübersicht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if let url = pdfURL {
                        ShareLink(
                            item: url,
                            preview: SharePreview(
                                "PegelWatch-Lageübersicht.pdf",
                                image: Image(systemName: "doc.text.fill")
                            )
                        ) {
                            Label("Teilen", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .task { await buildPDF() }
        }
    }

    private var sortedStations: [WatchedStation] {
        let order: [AlarmLevel] = [.critical, .danger, .warning, .normal]
        return stations.sorted { a, b in
            let ai = order.firstIndex(of: a.alarmLevel) ?? order.count
            let bi = order.firstIndex(of: b.alarmLevel) ?? order.count
            if ai != bi { return ai < bi }
            return a.shortname < b.shortname
        }
    }

    @MainActor
    private func buildPDF() async {
        let content = SnapshotPageView(stations: sortedStations, generatedAt: generatedAt)
            .padding(20)
            .environment(\.colorScheme, .light)
            .frame(width: 595)

        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PegelWatch-Lageübersicht.pdf")

        renderer.render { size, draw in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }

        pdfURL = url
    }
}

// MARK: - Page layout (used for both sheet preview and PDF render)

private struct SnapshotPageView: View {
    let stations: [WatchedStation]
    let generatedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            Rectangle()
                .fill(Color.black)
                .frame(height: 1.5)
                .padding(.vertical, 14)

            if stations.isEmpty {
                Text("Keine Stationen in der Beobachtungsliste.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                stationTable
            }

            Spacer(minLength: 20)

            Rectangle()
                .fill(Color.gray.opacity(0.35))
                .frame(height: 0.5)
                .padding(.bottom, 8)

            footerSection
        }
        .foregroundColor(.black)
        .background(Color.white)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("PegelWatch")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text("Stand: \(generatedAt.formatted(date: .numeric, time: .shortened))")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            Text("Lageübersicht · \(stations.count) Station\(stations.count == 1 ? "" : "en")")
                .font(.system(size: 13))
                .foregroundColor(.gray)
        }
    }

    private var stationTable: some View {
        VStack(spacing: 0) {
            columnHeaders
            ForEach(Array(stations.enumerated()), id: \.element.id) { index, station in
                SnapshotStationRow(station: station)
                    .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.04))
                if index < stations.count - 1 {
                    Divider().background(Color.gray.opacity(0.2))
                }
            }
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            Text("Station")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Pegel")
                .frame(width: 72, alignment: .trailing)
            Text("Trend")
                .frame(width: 38, alignment: .center)
            Text("Alarmstufe")
                .frame(width: 82, alignment: .trailing)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.gray)
        .padding(.bottom, 6)
    }

    private var footerSection: some View {
        HStack {
            Text("Daten: pegelonline.wsv.de · heichwaasser.lu")
                .font(.system(size: 9))
                .foregroundColor(.gray)
            Spacer()
            Text("Erzeugt mit PegelWatch")
                .font(.system(size: 9))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Station row

private struct SnapshotStationRow: View {
    let station: WatchedStation

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                Text(station.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(station.waterDisplayName)
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            levelText
                .frame(width: 72, alignment: .trailing)

            trendView
                .frame(width: 38, alignment: .center)

            Text(station.noDataAvailable ? "Keine Daten" : station.alarmLevel.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(dotColor)
                .frame(width: 82, alignment: .trailing)
        }
        .padding(.vertical, 7)
        .foregroundColor(.black)
    }

    // Explicit colors so amber is legible on white (system yellow is not)
    private var dotColor: Color {
        guard !station.noDataAvailable else { return .gray }
        switch station.alarmLevel {
        case .normal:   return Color(red: 0.13, green: 0.69, blue: 0.30)
        case .warning:  return Color(red: 0.80, green: 0.55, blue: 0.00)
        case .danger:   return Color(red: 0.90, green: 0.35, blue: 0.00)
        case .critical: return Color(red: 0.85, green: 0.10, blue: 0.10)
        }
    }

    @ViewBuilder
    private var levelText: some View {
        if station.noDataAvailable {
            Text("—").font(.system(size: 12)).foregroundColor(.gray)
        } else if let value = station.lastValue {
            Text("\(Int(value)) cm")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        } else {
            Text("—").font(.system(size: 12)).foregroundColor(.gray)
        }
    }

    @ViewBuilder
    private var trendView: some View {
        if let trend = station.trend {
            if trend > 0.5 {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.85, green: 0.10, blue: 0.10))
            } else if trend < -0.5 {
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.13, green: 0.69, blue: 0.30))
            } else {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.gray)
            }
        } else {
            Text("—").font(.system(size: 11)).foregroundColor(.gray)
        }
    }
}

// MARK: - Preview

#Preview {
    SectorSnapshotView(stations: [.preview, .previewAlarming, .previewNoData])
}
