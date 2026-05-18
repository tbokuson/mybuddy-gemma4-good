import SwiftUI

/// バディのアバターを表示するビュー
/// AI生成ボディ画像 + SwiftUI描画パーツのハイブリッド方式
struct BuddyAvatarView: View {
    let seed: BuddySeed?
    var size: CGFloat = 100
    var showAnimation: Bool = true

    // アニメーション状態
    @State private var isBlinking = false
    @State private var isEureka = false
    @State private var breathScale: CGFloat = 1.0
    @State private var bounceY: CGFloat = 0
    @State private var fishMouthOpen = false
    @State private var blinkTimer: Timer?
    @State private var fishMouthTimer: Timer?
    @State private var eurekaTimer: Timer?

    private var eyeStyle: AvatarEyeStyle {
        guard let seed else { return .sparkle }
        return AvatarEyeStyle.from(seed.eyeId)
    }

    private var mouthStyle: AvatarMouthStyle {
        guard let seed else { return .smile }
        return AvatarMouthStyle.from(seed.mouthId)
    }

    private var earStyle: AvatarEarStyle {
        guard let seed else { return .round }
        return AvatarEarStyle.from(seed.earId)
    }

    private var cheekStyle: AvatarCheekStyle {
        guard let seed else { return .blush }
        let emotionId = seed.accentIds.first(where: { $0.hasPrefix("emotion_") }) ?? ""
        return AvatarCheekStyle.from(emotionId)
    }

    private var characterType: String {
        seed?.characterType ?? "monster"
    }

    private var bodyColor: Color {
        guard let seed else { return AvatarPalette.pastel }
        if characterType == "ojisan" {
            return AvatarPalette.skinColor(for: seed.paletteId)
        }
        if characterType == "fish" {
            // 魚: 赤っぽい（丸魚）/ 青っぽい（細長魚）
            return seed.bodyId == "fish_long"
                ? Color(red: 1.0, green: 0.65, blue: 0.60)     // 赤っぽい
                : Color(red: 0.65, green: 0.78, blue: 1.0)     // 青っぽい
        }
        return AvatarPalette.color(for: seed.paletteId)
    }

    /// 生成画像が左向きの魚（右向きに反転が必要）
    private var fishBodyNeedsFlip: Bool {
        switch seed?.bodyId {
        case "fish_lionfish", "fish_clownfish", "fish_yamame": return true
        default: return false
        }
    }

    /// 魚用グラデーション色
    private var fishGradientColors: [Color] {
        switch seed?.bodyId {
        case "fish_long":
            // 真鯛: ピンク → 淡いピンク白（お腹）
            return [
                Color(red: 1.0, green: 0.42, blue: 0.50),
                Color(red: 1.0, green: 0.78, blue: 0.75)
            ]
        case "fish_lionfish":
            // ミノカサゴ: 赤茶 → クリーム
            return [
                Color(red: 0.80, green: 0.30, blue: 0.25),
                Color(red: 0.95, green: 0.85, blue: 0.70)
            ]
        case "fish_clownfish":
            // カクレクマノミ: オレンジ → 薄オレンジ
            return [
                Color(red: 1.0, green: 0.55, blue: 0.15),
                Color(red: 1.0, green: 0.85, blue: 0.60)
            ]
        case "fish_yamame":
            // ヤマメ: 銀緑 → 白
            return [
                Color(red: 0.35, green: 0.60, blue: 0.50),
                Color(red: 0.90, green: 0.92, blue: 0.85)
            ]
        default:
            // フグ: 濃い青 → ベージュ（お腹）
            return [
                Color(red: 0.30, green: 0.55, blue: 0.95),
                Color(red: 0.95, green: 0.88, blue: 0.75)
            ]
        }
    }

    private var bodyImageName: String {
        guard let seed else { return "BuddyBody" }
        switch characterType {
        case "fish":
            switch seed.bodyId {
            case "fish_long": return "BuddyBodyFishLong"
            case "fish_lionfish": return "BuddyBodyFishLionfish"
            case "fish_clownfish": return "BuddyBodyFishClownfish"
            case "fish_yamame": return "BuddyBodyFishYamame"
            default: return "BuddyBodyFishRound"
            }
        case "ojisan":
            switch seed.bodyId {
            case "ojisan_combover": return "BuddyFaceOjisanCombover"
            case "ojisan_mustache": return "BuddyFaceOjisanMustache"
            case "ojisan_charai": return "BuddyFaceOjisanCharai"
            case "ojisan_keibu": return "BuddyFaceOjisanKeibu"
            case "ojisan_timid": return "BuddyFaceOjisanTimid"
            default: return "BuddyFaceOjisanBaldGlasses"
            }
        default:
            switch seed.bodyId {
            case "chubby": return "BuddyBodyChubby"
            case "fluffy": return "BuddyBodyFluffy"
            default: return "BuddyBody"
            }
        }
    }

