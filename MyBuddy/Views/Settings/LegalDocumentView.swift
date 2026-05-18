import SwiftUI

/// 法務文書（プライバシーポリシー / 利用規約 / OSS ライセンス）を共通表示するビュー
struct LegalDocumentView: View {
    let title: String
    let content: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(content)
                    .font(.body)
                    .foregroundStyle(QuietNativeTheme.primaryText)
                    .lineSpacing(6)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .quietNativeCard(cornerRadius: 22)
            .padding(.horizontal)
            .padding(.top, 16)
            .quietNativeTabBarClearance()
        }
        .background(QuietNativeTheme.pageGradient)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
