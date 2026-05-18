import SwiftUI

struct JournalImageGallery: View {
    enum Layout {
        case detail
        case row
        case preview
    }

    let images: [Data]
    var layout: Layout = .detail
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue

    private var resolvedImages: [UIImage] {
        images.compactMap(UIImage.init(data:))
    }

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: appLanguageRawValue) ?? .system).resolvedLanguage)
    }

    @ViewBuilder
    var body: some View {
        if !resolvedImages.isEmpty {
            switch layout {
            case .detail:
                detailGallery
            case .row:
                rowGallery
            case .preview:
                previewGallery
            }
        }
    }

    @ViewBuilder
    private var detailGallery: some View {
        if resolvedImages.count == 1, let image = resolvedImages.first {
            imageCard(image, height: 248, cornerRadius: 26)
        } else {
            carousel(height: 256, cornerRadius: 26)
        }
    }

    @ViewBuilder
    private var previewGallery: some View {
        if resolvedImages.count == 1, let image = resolvedImages.first {
            imageCard(image, height: 220, cornerRadius: 22)
        } else {
            carousel(height: 228, cornerRadius: 22)
        }
    }

    @ViewBuilder
    private var rowGallery: some View {
        if let image = resolvedImages.first {
            ZStack(alignment: .topTrailing) {
                imageCard(image, height: 156, cornerRadius: 22)

                if resolvedImages.count > 1 {
                    imageCountBadge
                        .padding(12)
                }
            }
        }
    }

    private func carousel(height: CGFloat, cornerRadius: CGFloat) -> some View {
        TabView {
            ForEach(Array(resolvedImages.enumerated()), id: \.offset) { _, image in
                imageCard(image, height: height, cornerRadius: cornerRadius)
                    .padding(.horizontal, 2)
            }
        }
        .frame(height: height)
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .overlay(alignment: .topTrailing) {
            imageCountBadge
                .padding(14)
        }
    }

    private func imageCard(_ image: UIImage, height: CGFloat, cornerRadius: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
            .accessibilityHidden(true)
    }

    private var imageCountBadge: some View {
        Text(text.imageCountLabel(count: resolvedImages.count))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
    }
}
