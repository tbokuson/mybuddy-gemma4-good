# プロンプト生成仕様書

本ドキュメントは、MyBuddy アプリケーションで使用するすべてのプロンプト生成処理の実装仕様を記録しています。

各項目は以下の情報を含みます：
- **実装ファイル** — コードの場所
- **関数・実装方式** — 具体的な実装
- **利用箇所** — どのプロンプトが使用するか
- **サンプリング設定** — temperature, top_k, top_p など
- **現在の仕様** — プロンプト全文または説明

---

## プロンプト実装一覧

| # | プロンプト | ファイル | 状態 | 備考 |
|---|---|---|---|---|
| 2 | 人格システムプロンプト | `BuddyProfile.swift` | 完了 | v5: 単語コピー禁止と雰囲気反映を分離。方言ガード追加 |
| 3 | 人格再注入アンカー | (削除済み) | 完了 | `makePersonaReanchor` 廃止。`buildPersonaAnchor` は残存（user turn 注入用） |
| 1 | チャット応答 — テキスト | `ChatResponseService.swift` | 完了 | 8箇条の会話方針 + 時刻コンテキスト + 締めモード + 記憶コンテキスト |
| 1b | チャット — 話題転換・会話終了 | `ChatViewModel.swift` | 完了 | 短応答2回+バディ非質問2回→強制締め。Toast サジェスト方式 |
| 2 | チャット応答 — 画像付き | `ChatResponseService.swift` | 完了 | テキスト版と統一・画像フォローアップ2ターン制御 |
| 3 | メモ抽出 (Stage 1) | `MemoExtractionStage.swift` | 完了 | フォーマット指示形式に刷新。空括弧除去・ダンプログ追加 |
| 4 | 日記生成 (Stage 2) | `ThinkingDiaryStage.swift` | 完了 | ルール9箇条・感情タグ上限2件・バディ一言・段落構成・過去形強制 |
| 4b | 日記リライト | (削除済み) | 完了 | メモ入力化で丸写し問題が解消 |
| 5 | フォールバック返答生成 | `FallbackReplyGenerator.swift` | 完了 | LLM不使用。PersonaLineComposer で決定的に生成 |
| 6 | オンボーディング会話 | `OnboardingViewModel.swift` | 完了 | セクション制御化+【確定:enum:内容】タグ |
| 6b | ニックネーム抽出 | `OnboardingViewModel.swift` | 完了 | シンプルで問題なし |
| 6c | パラメータ抽出 (JSON) | (削除済み) | 完了 | セクション別【確定】タグに置換 |
| 6d | Reveal 挨拶生成 | `OnboardingViewModel.swift` | 完了 | 2のsystemPromptのみ |
| 7 | 挨拶テンプレート | `ChatViewModel.swift` + `PersonaLineComposer.swift` | 完了 | LLM不使用。決定的テンプレートに移行 |
| 8 | 会話終了メッセージ | `ChatViewModel.swift` + `PersonaLineComposer.swift` | 完了 | LLM不使用。決定的テンプレートに移行 |
| 9 | 日記サジェスト Toast | `ChatViewModel.swift` | 完了 | 新機能。締めシグナル検知→Toast表示 |
| 補足 | LocalTimeContext chatTimeHint | `LocalTimeContext.swift` | 完了 | `ChatResponseService.buildTextSystemPrompt` で system に注入済み |

---

## 2. 人格システムプロンプト (共通ベース) 完了

**ファイル:** `MyBuddy/Models/BuddyProfile.swift:101-146`
**関数:** `BuddyProfile.buildSystemPrompt(displayName:seed:userNickname:)`
**利用箇所:** 1, 2, 5, 6d のベース

### 現在のコード

```swift
static func buildSystemPrompt(displayName: String, seed: BuddySeed, userNickname: String = "") -> String {
    let personaCustom = seed.personaStyleCustom.trimmingCharacters(in: .whitespacesAndNewlines)
    let distanceCustom = seed.promptReadyConversationDistanceCustom
    let traits = seed.customTraits.trimmingCharacters(in: .whitespacesAndNewlines)
    let nick = userNickname.trimmingCharacters(in: .whitespacesAndNewlines)

    let personality = seed.personalityPromptDesc
    let voice = seed.personaStyle.voiceDescription
    let distance = distanceCustom.isEmpty ? seed.conversationDistance.promptDescription : distanceCustom

    var sections: [String] = [
        "あなたは「\(displayName)」という名前のキャラクター。返答はひらがな・カタカナ・漢字・句読点だけで書く。英単語・ローマ字・絵文字・記号は使わない。"
    ]
    sections.append("基本の人柄: \(personality)。")
    sections.append("基本の口調: \(voice)。")
    if !personaCustom.isEmpty {
        sections.append("キャラ像: 「\(personaCustom)」と呼ばれるような人物像を想像し、その雰囲気・口癖・テンション・態度で話す。ただし『\(personaCustom)』という単語そのもの、そして自分の性格分類名を会話の文中に書いてはいけない。")
    }
    if !traits.isEmpty {
        sections.append("追加の振る舞い: \(traits)。この文言そのままを会話文に書き写すのではなく、実際の口調や態度で表現する。")
    }
    sections.append("距離感: \(distance)。")
    if !nick.isEmpty {
        sections.append("相手は「\(nick)」。自分と相手を混同しない。")
    }
    // 方言ガード
    if seed.requestsExplicitDialect {
        sections.append("方言や独自の語尾が指定されている。その話し方を最優先で守り、標準語に戻さない。指示された語尾・抑揚を全ての返答で貫く。")
    } else {
        sections.append("方言の指定がないので標準語で話す。勝手に方言を混ぜない。")
    }
    sections.append("返答は会話文 1〜2 文だけ。前置き・見出し・設定の復唱・箇条書き・ト書きは書かない。")
    return sections.joined(separator: "\n")
}
```

