import SwiftUI
import SwiftData

struct JournalListView: View {
    @Query(sort: \JournalEntry.date, order: .reverse)
    private var entries: [JournalEntry]
    @AppStorage(JournalTypographyStyle.storageKey)
    private var journalTypographyRawValue = JournalTypographyStyle.defaultStyle.rawValue
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue

    @State private var flashbackEntry: JournalEntry?
    @State private var unreadRefreshToken = 0
    private let minimumFlashbackEntries = 30
    private let flashbackDisplayChance = 4

    private var journalTypography: JournalTypographyStyle {
        JournalTypographyStyle.from(rawValue: journalTypographyRawValue)
    }

    private var text: AppText {
        let mode = AppLanguageMode(rawValue: appLanguageRawValue) ?? .system
        return AppText(language: mode.resolvedLanguage)
    }

    private enum Layout {
        static let contentHorizontalPadding: CGFloat = 16
        static let cardPadding: CGFloat = 14
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        text.noJournalsTitle,
                        systemImage: "book.closed",
                        description: Text(text.noJournalsDescription)
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let flashback = flashbackEntry {
                                NavigationLink(destination: JournalDetailView(entry: flashback)) {
                                    FlashbackCard(
                                        entry: flashback,
                                        typography: journalTypography,
                                        contentPadding: Layout.cardPadding
                                    )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }

                            Text(text.allJournals)
                                .font(.headline)
                                .foregroundStyle(QuietNativeTheme.primaryText)

                            ForEach(entries) { entry in
                                NavigationLink(destination: JournalDetailView(entry: entry)) {
                                    JournalRowView(
                                        entry: entry,
                                        typography: journalTypography,
                                        isUnread: JournalUnreadStore.isUnread(entry.id),
                                        contentPadding: Layout.cardPadding
                                    )
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("journal.entryRow")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Layout.contentHorizontalPadding)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                    .quietNativeTabBarClearance()
                    .scrollIndicators(.hidden)
                }
            }
            .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
            .navigationTitle(text.journalTab)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    JournalTypographyMenu()
                }
            }
            .onAppear {
                pickFlashback()
            }
            .onReceive(NotificationCenter.default.publisher(for: .journalUnreadStateDidChange)) { _ in
                unreadRefreshToken &+= 1
            }
        }
    }

    private func pickFlashback() {
        guard entries.count >= minimumFlashbackEntries else {
            flashbackEntry = nil
            return
        }

        guard Int.random(in: 0..<flashbackDisplayChance) == 0 else {
            flashbackEntry = nil
            return
        }

        let pastEntries = entries.filter {
            !DayBoundary.isAppToday($0.date)
        }
        flashbackEntry = pastEntries.randomElement()
    }
}

private struct FlashbackCard: View {
    let entry: JournalEntry
    let typography: JournalTypographyStyle
    let contentPadding: CGFloat
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        let mode = AppLanguageMode(rawValue: appLanguageRawValue) ?? .system
        return AppText(language: mode.resolvedLanguage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let images = entry.imageDataList, !images.isEmpty {
                JournalImageGallery(images: images, layout: .row)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(QuietNativeTheme.accent)
                Text(text.flashback)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuietNativeTheme.accent)
            }

            Text(entry.formattedDate)
                .font(.caption)
                .foregroundStyle(QuietNativeTheme.secondaryText)

            Text(entry.title)
                .font(.title3.weight(.semibold))
                .journalTypography(typography)
                .foregroundStyle(QuietNativeTheme.primaryText)

            Text(entry.summaryText)
                .font(.subheadline)
                .journalTypography(typography)
                .foregroundStyle(QuietNativeTheme.secondaryText)
                .lineLimit(2)
                .lineSpacing(typography.summaryLineSpacing)

            HStack(spacing: 6) {
                ForEach(entry.normalizedEmotionTags.prefix(4), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption2)
                        .foregroundStyle(QuietNativeTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(QuietNativeTheme.accentSoft)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietNativeCard(cornerRadius: 24, fill: QuietNativeTheme.accentSoft)
    }
}

// MARK: - Journal Row

struct JournalRowView: View {
    let entry: JournalEntry
    let typography: JournalTypographyStyle
    var isUnread = false
    var contentPadding: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let images = entry.imageDataList, !images.isEmpty {
                JournalImageGallery(images: images, layout: .row)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(entry.formattedDate)
                        .font(.caption)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                    if isUnread {
                        UnreadDotView(size: 7)
                    }
                }

                Text(entry.title)
                    .font(.title3.weight(.semibold))
                    .journalTypography(typography)
                    .foregroundStyle(QuietNativeTheme.primaryText)

                Text(entry.summaryText)
                    .font(.subheadline)
                    .journalTypography(typography)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                    .lineLimit(3)
                    .lineSpacing(typography.summaryLineSpacing)
            }

            HStack(spacing: 6) {
                ForEach(entry.normalizedEmotionTags.prefix(4), id: \.self) { tag in
                    Text("#\(tag)")
                        .font(.caption2)
                        .foregroundStyle(QuietNativeTheme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(QuietNativeTheme.accentSoft)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(contentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .quietNativeCard(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("journal.entryRow")
    }
}
