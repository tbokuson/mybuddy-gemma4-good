import Foundation

/// アプリ内に表示する法務文書（プライバシーポリシー / 利用規約 / OSS ライセンス）
///
/// 会話データは端末内にとどめつつ、初回モデル取得のみネットワーク通信を行う前提の文言。
enum AppLegalContent {
    static let lastUpdated = "2026年4月29日"
    static let lastUpdatedEnglish = "April 29, 2026"

    static func privacyPolicy(language: ResolvedAppLanguage) -> String {
        language == .english ? privacyPolicyEnglish : privacyPolicy
    }

    static func termsOfService(language: ResolvedAppLanguage) -> String {
        language == .english ? termsOfServiceEnglish : termsOfService
    }

    static func openSourceLicenses(language: ResolvedAppLanguage) -> String {
        language == .english ? openSourceLicensesEnglish : openSourceLicenses
    }

    static let privacyPolicy = """
    最終更新日: \(lastUpdated)

    MyBuddy（以下「本アプリ」）は、ユーザー（以下「あなた」）のプライバシーを最優先に設計されています。本ポリシーは、本アプリがあなたの情報をどのように扱うかを説明します。

    1. データの取り扱い方針
    本アプリは、会話データと AI 推論を端末内で扱うことを前提に設計されています。
    ・すべての会話・日記・バディ設定・画像は、あなたの iPhone 内にのみ保存されます。
    ・AI（人工知能）の推論処理も、あなたの iPhone 内で完結します。
    ・初回セットアップ時に、AI モデルファイルを取得するためのネットワーク通信を行う場合があります。
    ・モデル取得通信に、会話履歴、日記、画像、プロフィールなどのユーザーデータが含まれることはありません。

    2. 収集する情報
    本アプリ自身は以下のいずれの情報も収集しません。また、モデル取得通信へ以下の情報を送信しません。
    ・個人を特定できる情報（氏名・メール・電話番号・端末識別子等）
    ・利用ログ・分析データ・クラッシュレポート
    ・位置情報・連絡先・カレンダー
    ・広告 ID（IDFA）

    3. 端末内に保存されるデータ
    本アプリはあなたが入力・選択した以下の情報を、あなたの iPhone 内のアプリ専用ストレージに保存します。
    ・ニックネーム
    ・バディの名前・人格設定・見た目
    ・会話履歴
    ・日記本文・タイトル・感情タグ・添付画像
    ・連続記録日数（ストリーク）

    これらのデータは iOS のファイル保護機能（NSFileProtectionComplete）により、端末ロック中はアクセス不可に設定されています。また iCloud バックアップ対象から除外されており、Apple のクラウドにも送られません。

    4. 写真の取り扱い
    会話に画像を添付する際、iOS 標準の写真ピッカー（PhotosPicker）を使用します。これは Apple が提供する独立した仕組みで、選択した写真のみが本アプリに渡されます。本アプリが写真ライブラリ全体にアクセスすることはありません。

    渡された画像は、AI による画像理解処理に使われたうえで、日記に紐づけて端末内のみに保存されます。画像が外部に送信されることはありません。

    5. ネットワーク通信
    本アプリは、初回セットアップ時に AI モデルファイルを配布元から取得するための通信を行うことがあります。この通信はモデルファイルの取得に限定され、会話内容や日記本文などのユーザーデータは送信されません。

    モデル取得後の通常利用では、会話・日記生成・画像理解の推論は端末内で完結します。モデルを取得済みであれば、インターネット接続なしでも会話機能を利用できます。

    6. 第三者ライブラリ
    本アプリは複数のオープンソースソフトウェアを利用しています。通常の会話・日記機能では、これらを端末内で利用します。詳細は「OSS ライセンス」をご確認ください。

    7. データの削除
    設定画面の「バディと日記をリセット」から、本アプリが保存したすべてのデータを完全に削除できます。アプリ本体を iPhone から削除すれば、データも同時に消去されます。

    8. 子どものプライバシー
    保護者の方は、子どもが日記に個人的な情報を記録することについて、必要に応じて指導してください。本アプリ自身は記録内容を外部に送信することはありません。

    9. ポリシーの変更
    本ポリシーを更新する場合、本アプリのアップデート時に変更内容をお知らせします。

    10. お問い合わせ
    本ポリシーに関するご質問は、App Store の本アプリページに記載のサポート連絡先までお願いします。
    """