### 変更点
- 以前: 1文連結構成（v4）
- 現在: v5 で構造化セクション形式に変更
  - 「単語コピー禁止」と「雰囲気反映」を明確に分離
  - `personalityPromptDesc` / `voiceDescription` で基本の人柄・口調を個別記述
  - `requestsExplicitDialect` で方言ガード（方言指定あり→最優先で守る、なし→標準語固定）
  - `buildPersonaAnchor` で user turn に再注入するアンカーも別途提供
  - `buildUtteranceOnlySystemPrompt` で台詞本文のみ返す場面用のラッパーも追加

---

## 1. チャット応答 — テキスト 完了

**ファイル:** `MyBuddy/Services/ChatResponseService.swift:102-157`
**関数:** `buildTextSystemPrompt(for:)`
**呼出元:** `streamReply()` / `generateReply()`
**テンプレート:** `Gemma4PromptBuilder.buildMultiTurn(system:history:newUserMessage:)`
**maxTokens:** 192

### 現在の system プロンプト

```
{buddy.systemPrompt}  <-- 2の出力（v5構造化セクション）
現在時刻: {dateString} {timeString} / {timeSlot} / {dayTypeString}
{chatTimeHint}
会話方針:
- 返答は 1〜2 文、合計 60 字以内。自分の感想を一言入れてから、続きを聞く質問を短く添える
- 文末は「〜だね」「〜だよ」「〜かな」「〜だった」のような常体。「です」「ます」「ました」「でしょうか」は使わない
- ユーザーの発言をそのまま繰り返さない。語尾や単語を言い換えて応答する
- 同じ話題は 1〜2 往復で区切り、「他には？」の定型は避けて、朝／昼／夜や別の出来事・人・場所のどれか 1 つの切り口を選んで自然に移す
- ユーザーが「そうだね」「うん」「もういいかな」「また明日」「おやすみ」など会話を締めたそうなサインを出したら、新しい質問を重ねず、ねぎらいや「おつかれ」「今日もお疲れさま」「また明日」といった短い一言で自然に会話を閉じる
- 日記・メモ・箇条書き・ト書きを出さず、会話文だけ返す
- 角括弧・引用符・時刻ラベルで返答を始めない
- ローマ字や英単語（huh / went / ok / maybe など）は書かず、必ず日本語の語句に言い換える
```

### コンテキスト依存の追加指示

| 条件 | 追加される指示 |
|---|---|
| `memoryContext` が非空 | 記憶コンテキストを system に注入 |
| `isCorrectionReply` | 「相手は直前の受け取りを修正している。まず素直に受け取り直し、反論や助言をしない。」 |
| `isImageFollowUp` | 「この返答は直前の画像の話題の続き。画像の文脈を保って答える。」 |
| `shortResponseBias && earlyConversation` | 「会話はまだ序盤。短い返答でも早く締めず、今日ここまでの別の具体的な出来事を1つだけ聞いてよい。」 |
| `shortResponseBias` (序盤以外) | 「相手の返答は短い。新しい質問は増やしすぎず、短く受け止めるか軽く別の出来事へ移る。」 |
| `userMessage.count <= 12 && turnCount <= 4` | 「ユーザーの返答は短い。無理に同じ話題を掘らず、必要なら今日の別の出来事へ自然に移ってよい。」 |
| `turnCount >= 5` | 「会話はある程度続いている。新しい質問を重ねず、ねぎらいの一言や『また明日』『おつかれ』のような締めの挨拶に寄せる。」 |
| **締めモード**: `endOfTopicsBias \|\| (turnCount >= 5 && shortResponseBias)` | 「【締めモード】相手はもう話すことがないと示している。次の返答は質問を 1 つも入れず、20 字以内のねぎらい・締めの挨拶（例: 「今日もおつかれさま」「また明日ね」「ゆっくり休んでね」）のどれか 1 文だけを返す。新しい話題・質問・掘り下げは禁止。」 |

### `isEndOfTopicsReply` 判定