    var body: some View {
        ZStack {
            if characterType == "ojisan" {
                // おじさん: 小さな胴体 + 顔画像（口なし）+ SwiftUI口 + 瞬き/ひらめき
                ojisanSmallBody
                    .offset(y: size * 0.25)
                Image(bodyImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * 0.75, height: size * 0.75)
                    .offset(y: -size * 0.08)
                ojisanEyeOverlay
                    .offset(y: -size * 0.08)
                ojisanFaceView
            } else {
                // モンスター / 魚: AI生成画像 + SwiftUI顔パーツ
                if characterType == "fish" {
                    // 魚: グラデーション着色（元画像のディテールを保持しつつ色を差し替え）
                    ZStack {
                        // 元画像（ディテール＝明暗の元）
                        Image(bodyImageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size, height: size)
                        // グラデーションカラー（魚の形にマスク）を .color ブレンドで重ねる
                        // → 元画像の明度を保持しつつ、色相・彩度をグラデーションに置換
                        LinearGradient(
                            colors: fishGradientColors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: size, height: size)
                        .mask(
                            Image(bodyImageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        )
                        .blendMode(.color)
                    }
                    // 生成画像が左向きの魚は右向きに反転
                    .scaleEffect(x: fishBodyNeedsFlip ? -1 : 1, y: 1)
                } else {
                    Image(bodyImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .colorMultiply(bodyColor)
                }

                switch characterType {
                case "fish":
                    fishFaceView
                default:
                    monsterFaceView
                }
            }
        }
        .scaleEffect(breathScale)
        .offset(y: bounceY)
        .onAppear {
            guard showAnimation else { return }
            startBreathing()
            startBlinking()
            startBouncing()
            if characterType == "fish" {
                startFishMouthAnimation()
            }
            if characterType == "ojisan" {
                startEurekaAnimation()
            }
        }
        .onDisappear {
            stopTimers()
        }
    }

    // MARK: - アニメーション

    private func startBreathing() {
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            breathScale = 1.03
        }
    }

    private func startBlinking() {
        guard blinkTimer == nil else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.08)) {
                isBlinking = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.08)) {
                    isBlinking = false
                }
            }
        }
    }

    private func startBouncing() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            bounceY = -4
        }
    }

    private func startFishMouthAnimation() {
        guard fishMouthTimer == nil else { return }
        // 口パク: 1.5〜3秒間隔で口を開閉
        fishMouthTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 1.5...3.0), repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.12)) {
                fishMouthOpen = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                withAnimation(.easeInOut(duration: 0.10)) {
                    fishMouthOpen = false
                }
            }
        }
    }

    private func startEurekaAnimation() {
        guard eurekaTimer == nil else { return }
        // ランダムにひらめき発生（10〜20秒間隔、2秒間光る）
        // 瞬きやバウンスとは独立した特別な動作
        eurekaTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 10...20), repeats: true) { _ in
            withAnimation(.easeIn(duration: 0.1)) {
                isEureka = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.15)) {
                    isEureka = false
                }
            }
        }
    }

    private func stopTimers() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        fishMouthTimer?.invalidate()
        fishMouthTimer = nil
        eurekaTimer?.invalidate()
        eurekaTimer = nil
    }

    // MARK: - タイプ別顔ビュー

    @ViewBuilder
    private var monsterFaceView: some View {
        // 耳/角
        earView
            .offset(y: -size * 0.22)

        // 目
        Group {
            if isBlinking {
                blinkView
            } else {
                eyeView
            }
        }
        .offset(y: -size * 0.08)

        // 口
        mouthView
            .offset(y: size * 0.06)

        // ほっぺ
        cheekView
            .offset(y: size * 0.02)
    }

    /// 魚のbodyIdに応じた形状カテゴリ（目・口の配置決定用）
    private enum FishShape {
        case round      // フグ、クマノミ
        case long       // 真鯛、ヤマメ
        case lionfish   // ミノカサゴ
    }

    private var fishShape: FishShape {
        switch seed?.bodyId {
        case "fish_long", "fish_yamame": return .long
        case "fish_lionfish": return .lionfish
        default: return .round  // fish_round, fish_clownfish
        }
    }

    @ViewBuilder
    private var fishFaceView: some View {
        let shape = fishShape
        let eyeX: CGFloat = {
            switch shape {
            case .long: return size * 0.28
            case .lionfish: return size * 0.24
            case .round: return size * 0.20
            }
        }()

        // 魚の目（側面ビューなので１つだけ、eyeStyleで変化）
        Group {
            if isBlinking {
                RoundedRectangle(cornerRadius: 1)
                    .fill(.black)
                    .frame(width: size * 0.07, height: size * 0.012)
            } else {
                switch eyeStyle {
                case .happy:
                    HappyEyeShape()
                        .stroke(.black, style: StrokeStyle(lineWidth: size * 0.02, lineCap: .round))
                        .frame(width: size * 0.10, height: size * 0.06)
                case .sleepy:
                    SleepyEyeShape()
                        .stroke(.black, style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                        .frame(width: size * 0.10, height: size * 0.05)
                case .heart:
                    Image(systemName: "heart.fill")
                        .font(.system(size: size * 0.10))
                        .foregroundStyle(.pink.opacity(0.8))
                case .star:
                    Image(systemName: "star.fill")
                        .font(.system(size: size * 0.09))
                        .foregroundStyle(.yellow.opacity(0.9))
                case .angry:
                    ZStack {
                        Circle().fill(.black).frame(width: size * 0.07)
                        RoundedRectangle(cornerRadius: 1).fill(.black)
                            .frame(width: size * 0.10, height: size * 0.012)
                            .rotationEffect(.degrees(15))
                            .offset(y: -size * 0.05)
                    }
                case .dizzy:
                    ZStack {
                        RoundedRectangle(cornerRadius: 1).fill(.black)
                            .frame(width: size * 0.08, height: size * 0.014)
                            .rotationEffect(.degrees(45))
                        RoundedRectangle(cornerRadius: 1).fill(.black)
                            .frame(width: size * 0.08, height: size * 0.014)
                            .rotationEffect(.degrees(-45))
                    }
                case .wink:
                    HappyEyeShape()
                        .stroke(.black, style: StrokeStyle(lineWidth: size * 0.02, lineCap: .round))
                        .frame(width: size * 0.10, height: size * 0.06)
                case .big:
                    ZStack {
                        Circle().fill(.white).frame(width: size * 0.14)
                        Circle().fill(.black).frame(width: size * 0.10)
                        Circle().fill(.white).frame(width: size * 0.04)
                            .offset(x: size * 0.015, y: -size * 0.02)
                    }
                case .sparkle:
                    ZStack {
                        Circle().fill(.white).frame(width: size * 0.11)
                        Circle().fill(.black).frame(width: size * 0.07)
                        Circle().fill(.white).frame(width: size * 0.03)
                            .offset(x: size * 0.012, y: -size * 0.015)
                        Circle().fill(.white.opacity(0.6)).frame(width: size * 0.014)
                            .offset(x: -size * 0.015, y: size * 0.012)
                    }
                default: // dot
                    ZStack {
                        Circle().fill(.white).frame(width: size * 0.11)
                        Circle().fill(.black).frame(width: size * 0.07)
                        Circle().fill(.white).frame(width: size * 0.03)
                            .offset(x: size * 0.012, y: -size * 0.015)
                        Circle().fill(.white.opacity(0.5)).frame(width: size * 0.014)
                            .offset(x: -size * 0.015, y: size * 0.012)
                    }
                }
            }
        }
        .offset(x: eyeX, y: -size * 0.04)

        // フグ・クマノミの眉毛
        if shape == .round {
            RoundedRectangle(cornerRadius: size * 0.008)
                .fill(Color.black.opacity(0.45))
                .frame(width: size * 0.09, height: size * 0.014)
                .rotationEffect(.degrees(-8))
                .offset(x: eyeX, y: -size * 0.10)
        }

        // 真鯛装飾: 目の上の青い線 + 側線上の青い点
        if seed?.bodyId == "fish_long" {
            Circle()
                .trim(from: 0.55, to: 0.85)
                .stroke(Color(red: 0.2, green: 0.4, blue: 0.85), lineWidth: size * 0.008)
                .frame(width: size * 0.14, height: size * 0.10)
                .offset(x: eyeX, y: -size * 0.07)

            ForEach(0..<6, id: \.self) { i in
                let t = CGFloat(i)
                let archY: CGFloat = -size * (0.11 - t * 0.010 - t * t * 0.002)
                let dotX: CGFloat = eyeX - size * 0.08 - size * t * 0.065
                Circle()
                    .fill(Color(red: 0.25, green: 0.45, blue: 0.90).opacity(0.65))
                    .frame(width: size * 0.010)
                    .offset(x: dotX, y: archY)
            }
        }

        // ヤマメ装飾: パーマーク（側面に楕円形の暗い斑点）
        if seed?.bodyId == "fish_yamame" {
            ForEach(0..<7, id: \.self) { i in
                let t = CGFloat(i)
                let markX: CGFloat = eyeX - size * 0.06 - size * t * 0.055
                let markY: CGFloat = -size * 0.01
                Ellipse()
                    .fill(Color(red: 0.20, green: 0.35, blue: 0.30).opacity(0.45))
                    .frame(width: size * 0.022, height: size * 0.032)
                    .offset(x: markX, y: markY)
            }
        }

        // 口（魚の口先付近、mouthStyleで変化）
        let mouthX: CGFloat = {
            switch shape {
            case .long: return size * 0.40
            case .lionfish: return size * 0.34
            case .round: return size * 0.36
            }
        }()
        let mouthY: CGFloat = size * 0.02
        Group {
            switch mouthStyle {
            case .open:
                Ellipse()
                    .fill(Color.black.opacity(0.6))
                    .frame(
                        width: size * (fishMouthOpen ? 0.030 : 0.020),
                        height: size * (fishMouthOpen ? 0.025 : 0.006)
                    )
            case .pout:
                SmileShape()
                    .stroke(.black.opacity(0.6), style: StrokeStyle(lineWidth: size * 0.008, lineCap: .round))
                    .frame(width: size * 0.04, height: size * 0.015)
                    .rotationEffect(.degrees(180))
            case .wavy:
                WavyMouthShape()
                    .stroke(.black.opacity(0.6), style: StrokeStyle(lineWidth: size * 0.008, lineCap: .round))
                    .frame(width: size * 0.05, height: size * 0.012)
            case .flat:
                RoundedRectangle(cornerRadius: 1)
                    .fill(.black.opacity(0.5))
                    .frame(width: size * 0.04, height: size * 0.006)
            default: // smile
                SmileShape()
                    .stroke(.black.opacity(0.6), style: StrokeStyle(lineWidth: size * 0.008, lineCap: .round))
                    .frame(width: size * 0.04, height: size * 0.018)
            }
        }
        .offset(x: mouthX, y: mouthY)

    }

    // MARK: - おじさん瞬き・ひらめき

    /// おじさんタイプ別の目/メガネレンズ位置（顔画像 size*0.75 基準）
    private struct OjisanEyeLayout {
        let leftCenter: (x: CGFloat, y: CGFloat)   // 左目中心（画像座標比率）
        let rightCenter: (x: CGFloat, y: CGFloat)   // 右目中心
        let lensW: CGFloat                           // レンズ幅比率
        let lensH: CGFloat                           // レンズ高さ比率
        let isRound: Bool                            // 丸メガネか四角か
        let skinColor: Color                         // 肌色（瞬き用）
    }

    private var ojisanEyeLayout: OjisanEyeLayout {
        switch seed?.bodyId {
        case "ojisan_combover":
            // 七三分け: 四角メガネ、やや下寄り
            return OjisanEyeLayout(
                leftCenter: (x: -0.12, y: 0.02),
                rightCenter: (x: 0.12, y: 0.02),
                lensW: 0.15, lensH: 0.10,
                isRound: false,
                skinColor: Color(red: 0.90, green: 0.76, blue: 0.62)
            )
        case "ojisan_mustache":
            // ヒゲ＋金メガネ: 丸メガネ、やや上寄り
            return OjisanEyeLayout(
                leftCenter: (x: -0.12, y: -0.04),
                rightCenter: (x: 0.12, y: -0.04),
                lensW: 0.16, lensH: 0.15,
                isRound: true,
                skinColor: Color(red: 0.92, green: 0.80, blue: 0.66)
            )
        case "ojisan_charai":
            // チャラい: 色サングラス（大きめ横長レンズ）
            return OjisanEyeLayout(
                leftCenter: (x: -0.14, y: 0.0),
                rightCenter: (x: 0.14, y: 0.0),
                lensW: 0.18, lensH: 0.10,
                isRound: false,
                skinColor: Color(red: 0.70, green: 0.52, blue: 0.38)
            )
        case "ojisan_keibu":
            // 警部: 四角メガネ
            return OjisanEyeLayout(
                leftCenter: (x: -0.12, y: 0.0),
                rightCenter: (x: 0.12, y: 0.0),
                lensW: 0.14, lensH: 0.10,
                isRound: false,
                skinColor: Color(red: 0.90, green: 0.76, blue: 0.62)
            )
        case "ojisan_timid":
            // 気弱: 大きい丸メガネ
            return OjisanEyeLayout(
                leftCenter: (x: -0.13, y: 0.0),
                rightCenter: (x: 0.13, y: 0.0),
                lensW: 0.18, lensH: 0.17,
                isRound: true,
                skinColor: Color(red: 0.95, green: 0.85, blue: 0.75)
            )
        default:
            // ハゲ＋丸メガネ（波平）: 丸メガネ、中央やや上
            return OjisanEyeLayout(
                leftCenter: (x: -0.13, y: 0.0),
                rightCenter: (x: 0.13, y: 0.0),
                lensW: 0.17, lensH: 0.16,
                isRound: true,
                skinColor: Color(red: 0.92, green: 0.78, blue: 0.65)
            )
        }
    }

    /// おじさんの目の上に重ねるオーバーレイ（瞬き＋ひらめき）
    /// サイズを固定して、状態切り替え時のレイアウトガタつきを防止する
    @ViewBuilder
    private var ojisanEyeOverlay: some View {
        let layout = ojisanEyeLayout
        let faceSize = size * 0.75

        ZStack {
        if isEureka {
            // ひらめき: メガネレンズが真っ白に光る
            ojisanLensShape(layout: layout, faceSize: faceSize, isLeft: true)
                .fill(.white)
                .shadow(color: .white.opacity(0.8), radius: size * 0.03)
            ojisanLensShape(layout: layout, faceSize: faceSize, isLeft: false)
                .fill(.white)
                .shadow(color: .white.opacity(0.8), radius: size * 0.03)
            // キュピーン！フラッシュ（右レンズの右上）
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.06, weight: .bold))
                .foregroundStyle(.yellow)
                .shadow(color: .yellow.opacity(0.6), radius: size * 0.01)
                .offset(
                    x: faceSize * layout.rightCenter.x + faceSize * layout.lensW * 0.5,
                    y: faceSize * layout.rightCenter.y - faceSize * layout.lensH * 0.5
                )
        } else if isBlinking {
            // 瞬き: レンズ内を肌色で塗りつぶし → 閉じ目の線
            ojisanLensShape(layout: layout, faceSize: faceSize, isLeft: true)
                .fill(layout.skinColor)
            ojisanLensShape(layout: layout, faceSize: faceSize, isLeft: false)
                .fill(layout.skinColor)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.black.opacity(0.5))
                .frame(width: faceSize * layout.lensW * 0.6, height: size * 0.008)
                .offset(x: faceSize * layout.leftCenter.x, y: faceSize * layout.leftCenter.y)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.black.opacity(0.5))
                .frame(width: faceSize * layout.lensW * 0.6, height: size * 0.008)
                .offset(x: faceSize * layout.rightCenter.x, y: faceSize * layout.rightCenter.y)
        } else if eyeStyle != .dot && eyeStyle != .sparkle {
            // 表情バリエーション: レンズ内を肌色で塗りつぶし → アイコンオーバーレイ
            ojisanLensShape(layout: layout, faceSize: faceSize, isLeft: true)
                .fill(layout.skinColor)
            ojisanLensShape(layout: layout, faceSize: faceSize, isLeft: false)
                .fill(layout.skinColor)
            // 左目
            ojisanExpressionEye(eyeStyle: eyeStyle, size: faceSize * layout.lensW * 0.5)
                .offset(x: faceSize * layout.leftCenter.x, y: faceSize * layout.leftCenter.y)
            // 右目
            ojisanExpressionEye(eyeStyle: eyeStyle, size: faceSize * layout.lensW * 0.5)
                .offset(x: faceSize * layout.rightCenter.x, y: faceSize * layout.rightCenter.y)
        }
        }
        .frame(width: faceSize, height: faceSize)
        .clipped()
    }

    /// レンズ形状（丸 or 四角）を返すヘルパー
    private func ojisanLensShape(layout: OjisanEyeLayout, faceSize: CGFloat, isLeft: Bool) -> some Shape {
        let center = isLeft ? layout.leftCenter : layout.rightCenter
        let w = faceSize * layout.lensW
        let h = faceSize * layout.lensH
        let x = faceSize * center.x - w / 2
        let y = faceSize * center.y - h / 2
        let rect = CGRect(x: x, y: y, width: w, height: h)

        if layout.isRound {
            return OjisanLensPath(rect: rect, isRound: true)
        } else {
            return OjisanLensPath(rect: rect, isRound: false)
        }
    }

    /// おじさん用の表情目（メガネレンズ内に描画）
    @ViewBuilder
    private func ojisanExpressionEye(eyeStyle: AvatarEyeStyle, size s: CGFloat) -> some View {
        switch eyeStyle {
        case .happy:
            HappyEyeShape()
                .stroke(.black, style: StrokeStyle(lineWidth: s * 0.15, lineCap: .round))
                .frame(width: s, height: s * 0.5)
        case .sleepy:
            SleepyEyeShape()
                .stroke(.black, style: StrokeStyle(lineWidth: s * 0.12, lineCap: .round))
                .frame(width: s, height: s * 0.4)
        case .heart:
            Image(systemName: "heart.fill")
                .font(.system(size: s * 0.8))
                .foregroundStyle(.pink.opacity(0.8))
        case .star:
            Image(systemName: "star.fill")
                .font(.system(size: s * 0.7))
                .foregroundStyle(.yellow.opacity(0.9))
        case .angry:
            ZStack {
                Circle().fill(.black).frame(width: s * 0.5)
                RoundedRectangle(cornerRadius: 1).fill(.black)
                    .frame(width: s * 0.8, height: s * 0.1)
                    .rotationEffect(.degrees(15))
                    .offset(y: -s * 0.4)
            }
        case .dizzy:
            ZStack {
                RoundedRectangle(cornerRadius: 1).fill(.black)
                    .frame(width: s * 0.7, height: s * 0.1).rotationEffect(.degrees(45))
                RoundedRectangle(cornerRadius: 1).fill(.black)
                    .frame(width: s * 0.7, height: s * 0.1).rotationEffect(.degrees(-45))
            }
        case .wink:
            HappyEyeShape()
                .stroke(.black, style: StrokeStyle(lineWidth: s * 0.15, lineCap: .round))
                .frame(width: s, height: s * 0.5)
        case .big:
            ZStack {
                Circle().fill(.black).frame(width: s * 0.7)
                Circle().fill(.white).frame(width: s * 0.25)
                    .offset(x: s * 0.1, y: -s * 0.1)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var ojisanFaceView: some View {
        // 口（SwiftUI描画 — 表情に応じて変化）
        Group {
            switch mouthStyle {
            case .open:
                Ellipse()
                    .fill(.black.opacity(0.6))
                    .frame(width: size * 0.05, height: size * 0.04)
            case .pout:
                SmileShape()
                    .stroke(.black.opacity(0.6), style: StrokeStyle(lineWidth: size * 0.01, lineCap: .round))
                    .frame(width: size * 0.06, height: size * 0.02)
                    .rotationEffect(.degrees(180))
            case .wavy:
                WavyMouthShape()
                    .stroke(.black.opacity(0.6), style: StrokeStyle(lineWidth: size * 0.01, lineCap: .round))
                    .frame(width: size * 0.08, height: size * 0.02)
            case .flat:
                RoundedRectangle(cornerRadius: 1)
                    .fill(.black.opacity(0.5))
                    .frame(width: size * 0.06, height: size * 0.008)
            default:
                SmileShape()
                    .stroke(.black.opacity(0.6), style: StrokeStyle(lineWidth: size * 0.01, lineCap: .round))
                    .frame(width: size * 0.08, height: size * 0.03)
            }
        }
        .offset(y: seed?.bodyId == "ojisan_combover" ? size * 0.07 : size * 0.03)
    }

    /// おじさん用の小さな胴体（サラリーマン風）
    private let ojisanSkinColor = Color(red: 0.92, green: 0.78, blue: 0.65)
    private let ojisanShirtColor = Color(red: 0.88, green: 0.91, blue: 0.95) // 薄い水色ワイシャツ
    private let ojisanPantsColor = Color(red: 0.35, green: 0.35, blue: 0.40) // グレーズボン

    /// ネクタイ色（paletteIdで変化）
    private var ojisanTieColor: Color {
        switch seed?.paletteId {
        case "warm":  return Color(red: 0.75, green: 0.20, blue: 0.18)  // 赤ネクタイ
        case "cool":  return Color(red: 0.15, green: 0.15, blue: 0.35)  // 紺ネクタイ
        case "earth": return Color(red: 0.45, green: 0.30, blue: 0.15)  // 茶ネクタイ
        default:      return Color(red: 0.20, green: 0.35, blue: 0.20)  // 緑ネクタイ
        }
    }

    private var ojisanSmallBody: some View {
        ZStack {
            // 腕（袖 + 手）
            HStack(spacing: size * 0.22) {
                // 左腕
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: size * 0.015)
                        .fill(ojisanShirtColor)
                        .frame(width: size * 0.05, height: size * 0.055)
                    // 手（肌色）
                    Circle()
                        .fill(ojisanSkinColor)
                        .frame(width: size * 0.04, height: size * 0.04)
                }
                .rotationEffect(.degrees(15))
                // 右腕
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: size * 0.015)
                        .fill(ojisanShirtColor)
                        .frame(width: size * 0.05, height: size * 0.055)
                    Circle()
                        .fill(ojisanSkinColor)
                        .frame(width: size * 0.04, height: size * 0.04)
                }
                .rotationEffect(.degrees(-15))
            }
            .offset(y: -size * 0.02)

            // 上半身: ワイシャツ + 下半身: ズボン + 脚 + 靴（一体）
            VStack(spacing: 0) {
                // ワイシャツ
                RoundedRectangle(cornerRadius: size * 0.025)
                    .fill(ojisanShirtColor)
                    .frame(width: size * 0.28, height: size * 0.10)

                // ズボン胴部分
                RoundedRectangle(cornerRadius: size * 0.008)
                    .fill(ojisanPantsColor)
                    .frame(width: size * 0.26, height: size * 0.03)

                // ズボン脚（2本に分かれる）
                HStack(spacing: size * 0.02) {
                    RoundedRectangle(cornerRadius: size * 0.008)
                        .fill(ojisanPantsColor)
                        .frame(width: size * 0.055, height: size * 0.05)
                    RoundedRectangle(cornerRadius: size * 0.008)
                        .fill(ojisanPantsColor)
                        .frame(width: size * 0.055, height: size * 0.05)
                }

                // 靴
                HStack(spacing: size * 0.015) {
                    RoundedRectangle(cornerRadius: size * 0.006)
                        .fill(Color(red: 0.25, green: 0.2, blue: 0.15))
                        .frame(width: size * 0.06, height: size * 0.02)
                    RoundedRectangle(cornerRadius: size * 0.006)
                        .fill(Color(red: 0.25, green: 0.2, blue: 0.15))
                        .frame(width: size * 0.06, height: size * 0.02)
                }
            }

            // ネクタイ（結び目 + 本体 + 先端）
            VStack(spacing: 0) {
                NecktiKnotShape()
                    .fill(ojisanTieColor)
                    .frame(width: size * 0.03, height: size * 0.018)
                NecktieBodyShape()
                    .fill(ojisanTieColor)
                    .frame(width: size * 0.035, height: size * 0.065)
            }
            .offset(y: -size * 0.025)
        }
    }

    private var blinkView: some View {
        HStack(spacing: size * 0.14) {
            RoundedRectangle(cornerRadius: 1)
                .fill(.black)
                .frame(width: size * 0.07, height: size * 0.012)
            RoundedRectangle(cornerRadius: 1)
                .fill(.black)
                .frame(width: size * 0.07, height: size * 0.012)
        }
    }

    // MARK: - おじさん（装飾なし — ハゲ固定）

    /// 波平風サイドヘア（頭の両サイドにちょっとだけ髪）
    private var ojisanSideHair: some View {
        let hairColor = Color(red: 0.25, green: 0.22, blue: 0.20)
        let faceW = size * 0.75
        return HStack(spacing: faceW * 0.85) {
            // 左サイド — 耳の上あたりに半月状の髪
            SideHairShape()
                .fill(hairColor)
                .frame(width: size * 0.10, height: size * 0.14)
                .scaleEffect(x: -1)
            // 右サイド
            SideHairShape()
                .fill(hairColor)
                .frame(width: size * 0.10, height: size * 0.14)
        }
        .offset(y: -size * 0.02)
    }

    // MARK: - 目

    @ViewBuilder
    private var eyeView: some View {
        let eyeSize = size * 0.06
        let spacing = size * 0.14

        HStack(spacing: spacing) {
            switch eyeStyle {
            case .dot:
                ForEach(0..<2, id: \.self) { _ in
                    Circle()
                        .fill(.black)
                        .frame(width: eyeSize, height: eyeSize)
                }
            case .sparkle:
                ForEach(0..<2, id: \.self) { _ in
                    ZStack {
                        Circle()
                            .fill(.black)
                            .frame(width: eyeSize * 1.4, height: eyeSize * 1.4)
                        Circle()
                            .fill(.white)
                            .frame(width: eyeSize * 0.5, height: eyeSize * 0.5)
                            .offset(x: eyeSize * 0.15, y: -eyeSize * 0.2)
                        Circle()
                            .fill(.white.opacity(0.6))
                            .frame(width: eyeSize * 0.25, height: eyeSize * 0.25)
                            .offset(x: -eyeSize * 0.2, y: eyeSize * 0.2)
                    }
                }
            case .happy:
                ForEach(0..<2, id: \.self) { _ in
                    HappyEyeShape()
                        .stroke(.black, style: StrokeStyle(lineWidth: size * 0.02, lineCap: .round))
                        .frame(width: eyeSize * 1.6, height: eyeSize * 0.9)
                }
            case .sleepy:
                ForEach(0..<2, id: \.self) { _ in
                    SleepyEyeShape()
                        .stroke(.black, style: StrokeStyle(lineWidth: size * 0.018, lineCap: .round))
                        .frame(width: eyeSize * 1.5, height: eyeSize * 0.8)
                }
            case .wink:
                ZStack {
                    Circle()
                        .fill(.black)
                        .frame(width: eyeSize * 1.4, height: eyeSize * 1.4)
                    Circle()
                        .fill(.white)
                        .frame(width: eyeSize * 0.5, height: eyeSize * 0.5)
                        .offset(x: eyeSize * 0.15, y: -eyeSize * 0.2)
                }
                HappyEyeShape()
                    .stroke(.black, style: StrokeStyle(lineWidth: size * 0.02, lineCap: .round))
                    .frame(width: eyeSize * 1.6, height: eyeSize * 0.9)

            case .big:
                // 大きなまん丸目
                ForEach(0..<2, id: \.self) { _ in
                    ZStack {
                        Circle()
                            .fill(.black)
                            .frame(width: eyeSize * 2.0, height: eyeSize * 2.0)
                        Circle()
                            .fill(.white)
                            .frame(width: eyeSize * 0.7, height: eyeSize * 0.7)
                            .offset(x: eyeSize * 0.2, y: -eyeSize * 0.3)
                        Circle()
                            .fill(.white.opacity(0.5))
                            .frame(width: eyeSize * 0.35, height: eyeSize * 0.35)
                            .offset(x: -eyeSize * 0.25, y: eyeSize * 0.25)
                    }
                }

            case .heart:
                // ハート目
                ForEach(0..<2, id: \.self) { _ in
                    Image(systemName: "heart.fill")
                        .font(.system(size: eyeSize * 1.8))
                        .foregroundStyle(.pink.opacity(0.8))
                }

            case .star:
                // 星目
                ForEach(0..<2, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: eyeSize * 1.6))
                        .foregroundStyle(.yellow.opacity(0.9))
                }

            case .angry:
                // 怒り目（v字眉 + 目）
                ForEach(0..<2, id: \.self) { i in
                    ZStack {
                        Circle()
                            .fill(.black)
                            .frame(width: eyeSize * 1.2, height: eyeSize * 1.2)
                        // 眉
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.black)
                            .frame(width: eyeSize * 1.8, height: size * 0.015)
                            .rotationEffect(.degrees(i == 0 ? 15 : -15))
                            .offset(y: -eyeSize * 1.0)
                    }
                }

            case .dizzy:
                // ぐるぐる目（×マーク）
                ForEach(0..<2, id: \.self) { _ in
                    ZStack {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.black)
                            .frame(width: eyeSize * 1.6, height: size * 0.018)
                            .rotationEffect(.degrees(45))
                        RoundedRectangle(cornerRadius: 1)
                            .fill(.black)
                            .frame(width: eyeSize * 1.6, height: size * 0.018)
                            .rotationEffect(.degrees(-45))
                    }
                }
            }
        }
    }

    // MARK: - 口

    @ViewBuilder
    private var mouthView: some View {
        let mouthW = size * 0.10
        let mouthH = size * 0.05

        switch mouthStyle {
        case .smile:
            SmileShape()
                .stroke(.black.opacity(0.8), style: StrokeStyle(lineWidth: size * 0.015, lineCap: .round))
                .frame(width: mouthW, height: mouthH)

        case .open:
            Ellipse()
                .fill(.black.opacity(0.7))
                .frame(width: mouthW * 0.5, height: mouthH * 0.7)

        case .pout:
            // むっとした口（逆アーチ）
            SmileShape()
                .stroke(.black.opacity(0.8), style: StrokeStyle(lineWidth: size * 0.015, lineCap: .round))
                .frame(width: mouthW * 0.7, height: mouthH * 0.6)
                .rotationEffect(.degrees(180))

        case .wavy:
            // にょろにょろ口
            WavyMouthShape()
                .stroke(.black.opacity(0.8), style: StrokeStyle(lineWidth: size * 0.015, lineCap: .round))
                .frame(width: mouthW * 1.2, height: mouthH * 0.6)

        case .flat:
            // 一文字口
            RoundedRectangle(cornerRadius: 1)
                .fill(.black.opacity(0.7))
                .frame(width: mouthW * 0.8, height: size * 0.012)
        }
    }

    // MARK: - 耳/角

    @ViewBuilder
    private var earView: some View {
        let e = size * 0.14  // ベース耳サイズ（大きめ）

        HStack(spacing: size * 0.32) {
            switch earStyle {
            case .horns:
                // 小さなツノ
                HornShape()
                    .fill(bodyColor.opacity(0.7))
                    .frame(width: e * 0.7, height: e * 1.1)
                    .rotationEffect(.degrees(-12))
                HornShape()
                    .fill(bodyColor.opacity(0.7))
                    .frame(width: e * 0.7, height: e * 1.1)
                    .rotationEffect(.degrees(12))

            case .round:
                // 丸耳（小さめ、左右に開く）
                ZStack {
                    Ellipse()
                        .fill(bodyColor.opacity(0.8))
                        .frame(width: e * 1.1, height: e * 0.9)
                    Ellipse()
                        .fill(bodyColor.opacity(0.4))
                        .frame(width: e * 0.55, height: e * 0.45)
                }
                .rotationEffect(.degrees(-25))
                ZStack {
                    Ellipse()
                        .fill(bodyColor.opacity(0.8))
                        .frame(width: e * 1.1, height: e * 0.9)
                    Ellipse()
                        .fill(bodyColor.opacity(0.4))
                        .frame(width: e * 0.55, height: e * 0.45)
                }
                .rotationEffect(.degrees(25))

            case .pointed:
                // 尖り耳（横に大きく）
                PointedEarShape()
                    .fill(bodyColor.opacity(0.8))
                    .frame(width: e * 1.2, height: e * 1.5)
                    .rotationEffect(.degrees(-20))
                PointedEarShape()
                    .fill(bodyColor.opacity(0.8))
                    .frame(width: e * 1.2, height: e * 1.5)
                    .scaleEffect(x: -1)
                    .rotationEffect(.degrees(20))

            case .floppy:
                // 垂れ耳（ヨーダ風 — 横に長く垂れる）
                Ellipse()
                    .fill(bodyColor.opacity(0.8))
                    .frame(width: e * 2.2, height: e * 0.7)
                    .rotationEffect(.degrees(-15))
                    .offset(y: e * 0.4)
                Ellipse()
                    .fill(bodyColor.opacity(0.8))
                    .frame(width: e * 2.2, height: e * 0.7)
                    .rotationEffect(.degrees(15))
                    .offset(y: e * 0.4)

            case .bigRound:
                // 大きな丸耳（テディベア風、横に張り出す）
                ForEach(0..<2, id: \.self) { _ in
                    ZStack {
                        Ellipse()
                            .fill(bodyColor.opacity(0.8))
                            .frame(width: e * 1.8, height: e * 1.5)
                        Ellipse()
                            .fill(bodyColor.opacity(0.4))
                            .frame(width: e * 1.0, height: e * 0.8)
                    }
                }

            case .droopy:
                // 大きな垂れ耳（犬風 — 横にだらんと）
                Ellipse()
                    .fill(bodyColor.opacity(0.8))
                    .frame(width: e * 1.8, height: e * 0.9)
                    .rotationEffect(.degrees(-25))
                    .offset(y: e * 0.6)
                Ellipse()
                    .fill(bodyColor.opacity(0.8))
                    .frame(width: e * 1.8, height: e * 0.9)
                    .rotationEffect(.degrees(25))
                    .offset(y: e * 0.6)

            case .bat:
                // コウモリ風（大きく横に広がる尖り耳）
                BatEarShape()
                    .fill(bodyColor.opacity(0.8))
                    .frame(width: e * 1.6, height: e * 1.8)
                    .rotationEffect(.degrees(-12))
                BatEarShape()
                    .fill(bodyColor.opacity(0.8))
                    .frame(width: e * 1.6, height: e * 1.8)
                    .scaleEffect(x: -1)
                    .rotationEffect(.degrees(12))

            case .cat:
                // 猫耳（大きめ三角 + 内側ピンク）
                ZStack {
                    PointedEarShape()
                        .fill(bodyColor.opacity(0.8))
                        .frame(width: e * 1.3, height: e * 1.6)
                    PointedEarShape()
                        .fill(Color.pink.opacity(0.2))
                        .frame(width: e * 0.7, height: e * 0.9)
                        .offset(y: e * 0.18)
                }
                .rotationEffect(.degrees(-18))
                ZStack {
                    PointedEarShape()
                        .fill(bodyColor.opacity(0.8))
                        .frame(width: e * 1.3, height: e * 1.6)
                    PointedEarShape()
                        .fill(Color.pink.opacity(0.2))
                        .frame(width: e * 0.7, height: e * 0.9)
                        .offset(y: e * 0.18)
                }
                .scaleEffect(x: -1)
                .rotationEffect(.degrees(18))
            }
        }
    }

    // MARK: - ほっぺ

    @ViewBuilder
    private var cheekView: some View {
        let cheekSize = size * 0.06

        switch cheekStyle {
        case .blush:
            HStack(spacing: size * 0.24) {
                Circle().fill(Color.pink.opacity(0.3)).frame(width: cheekSize, height: cheekSize)
                Circle().fill(Color.pink.opacity(0.3)).frame(width: cheekSize, height: cheekSize)
            }
        case .stars:
            HStack(spacing: size * 0.26) {
                Image(systemName: "star.fill")
                    .font(.system(size: cheekSize * 0.7))
                    .foregroundStyle(.yellow.opacity(0.6))
                Image(systemName: "star.fill")
                    .font(.system(size: cheekSize * 0.7))
                    .foregroundStyle(.yellow.opacity(0.6))
            }
        case .none:
            EmptyView()
        }
    }
}