    static let termsOfService = """
    最終更新日: \(lastUpdated)

    本利用規約（以下「本規約」）は、MyBuddy（以下「本アプリ」）の利用条件を定めるものです。本アプリをご利用いただくことで、本規約に同意したものとみなされます。

    1. 利用条件
    ・本アプリは個人の日記・記録目的でご利用いただけます。
    ・本アプリの動作には iOS 17.6 以降を搭載した iPhone が必要です。
    ・本アプリのリバースエンジニアリング、逆コンパイル、改変は禁止します。

    2. AI 生成コンテンツについて
    ・本アプリのバディ（AI）が生成する応答・日記本文・要約等は、オンデバイスで動作する小規模言語モデルによる自動生成物です。
    ・AI の出力は不正確・不適切な内容を含む場合があります。医療・法律・金融等の専門的な判断を要する事項について、AI の出力を判断材料にしないでください。
    ・AI の出力に起因する判断・行動の結果について、開発者は責任を負いません。

    3. ユーザーの責任
    ・本アプリに記録される会話・日記の内容は、すべてあなた自身の責任で管理してください。
    ・本アプリはデータを端末内のみに保存します。iPhone を紛失した場合や本アプリを削除した場合、データは復元できません。重要な記録は別途バックアップしてください。
    ・本アプリのデータは iCloud バックアップから除外しているため、機種変更時の自動データ移行はできません。
    ・初回セットアップ時には、大容量の AI モデルファイルを取得するため、十分な空き容量と安定したネットワーク接続をご用意ください。

    4. 禁止事項
    ・違法行為、または他者の権利を侵害する用途での使用
    ・本アプリを改変・複製・再配布する行為
    ・本アプリのオンデバイス AI モデルを抽出して他用途で利用する行為

    5. 免責事項
    ・本アプリは「現状のまま（AS IS）」提供されます。
    ・開発者は、本アプリの利用または利用不能から生じる、いかなる直接的・間接的・偶発的・特別・結果的損害についても責任を負いません。
    ・AI モデルの動作・出力品質、デバイスのバッテリー消費、メモリ使用量について、開発者は保証しません。

    6. 知的財産権
    本アプリ自体の著作権は開発者に帰属します。本アプリが利用するオープンソースソフトウェアおよび AI モデルは、それぞれのライセンス条件に従います。詳細は「OSS ライセンス」をご確認ください。

    7. 規約の変更
    本規約は予告なく変更されることがあります。変更後の本規約は、本アプリのアップデート公開時から効力を生じます。

    8. 準拠法
    本規約は日本法に準拠し、本規約に関する紛争は東京地方裁判所を専属管轄裁判所とします。
    """

    static let openSourceLicenses = """
    本アプリは以下のオープンソースソフトウェア・モデルを利用しています。各ソフトウェアの著作権は、それぞれの権利者に帰属します。

    ── llama.cpp ──
    ライセンス: MIT License
    Copyright (c) 2023-2026 The ggml authors

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

    ── Gemma 4 model (E2B-it Q4_K_M) ──
    Google Gemma Terms of Use に基づき、本アプリ内での推論利用を目的として初回セットアップ時に取得します。モデルの抽出・再配布は禁止されています。
    https://ai.google.dev/gemma/terms

    ── stb_image ──
    Public Domain (Sean Barrett)。本アプリでは画像デコードに使用しています。

    ── miniaudio ──
    Public Domain / MIT-0 (David Reid)。本アプリでは VisionEngine の依存として同梱されていますが、マイク入力等の音声機能は使用していません。

    ── Apple Frameworks ──
    SwiftUI / SwiftData / Foundation / UIKit / Metal / PhotosUI 等は Apple Inc. の SDK を利用しています。
    """