「もう話すことがない」を示す返答を検知する新規メソッド。以下を完全一致または部分一致で拾う:
- 完全一致: 「ない」「ないよ」「なし」「特にない」「特になし」「もうない」「もうないよ」「もう無い」「そんなとこかな」「そんなとこ」「そんなもん」「そんなもんかな」「それぐらい」「それくらい」「以上」「おしまい」「終わり」「もういい」「もういいよ」「もういいかな」
- 部分一致: 「そんなとこ」「特にない」「もう話すこと」「他には無い」「他にはない」

### 現在の user メッセージ構築

以前のアプリレベル話題転換（`userMessage.count <= 12` で【】注入）は **廃止済み**。現在は user turn にユーザーメッセージをそのまま渡す。制御指示は全て system に集約。

```swift
// userContext が空の場合:
userMessage  // そのまま

// userContext がある場合:
userContext + "\n\n" + userMessage
```

### サンプリングパラメータ (`LLMSamplingProfile.chat`)

| パラメータ | 値 |
|---|---|
| temperature | 0.60 |
| topK | 30 |
| topP | 0.90 |
| minP | 0.05 |
| repeatPenalty | 1.10 |
| repeatLastN | 256 |
| seed | nil (ランダム) |

### 変更点
- 以前: 1文 persona + 口調指示 + 1行ルール。ユーザー短応答時に【】話題転換注入
- 現在: 構造化 persona(v5) + 時刻コンテキスト(`chatTimeHint`)復活 + 8箇条の会話方針
- `isEndOfTopicsReply` 判定を新設し、締めモードで質問禁止・20字以内を強制
- `turnCount >= 5` のヒントが「ねぎらいの一言や『また明日』『おつかれ』のような締めの挨拶に寄せる」に変更
- user turn への制御注入を廃止し、system に全集約
- `memoryContext` を system に注入（記憶コンテキスト復活）

---

## 1b. 会話管理（話題転換・会話終了・重複検知・日記サジェスト） 完了

**ファイル:** `MyBuddy/ViewModels/ChatViewModel.swift`
**プロンプトではなくアプリレベルのガード。**

### 会話終了 (`consecutiveShortReplies` + `consecutiveNonQuestionBuddyReplies`)
- `isDismissiveReply` で拒否的な応答を検知
  - 完全一致: 「ない」「なし」「特にない」「べつに」「別に」「いや」「やだ」「もういい」「大丈夫」「終わり」「おやすみ」「またね」「ありがとう」「わかった」「了解」「うん」「はい」「そうだね」「no」「nah」
  - 部分一致: 「話したくない」「もういい」「終わり」「眠いからやめる」「ここまで」
- 閾値: **2回連続**（以前は3回）で `consecutiveShortReplies >= 2`
- `consecutiveNonQuestionBuddyReplies`: バディ応答末尾が「？」「?」でない場合にカウント。疑問符で終わればリセット
- **強制締め発動条件**: ユーザー dismissive 2回連続 **AND** バディ非質問 2回連続
- 強制締め時の動作: `generateClosingMessage` で決定的テンプレートの締めメッセージを送信 → **日記モーダルではなく Toast サジェスト**（`maybeSuggestDiaryOnClosing`）

### 日記サジェスト Toast（新機能） {#toast}
- `shouldSuggestDiary` フラグで ChatView に Toast を表示
- 発動条件: ユーザー/バディの締めシグナル検出 + `turnCount >= 3` + 未サジェスト(`hasSuggestedDiaryThisSession == false`) + `canTriggerDiaryCompilation`
- 「作成」ボタンで `acceptDiarySuggestion()` → 日記作成を起動
- 「x」ボタンで `dismissDiarySuggestion()` → 非表示。会話は続行可能

### 締め検知 (`detectClosing`)
- ユーザー側シグナル: 「また明日」「おやすみ」「もういい」「今日はここまで」「そろそろ寝る」「ありがとう」「バイバイ」「じゃあね」「もう寝る」→ バディの「？」に関係なく通す
- バディ側シグナル: 「また明日」「おつかれ」「お疲れさま」「お疲れ様」「ゆっくり休んで」「おやすみ」「今日もお疲れさま」→ バディ応答末尾が「？」「?」なら無効化

### 重複応答検知 (`isDuplicateResponse`)
- 直近 2 件のバディ発話と完全一致をチェック（句読点・末尾記号は正規化で吸収）
- 一致検出 → フォールバック応答に切り替え

---

## 2. チャット応答 — 画像付き 完了

**ファイル:** `MyBuddy/Services/ChatResponseService.swift:217-238`
**関数:** `generateImageReply()` / `buildImageSystemPrompt()`
**テンプレート:** `Gemma4PromptBuilder.buildMultiTurnWithImage(system:history:newUserMessage:)`
**maxTokens:** 192

### 現在のプロンプト全文

**system:**
```
{buddy.systemPrompt}  <-- 2の出力（v5構造化セクション）
あなたは「{buddyName}」。話し相手は「{userName}」。この2つは別の存在。
画像応答ルール:
- 先頭に時刻ラベルや引用符を付けない
- まず画像について1文で触れる
- 断定せず「〜に見える」「〜っぽい」を使う
- 返答は1〜2文に収める
- 質問する場合も1つまでにする
```

