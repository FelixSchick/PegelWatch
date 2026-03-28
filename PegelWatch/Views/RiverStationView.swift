//
//  RiverStationView.swift
//  PegelWatch
//
//  Created by Felix Schick on 28.03.26.
//


import SwiftUI

struct RiverStationView: View {

    let stations: [Station]
    let isWatched: (String) -> Bool
    let onToggle: (Station) -> Void

    private let minSpacing: CGFloat = 64
    private let labelWidth: CGFloat = 110

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1/30)) { timeline in
                let phase = CGFloat(timeline.date.timeIntervalSinceReferenceDate * 18)
                let pts = resolvedPoints(in: geo.size)

                Canvas { ctx, size in
                    drawRiver(ctx: &ctx, pts: pts, phase: phase)
                    drawDots(ctx: &ctx, pts: pts)
                }
                .overlay {
                    GeometryReader { _ in
                        ForEach(Array(zip(stations, pts)), id: \.0.id) { station, pt in
                            stationLabel(station: station, at: pt, canvasWidth: geo.size.width)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 32)
    }

    // MARK: - Point layout with minimum spacing enforcement

    private func rawY(for station: Station, in size: CGSize) -> CGFloat {
        guard stations.count > 1,
              let km = station.km,
              let first = stations.first?.km,
              let last = stations.last?.km,
              last > first
        else { return size.height / 2 }

        let t = (km - first) / (last - first)
        return size.height * 0.04 + t * size.height * 0.92
    }

    private func resolvedPoints(in size: CGSize) -> [CGPoint] {
        guard !stations.isEmpty else { return [] }

        var ys: [CGFloat] = stations.map { rawY(for: $0, in: size) }

        for _ in 0..<10 {
            for i in 1..<ys.count {
                let gap = ys[i] - ys[i - 1]
                if gap < minSpacing {
                    let push = (minSpacing - gap) / 2
                    ys[i - 1] -= push
                    ys[i]     += push
                }
            }
        }

        return stations.enumerated().map { idx, station in
            let t = stations.count > 1
                ? CGFloat(idx) / CGFloat(stations.count - 1)
                : 0.5
            let x = size.width * 0.5 + sin(t * .pi * 2.2) * size.width * 0.22
            return CGPoint(x: x, y: ys[idx])
        }
    }

    // MARK: - Canvas

    private func drawRiver(ctx: inout GraphicsContext, pts: [CGPoint], phase: CGFloat) {
        guard pts.count >= 2 else { return }
        let path = smoothPath(through: pts)

        ctx.stroke(path, with: .color(.blue.opacity(0.07)),
                   style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(.blue.opacity(0.3)),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(.blue.opacity(0.5)),
                   style: StrokeStyle(lineWidth: 1, lineCap: .round,
                                      dash: [4, 6], dashPhase: -phase))
    }

    private func drawDots(ctx: inout GraphicsContext, pts: [CGPoint]) {
        for (idx, pt) in pts.enumerated() {
            let watched = isWatched(stations[idx].id)

            if watched {
                ctx.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)),
                    with: .color(.blue.opacity(0.9))
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)),
                    with: .color(.white)
                )
            } else {
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)),
                    with: .color(.blue.opacity(0.5)),
                    lineWidth: 1.5
                )
                ctx.fill(
                    Path(ellipseIn: CGRect(x: pt.x - 1.5, y: pt.y - 1.5, width: 3, height: 3)),
                    with: .color(.blue.opacity(0.4))
                )
            }
        }
    }

    private func smoothPath(through pts: [CGPoint]) -> Path {
        var path = Path()
        path.move(to: pts[0])
        for i in 0..<pts.count - 1 {
            let cur = pts[i], nxt = pts[i + 1]
            let mid = CGPoint(x: (cur.x + nxt.x) / 2, y: (cur.y + nxt.y) / 2)
            path.addQuadCurve(to: i == pts.count - 2 ? nxt : mid, control: cur)
        }
        return path
    }

    // MARK: - Label

    @ViewBuilder
    private func stationLabel(station: Station, at pt: CGPoint, canvasWidth: CGFloat) -> some View {
        let watched = isWatched(station.id)
        let onRight = pt.x < canvasWidth * 0.5

        Button {
            onToggle(station)
        } label: {
            HStack(spacing: 6) {
                if onRight {
                    tick
                    content(station: station, watched: watched, onRight: true)
                } else {
                    content(station: station, watched: watched, onRight: false)
                    tick
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .position(
            x: onRight
                ? pt.x + 14 + labelWidth / 2
                : pt.x - 14 - labelWidth / 2,
            y: pt.y
        )
    }

    @ViewBuilder
    private func content(station: Station, watched: Bool, onRight: Bool) -> some View {
        VStack(alignment: onRight ? .leading : .trailing, spacing: 1) {
            Text(station.shortname)
                .font(.caption.weight(watched ? .semibold : .regular))
                .foregroundStyle(watched ? .primary : .secondary)
                .animation(.easeInOut(duration: 0.2), value: watched)

            if let km = station.km {
                Text("km \(Int(km))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .frame(width: labelWidth, alignment: onRight ? .leading : .trailing)
    }

    private var tick: some View {
        Rectangle()
            .fill(.secondary.opacity(0.25))
            .frame(width: 10, height: 1)
    }
}