// MARK: - パーツ種別 enum

enum AvatarEyeStyle: String, CaseIterable {
    // 通常時
    case dot
    // アニメーション用（表情変化）
    case sparkle, happy, sleepy, wink, big
    case heart, star, angry, dizzy

    static func from(_ seedId: String) -> Self {
        switch seedId {
        case "dot", "round": .dot
        case "sparkle": .sparkle
        case "happy": .happy
        case "sleepy": .sleepy
        case "wink": .wink
        case "big": .big
        case "heart": .heart
        case "star": .star
        case "angry": .angry
        case "dizzy": .dizzy
        default: .dot
        }
    }
}

enum AvatarMouthStyle: String, CaseIterable {
    // 通常時
    case smile, open
    // アニメーション用（表情変化）
    case pout, wavy, flat

    static func from(_ seedId: String) -> Self {
        switch seedId {
        case "smile", "small": .smile
        case "open": .open
        case "pout": .pout
        case "wavy": .wavy
        case "flat": .flat
        default: .smile
        }
    }
}

enum AvatarEarStyle: String, CaseIterable {
    case horns, round, pointed, floppy, bigRound, droopy, bat, cat

    static func from(_ seedId: String) -> Self {
        switch seedId {
        case "horns", "tiny": .horns
        case "round": .round
        case "pointed": .pointed
        case "floppy": .floppy
        case "big_round": .bigRound
        case "droopy": .droopy
        case "bat": .bat
        case "cat": .cat
        default: .round
        }
    }
}

