import SwiftUI

enum JournalTypographyStyle: String, CaseIterable, Identifiable {
    case natural
    case rounded
    case compact

    static let storageKey = "journal.typographyStyle"
    static let defaultStyle: Self = .natural

    var id: String { rawValue }

    func label(language: ResolvedAppLanguage = AppLanguageMode.currentResolved) -> String {
        if language == .english {
            switch self {
            case .natural:
                return "Standard"
            case .rounded:
                return "Soft"
            case .compact:
                return "Compact"
            }
        }
        switch self {
        case .natural:
            return "標準"
        case .rounded:
            return "やわらかめ"
        case .compact:
            return "すっきり"
        }
    }

    var symbolName: String {
        switch self {
        case .natural:
            return "textformat"
        case .rounded:
            return "character.bubble"
        case .compact:
            return "text.justify"
        }
    }

    var fontDesign: Font.Design? {
        switch self {
        case .rounded:
            return .rounded
        case .natural, .compact:
            return nil
        }
    }

    var fontWidth: Font.Width? {
        switch self {
        case .compact:
            return .condensed
        case .natural, .rounded:
            return nil
        }
    }

    var titleFont: Font {
        switch self {
        case .compact:
            return .title2.weight(.bold)
        case .natural, .rounded:
            return .title.weight(.bold)
        }
    }

    var bodyFont: Font { .body }
    var noteFont: Font { .subheadline }

    var bodyLineSpacing: CGFloat {
        switch self {
        case .natural:
            return 10
        case .rounded:
            return 9
        case .compact:
            return 8
        }
    }

    var summaryLineSpacing: CGFloat {
        switch self {
        case .natural, .rounded:
            return 4
        case .compact:
            return 3
        }
    }

    var bodyTracking: CGFloat {
        switch self {
        case .natural:
            return 0.2
        case .rounded:
            return 0.1
        case .compact:
            return 0
        }
    }

    static func from(rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? defaultStyle
    }
}

private struct JournalTypographyModifier: ViewModifier {
    let style: JournalTypographyStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        if let design = style.fontDesign, let width = style.fontWidth {
            content
                .fontDesign(design)
                .fontWidth(width)
        } else if let design = style.fontDesign {
            content.fontDesign(design)
        } else if let width = style.fontWidth {
            content.fontWidth(width)
        } else {
            content
        }
    }
}

extension View {
    func journalTypography(_ style: JournalTypographyStyle) -> some View {
        modifier(JournalTypographyModifier(style: style))
    }
}

struct JournalTypographyMenu: View {
    @AppStorage(JournalTypographyStyle.storageKey)
    private var typographyRawValue = JournalTypographyStyle.defaultStyle.rawValue
    @AppStorage(AppLanguageMode.storageKey) private var languageModeRawValue = AppLanguageMode.system.rawValue

    private var typography: JournalTypographyStyle {
        JournalTypographyStyle.from(rawValue: typographyRawValue)
    }

    private var text: AppText {
        AppText(language: (AppLanguageMode(rawValue: languageModeRawValue) ?? .system).resolvedLanguage)
    }

    var body: some View {
        Menu {
            Picker(text.isEnglish ? "Body font" : "本文フォント", selection: $typographyRawValue) {
                ForEach(JournalTypographyStyle.allCases) { style in
                    Label(style.label(language: text.resolvedLanguage), systemImage: style.symbolName)
                        .tag(style.rawValue)
                }
            }
        } label: {
            Image(systemName: "textformat")
        }
        .accessibilityLabel(text.isEnglish ? "Diary font" : "日記のフォント")
        .accessibilityValue(typography.label(language: text.resolvedLanguage))
    }
}