**user:**
```
{userMessage}
```

### 画像フォローアップ（2ターン制御）

画像送信直後のテキストターンでは、system に以下が追加される:
```
この返答は直前の画像の話題の続き。画像の文脈を保って答える。
```
- `ChatViewModel.lastImageTurnCount` で画像送信ターンを記録
- テキスト送信時に `lastImageTurnCount == turnCount - 1` なら `isImageFollowUp=true`
- 短応答でもフォローアップを優先

---

## 3. メモ抽出 — MemoExtractionStage 完了

**ファイル:** `MyBuddy/Services/DiaryPipeline/Stages/MemoExtractionStage.swift`
**2段階パイプラインの Stage 1。**
**テンプレート:** `Gemma4PromptBuilder.buildSingleTurn(system:user:)`
**maxTokens:** config.memoExtraction.maxTokens (192)
**samplingProfile:** `.extraction` (temp=0.20, topK=20, topP=0.85, seed=17)

### プロンプト全文

**system:**
```
会話ログから「ユーザー:」で始まる行にある出来事だけを抜き出す。「相手:」の行は絶対に抜き出さない。推測や要約はしない。
```

**user:**
```
「ユーザー:」行に書かれた出来事を、次のフォーマットで 1 行ずつ書き出す。

フォーマット:
- 行頭は必ず半角ハイフンと半角スペース「- 」で始める
- その直後にユーザー発言から読み取れる出来事を、1 行 1 件として日本語で書く（「事実」や「出来事」のような単語をそのまま書かない）
- ユーザー発言の中に感情語（疲れた／嬉しかった／不安 など、本人が口にした気持ちを表す語）があれば、同じ行の末尾に全角丸括弧でくくって書き添える（例: 行の末尾が「……（疲れた）」）。感情語が無い行には丸括弧を付けない
- 固有名詞（地名・店名・人名・商品名・ブランド名）はそのままの表記で残す。略さない、上位語に置き換えない
- ユーザー行の事実はひとつも漏らさない。近い話題でも別々の行に分けて全部書く
- 「（写真: …）」の補足があれば、その内容も事実として取り込む
- 相づちや単独の確認（うん／そう／はい）は無視する
- 事実が 1 つも無ければ「なし」とだけ出力する

【会話】
{conversationLog}
```

### パーサーの後処理
- 空括弧 `（）` / `()` を除去
- `splitStructuredContent` で「事実（感情）」を分離
- `normalizeFact`: 山括弧・鉤括弧等のラッパーを除去、末尾句読点をトリム
- `normalizeEmotion`: 「なし」「無し」を除去、12文字超を除去、禁止フラグメント（上司・会議等）を除去
- `isPlaceholderFact`: 「事実」「出来事」「エピソード」等のプレースホルダーを除去
- `repairMemos`: 重複除去 + コンテキストベースの主語補完（例: 「上司」が会話に含まれている場合に主語を補完）
- **ダンプログ**: パース結果を `ProbeLogger.block` で fact/emotion を 1 行ずつ出力

### チャンク処理
- `chunkSize` (デフォルト5) 件ずつ分割
- チャンク間で `Task.checkCancellation()` を挟み、バックグラウンド制限に対応

### 変更点
- 以前: 「- 事実（感情）」テンプレートと具体例を提示
- 現在: フォーマット指示形式に刷新
  - 「行頭は必ず半角ハイフンと半角スペース「- 」で始める」
  - 「事実や出来事のような単語をそのまま書かない」
  - 固有名詞保持ルール追加
  - 「（写真: ...）」補足の取り込みルール追加
  - 具体例は削除済み（LLMが引きずるため）
- パーサーに空括弧除去処理を追加
- メモパース結果のダンプログを追加

---

## 4. 日記生成 — ThinkingDiaryStage 完了

**ファイル:** `MyBuddy/Services/DiaryPipeline/Stages/ThinkingDiaryStage.swift`
**関数:** `run(memos:conversationTurns:memoryPreference:memoryPreferenceCustom:buddyName:buddySeed:)`
**テンプレート:** `Gemma4PromptBuilder.buildSingleTurnWithThinking(system:user:)` (thinking モード)
**maxTokens:** config.thinkingStage.maxTokens (640)
**samplingProfile:** `.journal` (temp=0.45, topK=20, topP=0.85, repeatPenalty=1.03, seed=29)

### 現在のプロンプト全文