enum AvatarCheekStyle: String, CaseIterable {
    case none, blush, stars

    static func from(_ emotionId: String) -> Self {
        switch emotionId {
        case "emotion_warm", "emotion_mellow": .blush
        case "emotion_energetic": .stars
        case "emotion_cool": .none
        default: .blush
        }
    }
}

enum AvatarPalette {
    static let warm = Color(red: 0.95, green: 0.82, blue: 0.68)
    static let cool = Color(red: 0.7, green: 0.84, blue: 0.95)
    static let pastel = Color(red: 0.7, green: 0.9, blue: 0.8)
    static let earth = Color(red: 0.82, green: 0.78, blue: 0.7)

    static func color(for paletteId: String) -> Color {
        switch paletteId {
        case "warm": warm
        case "cool": cool
        case "pastel": pastel
        case "earth": earth
        default: pastel
        }
    }

    // おじさん用肌色パレット
    static func skinColor(for paletteId: String) -> Color {
        switch paletteId {
        case "warm": Color(red: 0.96, green: 0.87, blue: 0.78)   // 暖かい肌色
        case "cool": Color(red: 0.90, green: 0.85, blue: 0.82)   // 明るい肌色
        case "pastel": Color(red: 0.95, green: 0.88, blue: 0.80)  // 標準肌色
        case "earth": Color(red: 0.88, green: 0.78, blue: 0.68)   // 日焼け肌色
        default: Color(red: 0.95, green: 0.88, blue: 0.80)
        }
    }
}

