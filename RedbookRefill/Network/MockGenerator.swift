//
//  MockGenerator.swift
//  RedPulse
//
//  Local mock of the generation API. Mirrors prototype `mockGenerateResult()`:
//  - extracts a short product name (≤8 chars) from the keyword's first token
//  - picks ad-type-specific templates at random
//  - simulates 1.5s latency for full generation, 1.0s for single-field
//

import Foundation

final class MockGenerator: GeneratorProtocol {

    // MARK: - GeneratorProtocol

    func generate(_ req: GenerateRequest) async throws -> GenerateResponse {
        try await sleep(seconds: 1.5)
        let pn = productName(from: req.keyword, product: req.product)
        let pack = TemplatePack.pick(for: req.adType)
        let debugPrompt = """
            [文生文提示词]
            你是一个小红书文案专家。产品：\(pn)
            广告类型：\(req.adType.displayName)
            关键词：\(req.keyword)\(req.keywordHint.map { "\n风格提示：\($0)" } ?? "")

            请根据以上信息生成一篇小红书笔记，包含标题、正文、标签。
            """

        return GenerateResponse(
            hotScore: Int.random(in: 78...94),
            suggestion: pack.suggestion(pn: pn),
            noteTitle: pack.title(pn: pn),
            content: pack.content(pn: pn),
            tags: pack.tags(pn: pn),
            imageSuggestion: pack.imageSuggestion(pn: pn),
            imagePrompt: pack.imagePrompt(pn: pn),
            videoPrompt: "smooth camera orbit around the product, soft studio lighting, 4K cinematic, 3 seconds",
            easterEgg: pack.easterEgg(pn: pn),
            debugTextPrompt: debugPrompt
        )
    }

    func generateImage(prompt: String, reqKey: String, accessKey: String, secretKey: String) async throws -> ImageGenResult {
        try await sleep(seconds: 2.0)
        // Mock: 返回占位图片（实际调用即梦 API 时返回真实 URL）
        return ImageGenResult(imageUrls: [
            "https://picsum.photos/seed/\(UUID().uuidString.prefix(8))/1024/1024",
            "https://picsum.photos/seed/\(UUID().uuidString.prefix(8))/1024/1024",
        ])
    }

    func generateVideo(prompt: String, reqKey: String, accessKey: String, secretKey: String) async throws -> VideoGenResult {
        try await sleep(seconds: 3.0)
        // Mock: 返回占位视频
        return VideoGenResult(videoUrl: "https://example.com/mock-video-\(UUID().uuidString.prefix(8)).mp4")
    }

    func regenerateTitle(
        recordId: UUID,
        keyword: String,
        product: Product?,
        adType: AdType,
        keywordHint: String?
    ) async throws -> String {
        try await sleep(seconds: 1.0)
        let pn = productName(from: keyword, product: product)
        return TemplatePack.pick(for: adType).title(pn: pn)
    }

    func regenerateBody(
        recordId: UUID,
        keyword: String,
        product: Product?,
        adType: AdType,
        keywordHint: String?,
        existingTitle: String,
        existingTags: [String]
    ) async throws -> String {
        try await sleep(seconds: 1.0)
        let pn = productName(from: keyword, product: product)
        return TemplatePack.pick(for: adType).content(pn: pn)
    }

    func regenerateTags(
        recordId: UUID,
        keyword: String,
        product: Product?,
        adType: AdType,
        keywordHint: String?,
        existingTitle: String,
        existingContent: String
    ) async throws -> [String] {
        try await sleep(seconds: 1.0)
        let pn = productName(from: keyword, product: product)
        return TemplatePack.pick(for: adType).tags(pn: pn)
    }

    func transformText(command: String, selectedText: String, context: String) async throws -> String {
        try await sleep(seconds: 0.8)
        switch command {
        case "润色":
            return "「\(selectedText)」—— 已优化表达，使语句更流畅自然"
        case "改写":
            return "换个说法：\(selectedText) 的另一种表达方式已生成"
        case "扩写":
            return "\(selectedText)：这一点可以展开来说，它不仅体现在产品本身，更延伸到了日常使用场景中，让用户体验更加完整"
        case "缩写":
            let shortened = String(selectedText.prefix(max(1, selectedText.count / 2)))
            return shortened.isEmpty ? selectedText : shortened
        case "换风格":
            return "来看看这样写：\(selectedText) ✨ 换个风格是不是更有小红书的感觉了"
        default:
            return selectedText
        }
    }

