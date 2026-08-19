import AVFoundation
import BikeGoGoCore
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum RideShareTemplate: String, CaseIterable, Identifiable {
    case compact
    case stats
    case fitness
    case performance
    case milestone

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: "简洁"
        case .stats: "数据"
        case .fitness: "体能"
        case .performance: "表现"
        case .milestone: "里程"
        }
    }
}

struct ImportedRideVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let extensionName = received.file.pathExtension.isEmpty
                ? "mov"
                : received.file.pathExtension
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("bikegogo-selected-\(UUID().uuidString)")
                .appendingPathExtension(extensionName)
            try FileManager.default.copyItem(at: received.file, to: destination)
            return ImportedRideVideo(url: destination)
        }
    }
}

enum RideShareExportError: LocalizedError {
    case imageRenderingFailed
    case videoCompositionFailed
    case videoExportFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageRenderingFailed:
            "无法生成分享图片，请更换照片后重试。"
        case .videoCompositionFailed:
            "无法读取这个视频，请更换视频后重试。"
        case let .videoExportFailed(message):
            "视频生成失败：\(message)"
        }
    }
}

@MainActor
enum RideShareMediaExporter {
    static func exportPhoto(
        _ photo: UIImage,
        ride: RideSession,
        template: RideShareTemplate,
        showsRoute: Bool
    ) throws -> URL {
        let sourceSize = CGSize(
            width: max(photo.size.width * photo.scale, 1),
            height: max(photo.size.height * photo.scale, 1)
        )
        let reduction = min(1, 4_096 / max(sourceSize.width, sourceSize.height))
        let targetSize = CGSize(
            width: (sourceSize.width * reduction).rounded(),
            height: (sourceSize.height * reduction).rounded()
        )
        guard let overlay = overlayImage(
            ride: ride,
            template: template,
            showsRoute: showsRoute,
            targetSize: targetSize
        ) else {
            throw RideShareExportError.imageRenderingFailed
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let result = renderer.image { _ in
            photo.draw(in: CGRect(origin: .zero, size: targetSize))
            overlay.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let data = result.jpegData(compressionQuality: 0.94) else {
            throw RideShareExportError.imageRenderingFailed
        }
        let url = outputURL(fileExtension: "jpg")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func exportVideo(
        at sourceURL: URL,
        ride: RideSession,
        template: RideShareTemplate,
        showsRoute: Bool
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let videoComposition = AVMutableVideoComposition(propertiesOf: asset)
        let renderSize = videoComposition.renderSize
        guard renderSize.width > 0,
              renderSize.height > 0,
              let overlay = overlayImage(
                  ride: ride,
                  template: template,
                  showsRoute: showsRoute,
                  targetSize: renderSize
              ) else {
            throw RideShareExportError.videoCompositionFailed
        }

        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: renderSize)

        let overlayLayer = CALayer()
        overlayLayer.frame = CGRect(origin: .zero, size: renderSize)
        overlayLayer.contents = overlay.cgImage
        overlayLayer.contentsGravity = .resize
        overlayLayer.masksToBounds = true

        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(overlayLayer)
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        guard let exporter = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RideShareExportError.videoCompositionFailed
        }

        let outputFileType: AVFileType = exporter.supportedFileTypes.contains(.mp4)
            ? .mp4
            : .mov
        let outputURL = outputURL(
            fileExtension: outputFileType == .mp4 ? "mp4" : "mov"
        )
        exporter.outputURL = outputURL
        exporter.outputFileType = outputFileType
        exporter.shouldOptimizeForNetworkUse = true
        exporter.videoComposition = videoComposition

        await withCheckedContinuation { continuation in
            exporter.exportAsynchronously {
                continuation.resume()
            }
        }

        guard exporter.status == .completed else {
            throw RideShareExportError.videoExportFailed(
                exporter.error?.localizedDescription ?? "未知错误"
            )
        }
        return outputURL
    }

    private static func overlayImage(
        ride: RideSession,
        template: RideShareTemplate,
        showsRoute: Bool,
        targetSize: CGSize
    ) -> UIImage? {
        let logicalWidth: CGFloat = 390
        let scale = targetSize.width / logicalWidth
        let logicalSize = CGSize(
            width: logicalWidth,
            height: targetSize.height / max(scale, 0.01)
        )
        let renderer = ImageRenderer(
            content: RideShareDataOverlay(
                ride: ride,
                template: template,
                showsRoute: showsRoute
            )
                .frame(width: logicalSize.width, height: logicalSize.height)
        )
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.uiImage
    }

    private static func outputURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BikeGoGo-Share-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }
}