// MARK: - カスタムShape

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.maxY)
            )
        }
    }
}

private struct HappyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.midX, y: rect.minY)
            )
        }
    }
}

private struct SleepyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.midY),
                control: CGPoint(x: rect.midX, y: rect.minY)
            )
        }
    }
}

private struct FangShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

private struct WavyMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addQuadCurve(
                to: CGPoint(x: rect.width * 0.33, y: rect.midY),
                control: CGPoint(x: rect.width * 0.17, y: rect.minY)
            )
            p.addQuadCurve(
                to: CGPoint(x: rect.width * 0.66, y: rect.midY),
                control: CGPoint(x: rect.width * 0.5, y: rect.maxY)
            )
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.midY),
                control: CGPoint(x: rect.width * 0.83, y: rect.minY)
            )
        }
    }
}

private struct CatMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.maxY),
                control: CGPoint(x: rect.width * 0.25, y: rect.maxY)
            )
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.width * 0.75, y: rect.maxY)
            )
        }
    }
}

private struct HornShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control: CGPoint(x: rect.minX, y: rect.midY)
            )
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.minY),
                control: CGPoint(x: rect.maxX, y: rect.midY)
            )
        }
    }
}

private struct BatEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            // 下辺の中央から左上、頂点、右上を経由
            p.move(to: CGPoint(x: rect.midX - rect.width * 0.15, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.height * 0.3),
                control: CGPoint(x: rect.minX - rect.width * 0.1, y: rect.height * 0.7)
            )
            p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.3))
            p.addQuadCurve(
                to: CGPoint(x: rect.midX + rect.width * 0.15, y: rect.maxY),
                control: CGPoint(x: rect.maxX + rect.width * 0.1, y: rect.height * 0.7)
            )
            p.closeSubpath()
        }
    }
}

