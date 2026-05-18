import SwiftUI
import SwiftData

struct BuddyProfileView: View {
    let buddy: BuddyProfile
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 14) {
                    BuddyAvatarView(seed: buddy.seed, size: 120)
                        .padding(.top, 8)

                    Text(buddy.displayName)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(QuietNativeTheme.primaryText)

                    Text(text.buddyProfileSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(QuietNativeTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(QuietNativeTheme.heroGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 22, y: 10)

                VStack(spacing: 12) {
                    ProfileCard(
                        icon: "heart.fill",
                        label: text.buddyProfilePersona,
                        value: text.personaLabel(style: buddy.personaStyle, custom: buddy.personaStyleCustom)
                    )
                    ProfileCard(
                        icon: "person.wave.2.fill",
                        label: text.buddyProfileDistance,
                        value: text.distanceLabel(distance: buddy.conversationDistance, custom: buddy.conversationDistanceCustom)
                    )
                    ProfileCard(
                        icon: "book.fill",
                        label: text.buddyProfileMemory,
                        value: text.memoryLabel(memory: buddy.memoryPreference, custom: buddy.memoryPreferenceCustom)
                    )

                    if !buddy.customTraits.isEmpty {
                        ProfileCard(
                            icon: "star.fill",
                            label: text.buddyProfileSpecialRule,
                            value: buddy.customTraits
                        )
                    }
                }

                if !buddy.personalityNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(text.buddyProfileAboutYou, systemImage: "person.fill")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(QuietNativeTheme.secondaryText)
                        Text(buddy.personalityNotes)
                            .font(.body)
                            .foregroundStyle(QuietNativeTheme.primaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .quietNativeCard(cornerRadius: 24)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .quietNativeTabBarClearance()
        .background(QuietNativeTheme.pageGradient.ignoresSafeArea())
        .navigationTitle(text.buddyProfileTitle(buddy.displayName))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProfileCard: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(QuietNativeTheme.accent)
                .frame(width: 28, height: 28)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(QuietNativeTheme.secondaryText)
                Text(value)
                    .font(.body)
                    .foregroundStyle(QuietNativeTheme.primaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(18)
        .quietNativeCard(cornerRadius: 24)
    }
}