    func summarizeImagePrompt(
        content: String,
        title: String,
        tags: [String],
        adType: AdType
    ) async throws -> String {
        try await sleep(seconds: 0.5)
        return "minimalist product photography, soft natural lighting, pastel background, clean composition, xiaohongshu style --ar 3:4"
    }

    // MARK: - Helpers

    private func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// First line first token, trimmed to ≤8 characters. Falls back to the
    /// product entry's name, then a generic placeholder.
    private func productName(from keyword: String, product: Product?) -> String {
        let firstLine = keyword
            .split(whereSeparator: { $0.isNewline })
            .first
            .map(String.init) ?? keyword
        let firstToken = firstLine
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? firstLine
        let trimmed = firstToken.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            return String(trimmed.prefix(8))
        }
        if let name = product?.name, !name.isEmpty {
            return String(name.prefix(8))
        }
        return "好物"
    }
}

// MARK: - Templates

private struct TemplatePack {
    let titles: [(String) -> String]
    let contents: [(String) -> String]
    let suggestions: [(String) -> String]
    let imageSuggestions: [(String) -> String]
    let imagePrompts: [(String) -> String]
    let easterEggs: [(String) -> String]
    let tagSets: [[String]]

    func title(pn: String) -> String        { titles.randomElement()!(pn) }
    func content(pn: String) -> String      { contents.randomElement()!(pn) }
    func suggestion(pn: String) -> String   { suggestions.randomElement()!(pn) }
    func imageSuggestion(pn: String) -> String { imageSuggestions.randomElement()!(pn) }
    func imagePrompt(pn: String) -> String  { imagePrompts.randomElement()!(pn) }
    func easterEgg(pn: String) -> String    { easterEggs.randomElement()!(pn) }
    func tags(pn: String) -> [String] {
        var set = tagSets.randomElement()!
        // Inject product name as a long-tail tag at position 1
        if !set.contains(where: { $0.contains(pn) }) {
            set.insert("\(pn)推荐", at: 1)
        }
        return Array(set.prefix(8))
    }

    static func pick(for type: AdType) -> TemplatePack {
        switch type {
        case .feedAd:    return .feed
        case .searchAd:  return .search
        case .brandAd:   return .brand
        case .salesNote: return .sales
        }
    }

    // MARK: - 信息流广告

    static let feed = TemplatePack(
        titles: [
            { pn in "💖姐妹冲！\(pn)真的让我回购到第三瓶✨" },
            { pn in "🌸入手\(pn)两周……我皮肤偷偷在变好💫" }
        ],
        contents: [
            { pn in """
            💖说真的我刚入\(pn)的时候真的没抱什么期待…就随手买的那种

            🌿结果用了三天就回来写笔记了！上脸完全不挑肤，闺蜜来我家蹭了一次直接代购加3

            ✨最戳我的点其实是质地，介于水和乳之间的那种，推开一秒就吸收，不黏不腻

            🌙我现在每天晚上都期待洗完澡那一下涂\(pn)的时刻，整个人都松下来了

            🛒平价里我用过的算很能打的一个，懒姐妹真的可以放心冲
            """ },
            { pn in """
            🌸闺蜜小聚被疯狂安利\(pn)，回家就下单了，没想到真踩到心巴上

            🍑包装本身就挺好看，放梳妆台上不显乱，颜值党友好

            🌿质地温和到不像有效果的样子…但坚持用了两周肤况肉眼可见在稳

            💫现在出门前不涂会觉得少了点什么，已经变成那种「不能少」的存在

            🛍真心推荐想入门又怕翻车的姐妹，闭眼冲不亏
            """ }
        ],
        suggestions: [
            { pn in "标题情绪有了但痛点不够，建议在「\(pn)」前加场景词如「油皮」或「夏天通勤」，提高点击率" },
            { pn in "正文偏抒情，建议加一句对比体验（如「之前用XX的时候…」），增强种草说服力" }
        ],
        imageSuggestions: [
            { pn in "晨光暖色调，\(pn)斜45度摆放在原木梳妆台一角，旁边搭配一支干花和绿植，营造日常生活感。" },
            { pn in "浅灰柔光背景，\(pn)放在浅色羊毛毯上，旁边一杯拿铁与一本翻开的书，慵懒下午场景。" }
        ],
        imagePrompts: [
            { pn in "soft natural lighting, \(pn) placed at 45 degrees on warm oak vanity, dried flowers and green plant beside, lifestyle product photography, high resolution --ar 3:4" },
            { pn in "minimalist beauty product on linen surface, soft window light, latte and book beside, lazy weekend mood, editorial photography --ar 3:4" }
        ],
        easterEggs: [
            { pn in "好用到想替你买🥹" },
            { pn in "懒人版护肤天花板✨" }
        ],
        tagSets: [
            ["平价好物", "种草日记", "回购清单", "日常护肤", "懒人护肤", "闺蜜安利"],
            ["种草", "好物分享", "踩雷指北", "梳妆台必备", "新手友好", "回购N次"]
        ]
    )