**system:**
```
あなたはユーザー本人の立場で、今日のメモをもとに日記を書く。視点は一人称「私」、文体は「〜した」「〜だった」「〜かった」の常体。「です／ます／ました」は使わない。

重要ルール（違反禁止）:
1. メモに書かれた事実と感情だけを使う。メモに無い情景（天気・表情・心の動き・他人の言動など）を足さない。
2. 時系列に沿って、関連する出来事を自然につなぐ。メモを並列に並べるだけでも、情景を作り足すのでもない。
3. 感情は、メモの丸括弧（ ）内に書かれた語句だけを拾う。括弧外の語を感情にしない。
4. 全メモの事実が本文に入るようにする（捨てない）。
5. バディや相手の存在、呼びかけ、助言、一般論は書かない。
6. 返答はひらがな・カタカナ・漢字・句読点だけ。英単語やローマ字、絵文字、記号は使わない。
7. メモの出来事はすべて「今日すでに起きたこと」として過去形で書く。「〜する予定だった」「〜しようと思う」「〜するつもり」のような未来・予定・推測の表現は使わない。メモの語尾が「〜だね」「〜かな」のような曖昧な形でも、過去形に直して書く。
8. メモに含まれる固有名詞（地名・店名・人名・商品名・ブランド名）は、必ず本文にそのままの表記で書く。省略・言い換え・上位語への置き換えをしない。
9. 段落構成: 場面（朝／昼／夜、または別の場所・別の行動）が切り替わるところで段落を分ける。段落と段落のあいだは空行 1 行で区切る。1 段落は 1〜3 文にまとめる。

【日記スタイル】
{styleInstruction}

【バディからの一言の口調】
最終行の「一言:」だけは、バディの persona / distance / customTraits / カスタム人格指定を反映する。本文・タイトル・感情タグにはバディ口調を混ぜない。

出力フォーマット（前置き・後書き・見出し・コードブロック・ト書きは書かない。以下の 4 行だけを、行頭のラベル文字列も含めて出力する）:
1 行目: 「タイトル: 」で始め、その直後に 10〜16 文字の日本語タイトルを書く
2 行目: 「感情: 」で始め、その直後にメモの（ ）内の感情語を最大 2 つまでカンマ区切りで書く。括弧外の語を感情にしない。3 つ以上あっても 2 つに絞る。感情語が無ければ「なし」とだけ書く
3 行目以降: 「本文: 」で始め、その直後から日記本文を書く。本文は場面ごとに段落を分け、段落間は空行 1 行。メモの事実を全部含める
最終行: 「一言: 」で始め、「{buddyName}」からの短い（1 文・30 字以内）ポジティブなねぎらいや応援の言葉を書く。ここだけは上の口調指示を最優先で守る。日記本文・タイトル・感情にはこの口調を混ぜない

書き方のコツ（事実列挙を日記にする）:
- メモの事実を 1 文ずつぶつ切りに並べず、「そのあと」「それから」「昼には」「夕方になって」「気づけば」などの時間や流れをつなぐ言葉でなめらかに繋ぐ
- 同じ場面に属する事実は 1 段落にまとめ、場面が変わるところで段落を切る
- 感情語はメモの（ ）内にある語だけを使い、事実と同じ文の中に自然に溶かす（例: 「〜して、◯◯だった」）。丸括弧「（ ）」は本文には絶対に書かない。感情語を独立した 1 文にもしない
- 同じ語尾ばかりで単調にならないよう、「〜した」「〜だった」「〜かった」を織り交ぜる

例（形式と書き方だけを真似る。語句そのものは使わない）:
メモ（例）:
- 朝ごはんを食べた
- 少し散歩した（気持ちよかった）
- 夕方に家で過ごした

出力（例）:
タイトル: ゆっくりした一日
感情: 気持ちよかった
本文: 朝ごはんを食べて、一日が始まった。そのあと外に出て少し散歩してみたら、思いのほか気持ちよかった。

夕方になってからは家に戻って、そのままゆっくり過ごした。
一言: のんびりできた一日、いいね。明日も楽しみだね。

反例（やってはいけない。メモに無い情景・心の動き・表情などを勝手に足している）:
「少し焦りながら」「笑いあった」「一日の疲れが癒えていくのを感じた」のような、メモに書かれていない描写を付け足さない。
```

**user:**
```
【今日のメモ】
{memoText}
```

### 後処理
- `stripParenthesizedEmotion`: 本文中の丸括弧付き感情語（例: 「（嬉しかった）」）を除去。メモの感情タグがそのまま本文にコピーされた場合の安全網
- `sanitizeEmotionTags`: 感情タグ上限 **2件**。禁止フラグメント（上司・ツンデレ等）を除外
- `sanitizeBody`: メタ文（「日記を書いた」「バディに相談した」等）を文単位で除去
- `stripLabelEcho`: 「タイトル:」「感情:」等のラベルが本文に混入した場合に除去
- `shouldUseDeterministicFallback`: LLMがプロンプトのメタ出力（「【今日のメモ】」等）をそのまま返した場合、決定的フォールバックに切り替え

### バディからの一言
- LLMが日記最終行に「一言: 」ラベルで生成する。追加のLLM呼び出しは不要
- `BuddySeed` の persona / distance / customTraits / カスタム人格指定を `一言:` 専用の口調指示として注入する
- 関西弁指定があるのに標準語コメントが返った場合、`PersonaLineComposer.diaryComment` の決定的コメントへ差し替える
- `DiaryPipeline` で `stageOutput.buddyComment` → `DiaryPipelineResult.tomorrowNote` として保存
- 決定的フォールバック（`makeDeterministicFallback`）時も `outputWithPersonaAlignedBuddyComment` で一言を補完する

