import SwiftUI
import SwiftData

struct JournalDetailView: View {
    @Bindable var entry: JournalEntry
    @Environment(\.modelContext) private var modelContext
    @AppStorage(JournalTypographyStyle.storageKey)
    private var journalTypographyRawValue = JournalTypographyStyle.defaultStyle.rawValue
    @AppStorage(AppLanguageMode.storageKey)
    private var appLanguageRawValue = AppLanguageMode.system.rawValue
    @State private var isEditing = false
    @State private var editTitle: String = ""
    @State private var editBody: String = ""

    private var journalTypography: JournalTypographyStyle {
        JournalTypographyStyle.from(rawValue: journalTypographyRawValue)
    }

    private var text: AppText {
        let mode = AppLanguageMode(rawValue: appLanguageRawValue) ?? .system
        return AppText(language: mode.resolvedLanguage)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.formattedDate)
                        .font(.caption)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                        .tracking(1)

                    FlowLayout(spacing: 6) {
                        ForEach(entry.normalizedEmotionTags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption)
                                .foregroundStyle(QuietNativeTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(QuietNativeTheme.accentSoft)
                                .clipShape(Capsule())
                        }
                    }

                    Text(isEditing ? editTitle : entry.title)
                        .font(journalTypography.titleFont)
                        .journalTypography(journalTypography)
                        .foregroundStyle(QuietNativeTheme.primaryText)
                }
                .padding(20)
                .quietNativeCard(cornerRadius: 28)

                if let images = entry.imageDataList, !images.isEmpty {
                    JournalImageGallery(images: images, layout: .detail)
                }

                if isEditing {
                    VStack(alignment: .leading, spacing: 12) {
                        TextField(text.titlePlaceholder, text: $editTitle)
                            .font(.headline)
                            .journalTypography(journalTypography)
                            .textFieldStyle(.plain)
                            .foregroundStyle(QuietNativeTheme.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(QuietNativeTheme.backgroundWarm)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        TextEditor(text: $editBody)
                            .font(journalTypography.bodyFont)
                            .journalTypography(journalTypography)
                            .lineSpacing(journalTypography.bodyLineSpacing)
                            .frame(minHeight: 200)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(QuietNativeTheme.backgroundWarm)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(20)
                    .quietNativeCard(cornerRadius: 28)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(entry.fullDiaryText)
                            .font(journalTypography.bodyFont)
                            .journalTypography(journalTypography)
                            .foregroundStyle(QuietNativeTheme.primaryText)
                            .lineSpacing(journalTypography.bodyLineSpacing)
                            .tracking(journalTypography.bodyTracking)
                    }
                    .padding(20)
                    .quietNativeCard(cornerRadius: 28)
                }

                if !entry.tomorrowNote.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(text.isEnglish ? "\(text.buddyNoteTitle) \(text.buddyDefaultName)" : "バディからの一言", systemImage: "sparkles")
                            .font(.caption)
                            .foregroundStyle(QuietNativeTheme.accent)

                        Text(entry.tomorrowNote)
                            .font(journalTypography.noteFont)
                            .journalTypography(journalTypography)
                            .foregroundStyle(QuietNativeTheme.secondaryText)
                            .lineSpacing(6)
                    }
                    .padding(18)
                    .quietNativeCard(cornerRadius: 24, fill: QuietNativeTheme.accentSoft)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .quietNativeTabBarClearance()
        .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
        .navigationTitle(isEditing ? text.edit : text.journalTab)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            JournalUnreadStore.markRead(entry.id)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                JournalTypographyMenu()

                if isEditing {
                    Button(text.save) {
                        let safeTitle = UserInputSanitizer.sanitize(editTitle, policy: .journalTitle)
                        let safeBody = UserInputSanitizer.sanitize(editBody, policy: .journalBody)
                        guard !safeTitle.isEmpty, !safeBody.isEmpty else { return }
                        entry.title = safeTitle
                        entry.fullDiaryText = safeBody
                        entry.summaryText = String(safeBody.prefix(60))
                        try? modelContext.save()
                        isEditing = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(QuietNativeTheme.accent)
                } else {
                    Button(text.edit) {
                        editTitle = entry.title
                        editBody = entry.fullDiaryText
                        isEditing = true
                    }
                    .foregroundStyle(QuietNativeTheme.accent)
                }
            }
        }
    }
}