    private static let privacyPolicyEnglish = """
    Last updated: \(lastUpdatedEnglish)

    MyBuddy (the "App") is designed with privacy as a first principle. This policy explains how the App handles your information.

    1. Basic policy
    The App is designed to keep diary data and AI inference on your device.
    - Chats, diary entries, buddy settings, and images are stored only on your iPhone.
    - AI inference runs on your iPhone.
    - During first setup, the App may connect to the internet to download AI model files.
    - That model download does not include your chats, diaries, images, profile, or other personal diary data.

    2. Information collected
    The App itself does not collect or transmit:
    - Personal identifiers such as your name, email address, phone number, or device identifier.
    - Analytics, usage logs, crash reports, location, contacts, calendar data, or advertising identifiers.

    3. Data stored on device
    The App stores the information you enter or choose in the App's private storage on your iPhone:
    - Your nickname.
    - Your buddy's name, personality settings, and appearance.
    - Chat history.
    - Diary titles, body text, emotion tags, and attached images.
    - Streak count.

    This data uses iOS file protection (NSFileProtectionComplete), so it is inaccessible while the device is locked. It is excluded from iCloud backup and is not sent to Apple's cloud by the App.

    4. Photos
    When you attach an image, the App uses Apple's system PhotosPicker. Only the photo you select is passed to the App. The App does not access your full photo library.

    Selected images are used for on-device image understanding and may be saved with the related diary entry on your iPhone. They are not sent to an external server by the App.

    5. Network communication
    The App may use network communication during first setup to download AI model files. This communication is limited to downloading model files and does not send diary or chat content.

    After the model files are downloaded, normal chat, diary generation, and image understanding run on device. If the model is already available, the App can be used without an internet connection.

    6. Third-party components
    The App uses open source software and model files. These components are used locally for normal chat and diary features. See "OSS Licenses" for details.

    7. Deleting data
    You can delete all data saved by the App from Settings by choosing "Reset buddy and diaries." Deleting the App from your iPhone also deletes the App's local data.

    8. Children's privacy
    Guardians should guide children as needed when they record personal information in a diary. The App itself does not send diary content outside the device.

    9. Changes
    If this policy changes, the updated policy will be provided in an App update.

    10. Contact
    For questions about this policy, please use the support contact listed on the App Store page.
    """

    private static let termsOfServiceEnglish = """
    Last updated: \(lastUpdatedEnglish)

    These Terms of Service (the "Terms") govern your use of MyBuddy (the "App"). By using the App, you agree to these Terms.

    1. Use of the App
    - The App is for personal diary and reflection purposes.
    - The App requires an iPhone running iOS 17.6 or later.
    - You may not reverse engineer, decompile, modify, or redistribute the App.

    2. AI-generated content
    - Buddy replies, diary entries, summaries, and related text are generated automatically by a small language model running on device.
    - AI output may be inaccurate, incomplete, or inappropriate. Do not rely on it for medical, legal, financial, or other professional decisions.
    - The developer is not responsible for decisions or actions taken based on AI output.

    3. Your responsibility
    - You are responsible for the chats and diary content you record in the App.
    - The App stores data only on your device. If you lose your iPhone or delete the App, the data may not be recoverable. Keep separate backups for important records.
    - The App's data is excluded from iCloud backup, so automatic migration to a new device is not provided.
    - First setup requires enough storage and a stable network connection to download large AI model files.

    4. Prohibited uses
    - Illegal activity or infringement of another person's rights.
    - Modifying, copying, or redistributing the App.
    - Extracting the on-device AI model from the App for other uses.

    5. Disclaimer
    - The App is provided "AS IS."
    - The developer is not liable for direct, indirect, incidental, special, or consequential damages arising from use or inability to use the App.
    - The developer does not guarantee AI model behavior, output quality, battery usage, or memory usage.

    6. Intellectual property
    The copyright in the App belongs to the developer. Open source software and AI models used by the App are governed by their respective license terms. See "OSS Licenses" for details.

    7. Changes
    These Terms may change without prior notice. Updated Terms take effect when the App update containing them is released.

    8. Governing law
    These Terms are governed by the laws of Japan. Disputes related to these Terms are subject to the exclusive jurisdiction of the Tokyo District Court.
    """

    private static let openSourceLicensesEnglish = """
    The App uses the following open source software and model files. Copyrights belong to their respective owners.

    -- llama.cpp --
    License: MIT License
    Copyright (c) 2023-2026 The ggml authors

    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.

    -- Gemma 4 model (E2B-it Q4_K_M) --
    The model is downloaded during first setup for inference inside this App under the Google Gemma Terms of Use. Extracting or redistributing the model is prohibited.
    https://ai.google.dev/gemma/terms

    -- stb_image --
    Public Domain (Sean Barrett). Used for image decoding.

    -- miniaudio --
    Public Domain / MIT-0 (David Reid). Bundled as a dependency of VisionEngine. The App does not use microphone or audio input features.

    -- Apple Frameworks --
    SwiftUI, SwiftData, Foundation, UIKit, Metal, PhotosUI, and other Apple SDK frameworks are provided by Apple Inc.
    """
}