### 変更点
- 以前: ルール5箇条、感情「メモの()内にある感情のみ。なければ「なし」」、例文なし
- 現在:
  - ルール 7 追加: 過去形の強制（「予定だった」等の未来・推測表現を禁止）
  - ルール 8 追加: 固有名詞をそのまま保持
  - ルール 9 追加: 段落構成（場面切替で段落分け、空行1行区切り）
  - 感情タグ上限 2 件
  - バディからの一言（「一言: 」ラベル）を日記の最終行として LLM が生成
  - 書き方のコツ 4 項目を追加（接続詞でつなぐ、段落まとめ、感情語を文中に溶かす、語尾バリエーション）
  - 丸括弧を本文に書かないルール追加
  - `stripParenthesizedEmotion` 後処理で本文中の括弧付き感情を除去
  - 例文は当たり障りのない日常行動（朝ごはん/散歩/夕方に家で過ごした）に変更

---

## 4b. 日記リライト 削除済み

メモ入力化により丸写し問題が構造的に解消されたため、リライトステージごと削除。

---

## 5. フォールバック返答生成 完了

**ファイル:** `MyBuddy/Services/FallbackReplyGenerator.swift`
**関数:** `generate(displayName:seed:)`
**タイミング:** オンボーディング完了時に3件事前生成

### 現在の方式

**LLM 不使用**。`PersonaLineComposer.fallbackReplies()` で人格アーキタイプ (gentle/cool/bright/mellow/dominant/tsundere) x 関西弁フラグから決定的に 3 件を生成する。

`FallbackReplyGenerator` は `llmService` を引数に取るが、内部では使用していない。全て `PersonaLineComposer` に委譲。

### 変更点
- 以前: テンプレート3件をLLMで口調変換
- 現在: LLM不使用。PersonaLineComposer のパターンマッチによる決定的生成
- 生成済みプールは `BuddyProfile.fallbackReplies` に保存
- ランタイムでプールが空の場合、`PersonaLineComposer.fallbackReplies()` を直接呼ぶ最終安全網あり

---

## 6. オンボーディング会話 完了（セクション制御化）

**ファイル:** `MyBuddy/ViewModels/OnboardingViewModel.swift`
**関数:** `buildSectionSystemPrompt(for:buddyName:)` + `generateSectionResponse(userMessage:)`
**テンプレート:** `Gemma4PromptBuilder.buildMultiTurn(system:history:newUserMessage:)`
**maxTokens:** 128

### 設計変更

- 以前: 1つの巨大システムプロンプト(700文字)で4話題を一括管理 → LLM破綻頻発
- 現在: アプリ側でセクション制御（nickname→persona→distance→diaryStyle→customTraits→done）
- 各セクションで固定の質問メッセージ + セクション内マルチターン対話
- パラメータ確定はアプリ側の決定的ロジック（`buildSectionResponsePlan`）で判定。LLM は `【確定】` タグを出力しない
- `matchEnumForSection` がキーワードマッチで enum 分類を決定し、BuddySeed に直接書き込む
- LLM はセクション内の返答文面生成（曖昧入力への聞き返し等）にのみ使用
- 固定メッセージには 500ms のタイピングインジケータ遅延

### セクション専用システムプロンプト（例: persona）

```
あなたは「{buddyName}」。
今は設定確認だけをする。返答は1〜2文。
明確なら短く受け止めて終える。曖昧なときだけ質問は1問まで。
説明・復唱・状況説明・「承知しました」「〜を決めている」などのメタ発話は禁止。
確認対象は「{buddyName}のキャラや雰囲気」。指定があればそのまま採用する。
```

各セクションで確認対象の説明文のみ差し替え。全セクション同じ構造。

### パラメータ確定ロジック（アプリ側決定的処理）

`buildSectionResponsePlan` が入力を以下の 3 パターンに分類:
- `.nullish` — 「おまかせ」「特にない」等 → デフォルト値で確定
- `.confirm` — enum キーワードマッチ成功 → その enum + custom 値で確定
- `.continue` — 曖昧 → LLM に返答生成を依頼して会話継続

### 安全弁

8ターン（`maxSectionTurns`）を超えた場合、デフォルト値で強制確定。

---

## 6b. ニックネーム抽出 変更なし

**ファイル:** `MyBuddy/ViewModels/OnboardingViewModel.swift`
**関数:** `extractNicknameWithLLM(from:)`
**maxTokens:** 16 / **samplingProfile:** `.extraction`

プロンプト・ロジックともに変更なし。シンプルで安定。

---

## 6c. パラメータ抽出 (JSON) 削除済み

