import SwiftUI
import SDWebImage
import SDWebImageSwiftUI
import ImageViewer_swift
import SPIndicator

struct SongInfo: View {
    let title: String
    let artists: [String]
    let thumbnailURL: String?
    let thumbnailIsSquare: Bool?
    let thumbnailForceSquare: Bool
    let thumbnailHasContextMenu: Bool

    init(
        title: String,
        artists: [String],
        thumbnailURL: String?,
        thumbnailIsSquare: Bool?,
        thumbnailForceSquare: Bool = true,
        thumbnailHasContextMenu: Bool = false
    ) {
        self.title = title
        self.artists = artists
        self.thumbnailURL = thumbnailURL
        self.thumbnailIsSquare = thumbnailIsSquare
        self.thumbnailForceSquare = thumbnailForceSquare
        self.thumbnailHasContextMenu = thumbnailHasContextMenu
    }

    var body: some View {
        VStack(spacing: 16) {
            SongImage(
                width: 180,
                height: 180,
                isLarge: true,

                thumbnailURL: thumbnailURL,
                thumbnailIsSquare: thumbnailIsSquare,
                thumbnailForceSquare: thumbnailForceSquare,
                tappableForViewer: thumbnailHasContextMenu
            )
            .contextMenu(
                thumbnailHasContextMenu
                    ? ContextMenu {
                        SaveCoverToPhotosButton(url: self.thumbnailURL.flatMap { URL(string: $0) })
                      }
                    : nil
            )
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(Color("PrimaryText"))
                    .multilineTextAlignment(.center)
                
                Text(formatArtists(artists))
                    .font(.subheadline)
                    .foregroundColor(Color("PrimaryText").opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
    }
}

struct SongImage: View {
    let width: CGFloat
    let height: CGFloat
    var isLarge: Bool = false
    
    let thumbnailURL: String?
    let thumbnailIsSquare: Bool?
    var preloadedImage: UIImage? = nil
    var thumbnailForceSquare: Bool = true
    var tappableForViewer: Bool = false

    private var squareSide: CGFloat { min(width, height) }
    private var cornerRadiusValue: CGFloat { isLarge ? 12 : 8 }
    private var shouldCropToSquare: Bool { thumbnailForceSquare || thumbnailIsSquare == false }
    private var frameWidth: CGFloat { shouldCropToSquare ? squareSide : width }
    private var frameHeight: CGFloat { shouldCropToSquare ? squareSide : height }

    var body: some View {
        if let thumbnailUrl = thumbnailURL, thumbnailIsSquare != nil {
            if let image = preloadedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: frameWidth, height: frameHeight)
                    .clipped()
                    .cornerRadius(cornerRadiusValue)
                    .shadow(color: .black.opacity(isLarge ? 0.15 : 0), radius: 6, x: 0, y: 2)
            } else if tappableForViewer {
                TappableImageView(
                    url: URL(string: thumbnailUrl),
                    thumbnailIsSquare: thumbnailIsSquare,
                    cornerRadius: cornerRadiusValue
                )
                    .frame(width: frameWidth, height: frameHeight)
                    .shadow(color: .black.opacity(isLarge ? 0.15 : 0), radius: 6, x: 0, y: 2)
            } else {
                WebImage(url: URL(string: thumbnailUrl)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: frameWidth, height: frameHeight)
                .clipped()
                .cornerRadius(cornerRadiusValue)
                .shadow(color: .black.opacity(isLarge ? 0.15 : 0), radius: 6, x: 0, y: 2)
            }
        } else {
            ZStack {
                Color.gray.opacity(0.2)
                Image(systemName: "music.note")
                    .foregroundColor(.secondary)
                    .font(.system(size: min(width, height) * 0.5))
            }
            .frame(width: frameWidth, height: frameHeight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct SaveCoverToPhotosButton: View {
    let url: URL?
        
    var body: some View {
        Button {            
            guard let url = url else {
                return
            }
            
            SDWebImageManager.shared.loadImage(with: url, options: [.highPriority, .retryFailed, .scaleDownLargeImages], progress: nil) { image, _, error, _, finished, _ in
                guard error == nil, finished, let image else {
                    SPIndicatorView(title: "Failed to save image", message: error?.localizedDescription ?? "Failed to load image", preset: .error).present()
                    return
                }
                
                let saver = ImageSaver()
                saver.onSuccess = {
                    SPIndicatorView(title: "Image Saved", preset: .done).present()
                }
                saver.onError = { error in
                    SPIndicatorView(title: "Failed to save image", message: error.localizedDescription, preset: .error).present()
                }
                saver.save(image)
            }

        } label: {
            Label("Save Cover to Photos", systemImage: "photo.badge.arrow.down")
        }
    }
}

// So we can use ImageViewer.swift with SwiftUI
struct TappableImageView: UIViewRepresentable {
    let url: URL?
    let thumbnailIsSquare: Bool?
    var cornerRadius: CGFloat = 12

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.clipsToBounds = true
        container.layer.cornerRadius = cornerRadius
        
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = true
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.frame = container.bounds
        container.addSubview(imageView)
        
        if let url = url {
            if thumbnailIsSquare == false {
                SDWebImageManager.shared.loadImage(with: url, options: [.highPriority, .retryFailed, .scaleDownLargeImages], progress: nil) { image, _, error, _, finished, _ in
                    guard error == nil, finished, let image else {
                        imageView.sd_setImage(with: url)
                        imageView.setupImageViewer(url: url, options: [.theme(.dark)])
                        return
                    }
                    let cropped = image.croppedToSquare()
                    imageView.image = cropped
                    imageView.setupImageViewer(images: [cropped], options: [.theme(.dark)])
                }
            } else {
                imageView.sd_setImage(with: url)
                imageView.setupImageViewer(url: url, options: [.theme(.dark)])
            }
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