    // MARK: - 搜索广告

    static let search = TemplatePack(
        titles: [
            { pn in "🔍\(pn)测评 | 三款对比后我留下了它💯" },
            { pn in "📌\(pn)怎么选？这篇攻略别再走弯路！" }
        ],
        contents: [
            { pn in """
            🔍说真的搜\(pn)搜了一周…功课做到头秃才下手，今天直接出对比

            📊我手上同时有三款同价位的，连续两周交叉用，从持妆/肤感/性价比三个维度打分

            ✨\(pn)赢在肤感，上脸没有那种"糊一层"的厚重感，油皮通勤8小时基本稳得住

            ⚠️唯一缺点是色号偏少，黄皮姐妹建议下手前看实拍试色，别只看官图

            🛒综合下来\(pn)是我现在的本命，附上具体回购理由👇
            """ },
            { pn in """
            📚最近后台一直被问\(pn)，今天系统整理一篇，从入门到避雷一次说清

            🧐先说结论：性价比党可以冲，追求顶配的可以再看一眼别家

            ✨真实使用感是\(pn)在中性肤上的表现最稳，干皮要叠面霜，油皮基本不用挑场景

            ⚠️注意第一次用先在耳后试敏感，毕竟成分这事每个人耐受度不一样

            🛒下方放对比表，懒得看的姐妹直接拉到最后看推荐链接
            """ }
        ],
        suggestions: [
            { pn in "搜索广告需要关键词密度，建议在正文前 50 字内重复出现「\(pn)」+「测评」「对比」「攻略」其一" },
            { pn in "标题缺少搜索意图词，建议加「平价替代」或「红黑榜」前缀提升 SEO 命中率" }
        ],
        imageSuggestions: [
            { pn in "纯白桌面俯拍，\(pn)居中，左右各放一款同价位对比品，标注价格小贴纸，攻略感强。" },
            { pn in "浅灰背景三宫格构图，\(pn)放在中间格，左右两格分别展示成分卡和使用前后对比。" }
        ],
        imagePrompts: [
            { pn in "top down flat lay, \(pn) centered on white background, two competitor products on left and right with small price tags, comparison chart layout, high resolution --ar 3:4" },
            { pn in "three panel layout, \(pn) center, ingredient card left, before-after right, neutral grey background, editorial review style --ar 3:4" }
        ],
        easterEggs: [
            { pn in "搜了一周不如看这篇📌" },
            { pn in "避雷地图请收好🗺" }
        ],
        tagSets: [
            ["测评对比", "选购攻略", "红黑榜", "避雷指南", "新手必看", "性价比之王"],
            ["攻略", "对比测评", "成分党", "购物清单", "种草避雷", "省钱攻略"]
        ]
    )

    // MARK: - 品牌广告