15フィールド一括JSON抽出 → セクション別アプリ側キーワードマッチ方式に置換。
`buildExtractionPrompt`, `extractParameters`, `parseExtractionResponse` すべて削除。
BuddySeed はセクション別の確定値から `buildSeedAndProceed()` で直接構築。
アバターパーツ(bodyId等)はランダム（`makeDefault()` と同じ）。

---

## 6d. Reveal 挨拶生成 変更なし

**ファイル:** `MyBuddy/ViewModels/OnboardingViewModel.swift`
**関数:** `generateGreetings()`
**テンプレート:** `Gemma4PromptBuilder.buildSingleTurn(system:user:)`
**maxTokens:** 64

### 現在のプロンプト全文

**system:**
```
{basePrompt}  <-- 2の出力
```

**user:**
```
{nick}に向けて、reveal画面で最初に見せる一言を作ってください。
意味は「これからよろしくね。一緒に過ごしていこう」に近づけること。
ただし「日記」「記録」「メモ」「アプリ」「設定」「姿」「オンボーディング」などのメタ語は禁止。
名前の自己紹介は不要。ユーザーに向けた自然な呼びかけだけを返してください。
```

### 補足
- フォールバック（`fallbackRevealGreeting`）があるので安全
- `PersonaLineComposer.revealGreeting()` でも決定的な挨拶を生成可能

---

## 7. 挨拶テンプレート（決定的生成） 完了

**ファイル:** `MyBuddy/ViewModels/ChatViewModel.swift:583-609` + `MyBuddy/Models/PersonaLineComposer.swift`
**関数:** `generateLLMGreeting(buddy:isFirstDay:isResume:tomorrowNote:)`
**LLM不使用。** `PersonaLineComposer` による決定的テンプレート生成に完全移行。

### 生成方式

`PersonaLineComposer` が人格アーキタイプ (gentle/cool/bright/mellow/dominant/tsundere) x 関西弁フラグ x 状況から挨拶を決定的に返す。

| 条件 | メソッド | 例 (gentle/標準語) |
|---|---|---|
| 初日 (`isFirstDay && firstDayGreeting が空`) | `firstDayGreeting(nickname:)` | `{nick}、今日はどんな一日だった？` |
| 初日 (`firstDayGreeting が保存済み`) | 保存値をそのまま返す | (オンボーディング時に生成した挨拶) |
| 再開 (`isResume`) | `resumeGreeting(nickname:)` | `{nick}、おかえり。続きから、ゆっくり聞かせて。` |
| 明日メモあり | `dailyGreeting(nickname:timeSlot:tomorrowNote:)` | `{nick}、そういえば「{note}」って言ってたね。どうだった？` |
| 深夜 | `deepNightGreeting(prefix:)` | `{nick}、遅くまでお疲れさま。今日はどんな一日だった？` |
| 朝 | `morningGreeting(prefix:)` | `{nick}、おはよう。今日はここまでどうだった？` |
| 夜 | `eveningGreeting(prefix:)` | `{nick}、こんばんは。今日はどんな一日だった？` |
| その他 | `daytimeGreeting(prefix:)` | `{nick}、今日はここまでどんな感じだった？` |

### 変更点
- 以前: 固定テンプレート + LLM口調変換（`Gemma4PromptBuilder.buildSingleTurn`）
- 現在: LLM不使用。PersonaLineComposer が archetype x 関西弁フラグで分岐し、決定的に挨拶文を返す
- `ProbeLogger` に `deterministic=true` のログを出力

---

## 8. 会話終了メッセージ（決定的生成） 完了

**ファイル:** `MyBuddy/ViewModels/ChatViewModel.swift:613-619` + `MyBuddy/Models/PersonaLineComposer.swift:283-311`
**関数:** `generateClosingMessage(buddy:)` → `PersonaLineComposer.closingLine(nickname:)`
**LLM不使用。** 決定的テンプレート生成。

### 生成方式

`PersonaLineComposer.closingLine(nickname:)` が archetype x 関西弁フラグで分岐:

| archetype | 標準語の例 |
|---|---|
| gentle | `{nick}、今日はここまででいいよ。ゆっくり休んでね。` |
| cool | `{nick}、今日はこのへんにして、もう休もう。` |
| bright | `{nick}、今日はここまでにしよっか！ゆっくり休んでね！` |
| mellow | `{nick}、今日はこのへんでゆるっと終わりにしよ〜。ゆっくり休んでね。` |
| dominant | `{nick}、今日はもう十分よ。続きはまた聞いてあげる。` |
| tsundere | `{nick}、今日はこのへんでいいでしょ。続きはまた聞いてあげる。` |

### 変更点
- 以前: 固定テンプレート + LLM口調変換
- 現在: LLM不使用。PersonaLineComposer で決定的に生成
- 会話終了後は日記モーダルではなく Toast サジェスト表示

---

## 補足: LocalTimeContext の chatTimeHint 全パターン

**ファイル:** `MyBuddy/Services/LocalTimeContext.swift`
**現状: チャットプロンプトの system に注入済み（`ChatResponseService.buildTextSystemPrompt` で使用）**