private struct PointedEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.midY)
            )
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.midY)
            )
        }
    }
}

// MARK: - おじさんレンズ用Shape

/// おじさんメガネレンズの形状（オフセット付きで指定位置に描画）
private struct OjisanLensPath: Shape {
    let rect: CGRect
    let isRound: Bool

    func path(in bounds: CGRect) -> Path {
        // boundsの中心を原点として、rectの位置にレンズを描画
        let cx = bounds.midX + rect.origin.x
        let cy = bounds.midY + rect.origin.y
        let drawRect = CGRect(x: cx, y: cy, width: rect.width, height: rect.height)

        if isRound {
            return Path(ellipseIn: drawRect)
        } else {
            return Path(roundedRect: drawRect, cornerRadius: rect.height * 0.15)
        }
    }
}

// MARK: - 波平サイドヘア用Shape

/// 耳の上にかぶさる半月状の髪（右向き）
private struct SideHairShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            // 右に膨らむ半月
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.midY)
            )
            p.closeSubpath()
        }
    }
}

// MARK: - ネクタイ用Shape

/// ネクタイ結び目（小さな逆三角形）
private struct NecktiKnotShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// ネクタイ本体（上が細く下が少し広がって先端が三角）
private struct NecktieBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            let topW = rect.width * 0.35
            let midW = rect.width * 0.55
            let midY = rect.height * 0.75
            // 上部（細い）
            p.move(to: CGPoint(x: rect.midX - topW / 2, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX + topW / 2, y: rect.minY))
            // 少し広がりながら下へ
            p.addLine(to: CGPoint(x: rect.midX + midW / 2, y: midY))
            // 先端（三角）
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX - midW / 2, y: midY))
            p.closeSubpath()
        }
    }
}