    static let brand = TemplatePack(
        titles: [
            { pn in "🤍关于\(pn) | 我想认真聊聊它的质感" },
            { pn in "✨\(pn)：一支让人安心的日常之选" }
        ],
        contents: [
            { pn in """
            🤍认识\(pn)是一次很安静的过程，没有大开大合的种草，只是用着用着发现离不开

            🌿成分是温和派那一挂，对敏感肌很友好，连续用一个月没有任何不适

            ✨它的设计也克制，磨砂瓶身放在台面上不抢戏，反而像家里固定陪伴的一件小物

            🍃官方在售后这块做得挺让人安心，问过两次客服都耐心解答，没有那种敷衍感

            🤝如果你也喜欢「不张扬但靠谱」的产品，\(pn)值得加进愿望单
            """ },
            { pn in """
            ✨写\(pn)其实犹豫了很久，因为它不是那种一上来就惊艳的产品，是越用越踏实的那一类

            🌿牌子本身一直走稳一点的路线，没有花哨包装，质感全在使用体验里

            🍃从配方到容器密封性都看得到用心，每一处都像是认真考虑过用户的

            💫长期使用的感受比短期种草更值得分享，这也是为什么我想正式聊聊\(pn)

            🌙喜欢慢消费、看重品质的姐妹，应该会和它合得来
            """ }
        ],
        suggestions: [
            { pn in "品牌广告需要稳重感，建议把第一段口语化感叹号减少，前两段保留专业冷静语气更贴合品牌" },
            { pn in "可以在正文中段加入一句品牌历史或工艺细节（如成分溯源），增强\(pn)的信任背书" }
        ],
        imageSuggestions: [
            { pn in "高级灰背景，\(pn)单独居中，柔和侧光打出瓶身轮廓，强调材质质感与品牌调性。" },
            { pn in "原木台面深色调，\(pn)与一支签字笔、一本皮面笔记本同框，传递成熟用户场景。" }
        ],
        imagePrompts: [
            { pn in "premium product photography, \(pn) centered on warm grey backdrop, soft rim light, focus on material texture, editorial brand campaign style --ar 3:4" },
            { pn in "mature lifestyle still life, \(pn) on dark walnut desk with leather notebook and fountain pen, moody ambient lighting --ar 3:4" }
        ],
        easterEggs: [
            { pn in "稳稳的安心感🤍" },
            { pn in "时间会证明的好物✨" }
        ],
        tagSets: [
            ["品牌故事", "质感生活", "长期主义", "成分党", "高级感", "日常仪式"],
            ["品质之选", "信任之选", "经典款", "慢消费", "梳妆台精选", "品牌推荐"]
        ]
    )

    // MARK: - 带货笔记

    static let sales = TemplatePack(
        titles: [
            { pn in "🔥\(pn)直降！今天不囤等明年涨价？💥" },
            { pn in "💥姐妹快冲！\(pn)半价末班车⏰" }
        ],
        contents: [
            { pn in """
            🔥姐妹们紧急通知！\(pn)今晚直播间直降一半！我刚抢完三瓶手都在抖

            💄先说效果：上脸即贴肤，油皮我亲测8小时不糊妆，闺蜜干皮也能驾驭

            ⚡️价格力度真的离谱，平时一瓶的钱今天能拿两瓶，错过又得等半年

            👇下单链接放评论区第一条，叠加店铺优惠券直接到手价更香

            🛒囤货党别犹豫，自用送人都合适，\(pn)闭眼冲不亏
            """ },
            { pn in """
            💥说真的我从来不催别人下单，但\(pn)今天这个价我必须拍桌子

            ✨先报数据：连续回购4次的真爱用户在此，效果不用我吹，评论区自己看

            🔥今晚的活动是直降+赠品+运费险，三重叠加是历史最低

            ⏰库存只有2000件，上次活动20分钟就空了，慢一步真的没有

            🛍我已经下单两瓶屯起来了，姐妹们的链接放第一条评论，冲就完事
            """ }
        ],
        suggestions: [
            { pn in "带货笔记需要更强行动召唤，建议标题加倒计时词「最后3小时」并把\(pn)价格优势前置" },
            { pn in "正文可以加一句具体的优惠数字（如「直降68元」），比模糊的「半价」更能催单" }
        ],
        imageSuggestions: [
            { pn in "亮黄背景配红色价签贴纸，\(pn)居中放置，左上角加「限时抢购」徽章，强促销感。" },
            { pn in "直播间手持镜头感，\(pn)被手举着对镜头，背景虚化的购物车堆叠，制造抢购氛围。" }
        ],
        imagePrompts: [
            { pn in "promotional product shot, \(pn) on bright yellow background with red price tag sticker, limited time badge top left, high contrast e-commerce style --ar 3:4" },
            { pn in "livestream hand held shot, \(pn) presented to camera, blurred shopping carts in background, energetic promotional mood --ar 3:4" }
        ],
        easterEggs: [
            { pn in "钱包痛但心是甜的💸" },
            { pn in "晚下单一秒都是损失🤯" }
        ],
        tagSets: [
            ["直播好物", "限时优惠", "囤货推荐", "回购清单", "今日必抢", "省钱攻略"],
            ["带货", "薅羊毛", "全网最低价", "活动预告", "购物清单", "立即下单"]
        ]
    )
}