| 時間帯 | timeSlot | chatTimeHint |
|---|---|---|
| 0:00-4:59 | 深夜 | 深夜なので、今日一日ここまでで実際に何があったかを聞く。現在の行動だけでなく、その日の出来事全体を優先する |
| 5:00-10:59 | 朝 | 朝なので、起きてから今までや昨夜〜今朝に何があったかを聞く。予定よりも、ここまでの出来事を優先する |
| 11:00-16:59 | 昼〜午後 | 昼〜午後なので、午前中から今までに何があったかを聞く。現在の行動だけでなく、今日ここまでの出来事を優先する |
| 17:00-23:59 | 夜 | 夜なので、今日一日ここまでで実際に何があったかを時系列で聞く。現在の行動だけを聞く形は避ける |

---

## 補足: engine パラメータの削除

### LLMEngineKind の完全削除
- `LLMEngineKind.swift` は削除済み
- `Qwen3PromptBuilder.swift` は削除済み
- `coResident` / `switchEngine` / `LoadedEngine` 等は全削除
- `generate` / `generateStream` / `generateWithImage` から `engine:` パラメータが消えた
- probeTag 呼び出しから `engine: .gemma` が除去。`samplingProfile` の `probeTag` 付き呼び出しが直接使われる形に

### LLMServiceFactory の簡素化
```swift
enum LLMServiceFactory {
    @MainActor
    static func makeFromEnvironment() -> any LLMServiceProtocol {
        if AppEnvironment.usesOllamaBackend {
            return OllamaService(configuration: AppEnvironment.ollamaConfiguration)
        }
        return LlamaCppService()
    }
}
```

---

## 補足: GPU分岐

**ファイル:** `MyBuddy/Services/LLMService.swift` (`LlamaCppService.loadModel`)

- `physicalMemGB >= 14.0 && modelSizeGB < physicalMemGB * 0.3` で `gpu_layers=99`（全レイヤー GPU）
- それ以外は `gpu_layers=0`（CPU only）
- `forceCpu=true` または環境変数 `LLM_FORCE_CPU=1` で CPU only を強制
- 中途半端な GPU オフロードは転送バッファでメモリ圧迫するため、全 GPU or CPU only の二択
- Vision 推論後に `cachedTokens.removeAll(keepingCapacity: true)` で KV キャッシュ乖離を防止

---

## 修正チェックリスト

- [x] 2 人格システムプロンプト (`BuddyProfile.buildSystemPrompt`) — v5 構造化セクション・方言ガード
- [x] ~~3 人格再注入アンカー (`BuddyProfile.makePersonaReanchor`)~~ — 削除（`buildPersonaAnchor` は残存）
- [x] 1. チャット応答 — テキスト (`ChatResponseService.buildTextSystemPrompt`) — 8箇条会話方針・締めモード・時刻コンテキスト復活
- [x] 1b. 会話管理 (`ChatViewModel`) — 2回閾値・バディ非質問追跡・Toast サジェスト方式
- [x] 2. チャット応答 — 画像付き (`ChatResponseService.buildImageSystemPrompt`) — テキスト版と統一・画像フォローアップ2ターン制御
- [x] 3. メモ抽出 (`MemoExtractionStage.run`) — フォーマット指示形式・空括弧除去・ダンプログ
- [x] 4. 日記生成 (`ThinkingDiaryStage.run`) — 9ルール・感情2件上限・バディ一言・段落構成・過去形強制
- [x] ~~4b. 日記リライト (`ThinkingDiaryStage.rewriteTranscriptLikeBody`)~~ — 削除
- [x] 5. フォールバック返答生成 (`FallbackReplyGenerator.generate`) — LLM不使用・PersonaLineComposer決定的生成
- [x] 6. オンボーディング会話 (`OnboardingViewModel.buildSectionSystemPrompt`) — セクション制御化+【確定:enum:内容】タグ
- [x] 6b. ニックネーム抽出 (`OnboardingViewModel.extractNicknameWithLLM`) — 変更なし
- [x] ~~6c. パラメータ抽出 (`OnboardingViewModel.buildExtractionPrompt`)~~ — 削除（セクション別確定に置換）
- [x] 6d. Reveal 挨拶生成 (`OnboardingViewModel.generateGreetings`) — 変更なし
- [x] 7. 挨拶テンプレート (`PersonaLineComposer`) — LLM不使用・決定的生成に移行
- [x] 8. 会話終了メッセージ (`PersonaLineComposer.closingLine`) — LLM不使用・決定的生成に移行
- [x] 9. 日記サジェスト Toast (`ChatViewModel.maybeSuggestDiaryOnClosing`) — 新機能
- [x] 補足: LocalTimeContext chatTimeHint — チャット system に注入済み
- [x] 補足: engine パラメータ削除 — LLMEngineKind/Qwen3PromptBuilder 削除済み
- [x] 補足: GPU分岐 — 14GB以上で全GPU、それ以外はCPU only。Vision後cachedTokensクリア