struct RideShareDataOverlay: View {
    let ride: RideSession
    let template: RideShareTemplate
    var showsRoute = true

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.08), .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if showsRoute, ride.points.count > 1 {
                    VStack {
                        HStack {
                            Spacer()
                            RideShareRouteBadge(points: ride.points)
                                .frame(
                                    width: width * 0.44,
                                    height: width * 0.34
                                )
                        }
                        Spacer()
                    }
                    .padding(.top, width * 0.055)
                    .padding(.horizontal, width * 0.055)
                }

                VStack(alignment: .leading, spacing: width * 0.025) {
                    brandRow(width: width)
                    weatherRow(width: width)
                    templateContent(width: width)
                }
                .padding(.horizontal, width * 0.055)
                .padding(.bottom, width * 0.06)
            }
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }

    private func brandRow(width: CGFloat) -> some View {
        HStack(spacing: width * 0.018) {
            Image(systemName: "bicycle")
            Text("BikeGoGo")
                .fontWeight(.bold)
            Spacer()
            Text(ChineseDateFormatting.date(ride.startedAt))
        }
        .font(.system(size: width * 0.035))
        .foregroundStyle(.white.opacity(0.9))
    }

    @ViewBuilder
    private func weatherRow(width: CGFloat) -> some View {
        if let weather = ride.weather {
            HStack(spacing: width * 0.025) {
                Label(
                    "\(Int(weather.temperatureCelsius.rounded()))° \(weather.conditionText)",
                    systemImage: weather.symbolName
                )
                if let humidity = weather.relativeHumidityPercent {
                    Label("\(Int(humidity.rounded()))%", systemImage: "humidity.fill")
                }
                if let windSpeed = weather.windSpeedKilometersPerHour {
                    Label(
                        String(format: "%.0f km/h", windSpeed),
                        systemImage: "wind"
                    )
                }
                Spacer(minLength: width * 0.01)
                Text("Apple Weather")
                    .foregroundStyle(.white.opacity(0.65))
            }
            .font(.system(size: width * 0.03, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .minimumScaleFactor(0.65)
        }
    }

    @ViewBuilder
    private func templateContent(width: CGFloat) -> some View {
        switch template {
        case .compact:
            HStack(alignment: .lastTextBaseline) {
                valueBlock(
                    title: "距离",
                    value: String(format: "%.2f", ride.metrics.distanceKilometers),
                    unit: "km",
                    width: width,
                    emphasized: true
                )
                Spacer()
                valueBlock(
                    title: "骑行时间",
                    value: durationText(ride.metrics.elapsedDurationSeconds),
                    unit: "",
                    width: width,
                    emphasized: false
                )
            }

        case .stats:
            Text(ride.title)
                .font(.system(size: width * 0.052, weight: .bold))
                .lineLimit(1)
            HStack(spacing: width * 0.04) {
                valueBlock(
                    title: "距离",
                    value: String(format: "%.2f", ride.metrics.distanceKilometers),
                    unit: "km",
                    width: width,
                    emphasized: true
                )
                valueBlock(
                    title: "均速",
                    value: String(format: "%.1f", ride.metrics.averageSpeedKilometersPerHour),
                    unit: "km/h",
                    width: width,
                    emphasized: false
                )
                valueBlock(
                    title: "爬升",
                    value: String(format: "%.0f", ride.metrics.elevationGainMeters),
                    unit: "m",
                    width: width,
                    emphasized: false
                )
            }
            HStack(spacing: width * 0.025) {
                Label(durationText(ride.metrics.elapsedDurationSeconds), systemImage: "clock")
                if let heartRate = ride.metrics.averageHeartRate {
                    Label("\(heartRate) bpm", systemImage: "heart.fill")
                }
            }
            .font(.system(size: width * 0.035, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))

        case .fitness:
            Text("体能训练")
                .font(.system(size: width * 0.052, weight: .bold))
            HStack(spacing: width * 0.04) {
                valueBlock(
                    title: "动态热量",
                    value: optionalNumber(ride.metrics.activeEnergyKilocalories, format: "%.0f"),
                    unit: "kcal",
                    width: width,
                    emphasized: true
                )
                valueBlock(
                    title: "平均心率",
                    value: ride.metrics.averageHeartRate.map(String.init) ?? "--",
                    unit: "bpm",
                    width: width,
                    emphasized: false
                )
                valueBlock(
                    title: "最高心率",
                    value: ride.metrics.maxHeartRate.map(String.init) ?? "--",
                    unit: "bpm",
                    width: width,
                    emphasized: false
                )
            }
            HStack(spacing: width * 0.025) {
                Label(durationText(ride.metrics.movingDurationSeconds), systemImage: "figure.outdoor.cycle")
                if let totalEnergy = ride.metrics.totalEnergyKilocalories {
                    Label(String(format: "%.0f kcal 总消耗", totalEnergy), systemImage: "flame.fill")
                }
                Label(String(format: "%.0f m", ride.metrics.elevationGainMeters), systemImage: "mountain.2.fill")
            }
            .font(.system(size: width * 0.032, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.7)

        case .performance:
            Text("骑行表现")
                .font(.system(size: width * 0.052, weight: .bold))
            HStack(spacing: width * 0.04) {
                valueBlock(
                    title: "平均速度",
                    value: String(format: "%.1f", ride.metrics.averageSpeedKilometersPerHour),
                    unit: "km/h",
                    width: width,
                    emphasized: true
                )
                valueBlock(
                    title: "最高速度",
                    value: String(format: "%.1f", ride.metrics.maxSpeedKilometersPerHour),
                    unit: "km/h",
                    width: width,
                    emphasized: false
                )
                valueBlock(
                    title: "累计爬升",
                    value: String(format: "%.0f", ride.metrics.elevationGainMeters),
                    unit: "m",
                    width: width,
                    emphasized: false
                )
            }
            HStack(spacing: width * 0.025) {
                Label(String(format: "%.2f km", ride.metrics.distanceKilometers), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                if let cadence = ride.metrics.averageCadenceRPM {
                    Label(String(format: "%.0f rpm", cadence), systemImage: "repeat")
                }
                if let power = ride.metrics.averageCyclingPowerWatts {
                    Label(String(format: "%.0f W", power), systemImage: "bolt.fill")
                }
            }
            .font(.system(size: width * 0.032, weight: .semibold))
            .foregroundStyle(.white.opacity(0.88))
            .lineLimit(1)
            .minimumScaleFactor(0.7)

        case .milestone:
            Text("本次骑行")
                .font(.system(size: width * 0.045, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            HStack(alignment: .lastTextBaseline, spacing: width * 0.018) {
                Text(String(format: "%.2f", ride.metrics.distanceKilometers))
                    .font(.system(size: width * 0.19, weight: .black))
                    .monospacedDigit()
                Text("km")
                    .font(.system(size: width * 0.055, weight: .bold))
            }
            Text("\(durationText(ride.metrics.elapsedDurationSeconds))  ·  均速 \(String(format: "%.1f", ride.metrics.averageSpeedKilometersPerHour)) km/h")
                .font(.system(size: width * 0.038, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private func valueBlock(
        title: String,
        value: String,
        unit: String,
        width: CGFloat,
        emphasized: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: width * 0.006) {
            Text(title)
                .font(.system(size: width * 0.03, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
            HStack(alignment: .lastTextBaseline, spacing: width * 0.009) {
                Text(value)
                    .font(.system(
                        size: width * (emphasized ? 0.105 : 0.065),
                        weight: emphasized ? .black : .bold
                    ))
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: width * 0.03, weight: .semibold))
                }
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func optionalNumber(_ value: Double?, format: String) -> String {
        guard let value else { return "--" }
        return String(format: format, value)
    }
}

private struct RideShareRouteBadge: View {
    let points: [RidePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("骑行轨迹", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))

            Canvas { context, size in
                let route = normalizedRoute(in: size)
                guard route.count > 1 else { return }

                var path = Path()
                path.move(to: route[0])
                for point in route.dropFirst() {
                    path.addLine(to: point)
                }
                context.stroke(
                    path,
                    with: .color(Color(red: 0.20, green: 0.90, blue: 0.48)),
                    style: StrokeStyle(
                        lineWidth: max(size.width * 0.025, 2),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                let markerSize = max(size.width * 0.075, 6)
                context.fill(
                    Path(ellipseIn: markerRect(at: route[0], size: markerSize)),
                    with: .color(Color(red: 0.20, green: 0.90, blue: 0.48))
                )
                if let cyclist = context.resolveSymbol(id: "cyclist") {
                    context.draw(cyclist, at: route[route.count - 1], anchor: .center)
                }
            } symbols: {
                ShareCyclistMarker()
                    .tag("cyclist")
            }
        }
        .padding(10)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
    }

    private func normalizedRoute(in size: CGSize) -> [CGPoint] {
        let validPoints = sampledPoints.filter {
            $0.latitude.isFinite
                && $0.longitude.isFinite
                && (-90...90).contains($0.latitude)
                && (-180...180).contains($0.longitude)
        }
        guard validPoints.count > 1 else { return [] }

        let meanLatitude = validPoints.map(\.latitude).reduce(0, +)
            / Double(validPoints.count)
        let longitudeScale = max(cos(meanLatitude * .pi / 180), 0.01)
        let projected = validPoints.map {
            CGPoint(
                x: $0.longitude * longitudeScale,
                y: -$0.latitude
            )
        }

        let minX = projected.map(\.x).min() ?? 0
        let maxX = projected.map(\.x).max() ?? 0
        let minY = projected.map(\.y).min() ?? 0
        let maxY = projected.map(\.y).max() ?? 0
        let routeWidth = max(maxX - minX, 0.000_001)
        let routeHeight = max(maxY - minY, 0.000_001)
        let inset = max(size.width * 0.07, 4)
        let drawingSize = CGSize(
            width: max(size.width - inset * 2, 1),
            height: max(size.height - inset * 2, 1)
        )
        let scale = min(
            drawingSize.width / routeWidth,
            drawingSize.height / routeHeight
        )
        let renderedWidth = routeWidth * scale
        let renderedHeight = routeHeight * scale
        let origin = CGPoint(
            x: (size.width - renderedWidth) / 2,
            y: (size.height - renderedHeight) / 2
        )

        return projected.map {
            CGPoint(
                x: origin.x + ($0.x - minX) * scale,
                y: origin.y + ($0.y - minY) * scale
            )
        }
    }

    private var sampledPoints: [RidePoint] {
        guard points.count > 500 else { return points }
        let step = max(points.count / 500, 1)
        var sampled = points.enumerated().compactMap { index, point in
            index.isMultiple(of: step) ? point : nil
        }
        if sampled.last != points.last, let last = points.last {
            sampled.append(last)
        }
        return sampled
    }

    private func markerRect(at point: CGPoint, size: CGFloat) -> CGRect {
        CGRect(
            x: point.x - size / 2,
            y: point.y - size / 2,
            width: size,
            height: size
        )
    }
}

private struct ShareCyclistMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.05, green: 0.45, blue: 0.40))
            Circle()
                .stroke(.white, lineWidth: 2)
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}
