import AVFoundation
import AVKit
import BikeGoGoCore
import PhotosUI
import SwiftUI
import UIKit

struct RideShareComposerView: View {
    let ride: RideSession

    @State private var selectedItem: PhotosPickerItem?
    @State private var media: RideShareMedia?
    @State private var player: AVPlayer?
    @State private var template: RideShareTemplate = .stats
    @State private var showsRoute = true
    @State private var isLoadingMedia = false
    @State private var isExporting = false
    @State private var output: RideShareOutput?
    @State private var errorMessage: String?
    @State private var loadID = UUID()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                mediaPreview

                Picker("数据样式", selection: $template) {
                    ForEach(RideShareTemplate.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)

                Toggle(isOn: $showsRoute) {
                    Label("显示骑行轨迹", systemImage: "map")
                }
                .disabled(ride.points.count < 2)

                HStack(spacing: 12) {
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label(
                            media == nil ? "选择素材" : "更换素材",
                            systemImage: "photo.on.rectangle.angled"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await export() }
                    } label: {
                        if isExporting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label("生成分享", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0, green: 0.42, blue: 0.36))
                    .disabled(media == nil || isLoadingMedia || isExporting)
                }
            }
            .padding(16)
        }
        .navigationTitle("分享骑行")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .onChange(of: selectedItem) { _, item in
            Task { await load(item) }
        }
        .onDisappear {
            player?.pause()
        }
        .sheet(item: $output) { result in
            RideShareActivityView(activityItems: [result.url])
        }
        .alert(
            "无法生成分享作品",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private var mediaPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black)

            if let media {
                switch media {
                case let .photo(image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                case .video:
                    if let player {
                        VideoPlayer(player: player)
                            .onAppear {
                                player.isMuted = true
                                player.play()
                            }
                    }
                }

                RideShareDataOverlay(
                    ride: ride,
                    template: template,
                    showsRoute: showsRoute
                )
            } else {
                PhotosPicker(
                    selection: $selectedItem,
                    matching: .any(of: [.images, .videos])
                ) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.stack")
                            .font(.system(size: 38))
                        Text("选择照片或视频")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            if isLoadingMedia {
                ZStack {
                    Color.black.opacity(0.46)
                    ProgressView("正在读取素材")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
        }
        .aspectRatio(media?.aspectRatio ?? 4 / 5, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    @MainActor
    private func load(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        let requestID = UUID()
        loadID = requestID
        isLoadingMedia = true
        player?.pause()
        player = nil

        do {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .image) }),
               let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                guard loadID == requestID else { return }
                media = .photo(image)
            } else if let video = try await item.loadTransferable(type: ImportedRideVideo.self) {
                let size = try await orientedVideoSize(at: video.url)
                guard loadID == requestID else { return }
                media = .video(url: video.url, size: size)
                player = AVPlayer(url: video.url)
            } else {
                throw RideShareExportError.videoCompositionFailed
            }
        } catch {
            guard loadID == requestID else { return }
            media = nil
            errorMessage = "无法读取所选素材：\(error.localizedDescription)"
        }

        if loadID == requestID {
            isLoadingMedia = false
        }
    }

    @MainActor
    private func export() async {
        guard let media else { return }
        isExporting = true
        player?.pause()
        defer { isExporting = false }

        do {
            let url: URL
            switch media {
            case let .photo(image):
                url = try RideShareMediaExporter.exportPhoto(
                    image,
                    ride: ride,
                    template: template,
                    showsRoute: showsRoute
                )
            case let .video(sourceURL, _):
                url = try await RideShareMediaExporter.exportVideo(
                    at: sourceURL,
                    ride: ride,
                    template: template,
                    showsRoute: showsRoute
                )
            }
            output = RideShareOutput(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func orientedVideoSize(at url: URL) async throws -> CGSize {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RideShareExportError.videoCompositionFailed
        }
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformed = CGRect(origin: .zero, size: size)
            .applying(transform)
            .standardized
            .size
        guard transformed.width > 0, transformed.height > 0 else {
            throw RideShareExportError.videoCompositionFailed
        }
        return transformed
    }
}

private enum RideShareMedia {
    case photo(UIImage)
    case video(url: URL, size: CGSize)

    var aspectRatio: CGFloat {
        switch self {
        case let .photo(image):
            image.size.width / max(image.size.height, 1)
        case let .video(_, size):
            size.width / max(size.height, 1)
        }
    }
}

private struct RideShareOutput: Identifiable {
    let url: URL

    var id: String { url.path }
}

private struct RideShareActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}