// MARK: - おじさん用Shape

private struct HairCombShape: Shape {
    // 七三分け髪
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addQuadCurve(
                to: CGPoint(x: rect.width * 0.3, y: rect.minY),
                control: CGPoint(x: rect.minX, y: rect.height * 0.3)
            )
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY),
                control: CGPoint(x: rect.width * 0.7, y: rect.height * 0.2)
            )
            p.closeSubpath()
        }
    }
}

private struct HairMessyShape: Shape {
    // ボサボサ髪
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.width * 0.05, y: rect.height * 0.4))
            p.addLine(to: CGPoint(x: rect.width * 0.15, y: rect.height * 0.6))
            p.addLine(to: CGPoint(x: rect.width * 0.25, y: rect.height * 0.15))
            p.addLine(to: CGPoint(x: rect.width * 0.35, y: rect.height * 0.5))
            p.addLine(to: CGPoint(x: rect.width * 0.5, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.width * 0.65, y: rect.height * 0.5))
            p.addLine(to: CGPoint(x: rect.width * 0.75, y: rect.height * 0.15))
            p.addLine(to: CGPoint(x: rect.width * 0.85, y: rect.height * 0.6))
            p.addLine(to: CGPoint(x: rect.width * 0.95, y: rect.height * 0.4))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

private struct HatShape: Shape {
    // 帽子
    func path(in rect: CGRect) -> Path {
        Path { p in
            // つば
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.75))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.75))
            p.closeSubpath()
            // 本体
            p.move(to: CGPoint(x: rect.width * 0.15, y: rect.height * 0.75))
            p.addQuadCurve(
                to: CGPoint(x: rect.width * 0.85, y: rect.height * 0.75),
                control: CGPoint(x: rect.midX, y: rect.minY)
            )
            p.closeSubpath()
        }
    }
}
