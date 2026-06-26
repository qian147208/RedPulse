//
//  GenerateViewHelpers.swift
//  灵芯
//
//  LLM helpers and state management extracted from GenerateView.
//  Extracted from the original 1272-line GenerateView.
//

import Foundation
import SwiftUI

// MARK: - Generate Action Button

struct GenerateActionButton: View {
    let isGenerating: Bool
    let onGenerate: () -> Void

    /// 跟 GenerateView 共享 currentStep — 第 5 步（生成按钮）的 popover 在 step == 4 时显示
    @AppStorage("generate_onboarding_step") private var currentStep: Int = -1
    /// 第 5 步 popover 显示状态（GenerateView 用 .onChange(of: currentStep) 设 true，
    /// 用户点"知道了"按钮时设 false 并 currentStep = 5）
    @State private var showGenerateTip: Bool = false

    private var enabled: Bool {
        !isGenerating
    }

    var body: some View {
        Button {
            HapticManager.heavyImpact()
            onGenerate()
        } label: {
            HStack(spacing: 10) {
                if isGenerating {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(.white)
                    Text("AI 撰写中...")
                } else {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 16, weight: .bold))
                    Text("立即生成小红书笔记")
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Adaptive.buttonHeight)
            .background(
                LinearGradient(
                    colors: [Color.brand, Color(red: 0.95, green: 0.08, blue: 0.25)],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            )
            .shadow(color: Color.brand.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1.0 : 0.5)
.keyboardShortcut("r", modifiers: .command)
        // P0-4: popover 在 iPad/Mac 上行为不一致（箭头方向、定位），改用 sheet 跨平台统一
        .sheet(isPresented: $showGenerateTip) {
            OnboardingPopover(
                title: "一键生成",
                message: "信息填好后点这里，AI 一次性给你标题、正文、标签。下一步教你怎么生成配图和视频",
                icon: "wand.and.stars",
                onDismiss: {
                    showGenerateTip = false
                    currentStep = 5
                }
            )
        }
        // currentStep 变化 → 启动对应 popover
        .onChange(of: currentStep) { _, new in
            if new == 4 {
                // 用微小延迟等按钮渲染完，否则 popover 位置算不准
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showGenerateTip = true
                }
            }
        }
    }
}

// MARK: - Product Category Inference
//
//  从产品名/卖点/场景/用户关键词里推断品类 — 让 LLM prompt 显式知道是什么品类，
//  并提供品类相关的 fallback 池 + 相关性校验兜底，确保 03/04 刷出来的东西跟产品强匹配。

enum ProductCategory: String, CaseIterable {
    case beauty = "美妆彩妆"
    case skincare = "护肤"
    case fashion = "穿搭时尚"
    case food = "美食"
    case fitness = "健身运动"
    case home = "家居生活"
    case digital = "数码电器"
    case parenting = "母婴亲子"
    case travel = "旅行"
    case other = "通用"

    /// 推断当前产品所属品类（取首个命中的，优先级按声明顺序）
    static func infer(product: Product?, keyword: String) -> ProductCategory {
        let haystack = (
            (product?.name ?? "") + " " +
            (product?.sellingPoint ?? "") + " " +
            (product?.scenario ?? "") + " " +
            (product?.targetAudience ?? "") + " " +
            keyword
        ).lowercased()

        // 每个品类的"识别词" — 命中就归该类
        let rules: [(ProductCategory, [String])] = [
            (.beauty,     ["口红", "唇釉", "唇彩", "粉底", "气垫", "bb霜", "cc霜", "眼影", "腮红", "眉笔", "睫毛", "彩妆", "美妆", "ysl", "dior", "mac", "雅诗兰黛", "兰蔻", "完美日记", "花西子", "3ce", "nars", "tom ford", "tf", "givenchy", "香奈儿", "Chanel"]),
            (.skincare,   ["护肤", "精华", "面霜", "乳液", "水乳", "水", "爽肤水", "化妆水", "洁面", "洗面奶", "防晒", "面膜", "玻尿酸", "烟酰胺", "视黄醇", "a醇", "敏感肌", "换季", "油皮", "干皮", "混油皮", "痘痘", "黑头", "毛孔", "祛痘", "sk-ii", "skii", "资生堂", "雅漾", "珂润", "薇诺娜", "理肤泉"]),
            (.fashion,    ["穿搭", "裙子", "连衣裙", "裤子", "牛仔裤", "阔腿裤", "外套", "风衣", "衬衫", "西装", "卫衣", "毛衣", "t恤", "polo衫", "鞋子", "运动鞋", "帆布鞋", "包包", "通勤", "约会", "小个子", "梨形", "苹果型", "显瘦", "显高", "ins风", "ootd", "小众品牌", "无性别"]),
            (.food,       ["美食", "菜谱", "减脂餐", "低卡", "零食", "甜品", "蛋糕", "面包", "咖啡", "拿铁", "奶茶", "早餐", "晚餐", "宵夜", "便当", "烘焙", "零食", "拌面", "火锅", "烧烤", "探店", "下午茶", "减脂", "饱腹", "速食", "拌饭"]),
            (.fitness,    ["健身", "瑜伽", "跑步", "减肥", "瘦身", "塑形", "马甲线", "天鹅臂", "帕梅拉", "刘畊宏", "燃脂", "增肌", "蛋白粉", "运动内衣", "瑜伽垫"]),
            (.home,       ["家居", "家装", "装修", "卧室", "客厅", "厨房", "浴室", "收纳", "氛围感", "治愈系", "好物", "ins风家居", "出租屋", "小户型", "香薰", "蜡烛"]),
            (.digital,    ["手机", "iphone", "华为", "小米", "电脑", "macbook", "耳机", "airpods", "相机", "数码", "智能", "智能手表", "投影", "键盘", "充电宝"]),
            (.parenting,  ["宝宝", "婴儿", "母婴", "奶粉", "纸尿裤", "辅食", "亲子", "孕妇", "怀孕", "待产", "新生儿", "幼儿", "早教", "玩具"]),
            (.travel,     ["旅行", "旅游", "攻略", "酒店", "景点", "vlog", "民宿", "自驾", "机票", "签证", "穷游", "city walk", "citywalk"]),
        ]

        for (cat, keywords) in rules {
            if keywords.contains(where: { haystack.contains($0) }) {
                return cat
            }
        }
        return .other
    }

    /// 各类别用于"03 热门关键词"的相关词库 — LLM 输出后做相关性校验
    var relevanceLexicon: [String] {
        switch self {
        case .beauty:     return ["口红", "唇", "粉底", "底妆", "眼影", "腮红", "彩妆", "妆容", "显白", "色号", "黄黑皮", "黄皮", "素颜", "伪素颜", "斩男", "氛围感", "纯欲", "日常妆", "约会妆", "通勤妆", "持久", "不拔干", "不拔", "不沾杯", "mac", "ysl", "dior", "花西子", "完美日记", "3ce", "tom ford", "tf", "nars", "givenchy", "香奈儿", "兰蔻", "雅诗兰黛", "美宝莲", "kate", "kanebo", "爱丽小屋"]
        case .skincare:   return ["护肤", "精华", "面霜", "乳液", "水乳", "爽肤水", "化妆水", "洁面", "洗面奶", "防晒", "面膜", "成分", "玻尿酸", "烟酰胺", "视黄醇", "a醇", "敏感肌", "换季", "油皮", "干皮", "混油皮", "痘痘", "黑头", "毛孔", "抗老", "抗初老", "抗皱", "美白", "提亮", "淡斑", "祛痘", "闭口", "sk2", "sk-ii", "资生堂", "雅漾", "珂润", "薇诺娜", "理肤泉", "黛珂", " ipsa", "茵芙莎", "珂莱蒂尔", "敏感肌救星", "学生党护肤", "平价护肤"]
        case .fashion:    return ["穿搭", "裙子", "连衣裙", "半身裙", "裤子", "阔腿裤", "牛仔裤", "外套", "风衣", "衬衫", "西装", "卫衣", "毛衣", "t恤", "polo", "鞋子", "运动鞋", "帆布鞋", "包包", "通勤", "约会", "小个子", "梨形", "苹果型", "显瘦", "显高", "百搭", "ins风", "ootd", "街拍", "小众品牌", "高级感", "无性别", "中性风", "山本耀司", "zara", "h&m", "ur", "me&city", "热风", "西遇"]
        case .food:       return ["美食", "菜谱", "减脂餐", "低卡", "零食", "甜品", "蛋糕", "面包", "咖啡", "拿铁", "奶茶", "早餐", "晚餐", "宵夜", "便当", "烘焙", "拌面", "火锅", "烧烤", "探店", "下午茶", "减脂", "饱腹", "速食", "拌饭", "饱腹感", "学生党", "上班族", "懒人", "微波炉", "快手菜", "家常菜", "下饭菜"]
        case .fitness:    return ["健身", "瑜伽", "跑步", "减肥", "瘦身", "塑形", "马甲线", "天鹅臂", "帕梅拉", "刘畊宏", "燃脂", "增肌", "蛋白粉", "运动内衣", "瑜伽垫", "拉伸", "普拉提", "撸铁", "拳击", "有氧", "无氧", "打卡", "居家健身", "健身房", "训练", "体重", "体脂", "围度", "背薄", "瘦腿", "瘦腰", "瘦手臂", "体态"]
        case .home:       return ["家居", "家装", "装修", "卧室", "客厅", "厨房", "浴室", "收纳", "氛围感", "治愈系", "好物", "ins风家居", "出租屋", "小户型", "香薰", "蜡烛", "床品", "四件套", "小家电", "空气炸锅", "扫地机器人", "洗碗机", "投影", "绿植", "装饰画", "抱枕", "地毯", "窗帘", "灯光", "氛围灯", "北欧风", "日式", "极简", "奶油风", "中古风", "侘寂"]
        case .digital:    return ["手机", "iphone", "华为", "小米", "电脑", "macbook", "耳机", "airpods", "相机", "数码", "智能", "智能手表", "投影", "键盘", "充电宝", "switch", "ps5", "ipad", "安卓", "苹果", "测评", "开箱", "性价比", "学生党", "上班族", "生产力", "拍照", "vlog", "摄影", "蓝牙", "降噪", "无线充电", "快充"]
        case .parenting:  return ["宝宝", "婴儿", "母婴", "奶粉", "纸尿裤", "辅食", "亲子", "孕妇", "怀孕", "待产", "新生儿", "幼儿", "早教", "玩具", "哄睡", "夜醒", "母乳", "奶粉", "添加辅食", "断奶", "疫苗", "儿保", "亲子互动", "育儿", "宝妈", "奶爸", "月嫂", "月子", "新生儿护理", "绘本", "幼儿园", "幼小衔接"]
        case .travel:     return ["旅行", "旅游", "攻略", "酒店", "景点", "vlog", "民宿", "自驾", "机票", "签证", "穷游", "city walk", "citywalk", "周末游", "周边游", "亲子游", "毕业旅行", "蜜月", "打卡", "出片", "机酒", "自由行", "跟团", "行李", "攻略", "小红书旅行", "特种兵旅行", "慢游", "躺平游"]
        case .other:      return []
        }
    }

    /// 各类别用于"03 热门关键词"的 fallback 池（精选 24+ 个，去重不通用）
    var trendingFallbackPool: [String] {
        switch self {
        case .beauty:
            return ["显白色号", "黄黑皮亲妈", "伪素颜口红", "斩男色", "氛围感妆容", "日常通勤妆", "约会斩男妆", "新手化妆", "底妆教程", "不沾杯口红", "持久口红", "平价彩妆", "大牌平替", "学生党彩妆", "彩妆工具", "眼影盘", "腮红画法", "韩系妆容", "日系妆容", "纯欲风", "亚裔妆容"]
        case .skincare:
            return ["学生党护肤", "敏感肌救星", "换季护肤", "油皮亲妈", "干皮救星", "抗老精华", "美白精华", "成分党", "早c晚a", "刷酸", "面膜测评", "防晒霜", "洗面奶", "水乳套装", "面霜推荐", "平价护肤", "大牌护肤", "孕妇可用", "痘肌自救", "毛孔收敛", "闭口粉刺"]
        case .fashion:
            return ["通勤穿搭", "约会穿搭", "梨形身材", "苹果型穿搭", "小个子穿搭", "显高显瘦", "ins风穿搭", "ootd", "高级感穿搭", "无性别风", "百搭单品", "基础款", "叠穿", "小众品牌", "国潮穿搭", "复古风", "街头风", "少女感", "甜酷风", "极简风"]
        case .food:
            return ["减脂餐", "饱腹感", "懒人食谱", "微波炉美食", "快手菜", "学生党早餐", "上班族便当", "低卡零食", "饱腹代餐", "自制奶茶", "拿铁教程", "甜品教程", "烘焙入门", "探店打卡", "火锅推荐", "烧烤合集", "下午茶", "减脂食谱", "下饭菜", "速食推荐"]
        case .fitness:
            return ["居家健身", "帕梅拉", "刘畊宏", "马甲线", "瘦腿", "瘦腰", "瘦手臂", "体态矫正", "瑜伽入门", "普拉提", "燃脂训练", "增肌", "减肥打卡", "健身房穿搭", "运动内衣", "瑜伽垫", "拉伸", "跑步打卡", "拳击", "撸铁"]
        case .home:
            return ["氛围感卧室", "治愈系家居", "小户型改造", "出租屋改造", "北欧风", "奶油风", "中古风", "极简风", "日式风", "侘寂风", "ins风家居", "氛围灯", "香薰蜡烛", "床品四件套", "地毯", "抱枕", "绿植", "装饰画", "小家电", "空气炸锅食谱"]
        case .digital:
            return ["iphone测评", "安卓机皇", "性价比手机", "macbook攻略", "学生党电脑", "蓝牙耳机", "降噪耳机", "airpods平替", "投影仪", "switch游戏", "ps5测评", "ipad生产力", "vlog相机", "拍照手机", "快充充电器", "充电宝", "智能手表", "机械键盘", "学生党数码", "上班族数码"]
        case .parenting:
            return ["新生儿护理", "待产包", "母乳喂养", "奶粉测评", "辅食食谱", "纸尿裤测评", "哄睡技巧", "夜醒频繁", "早教启蒙", "亲子互动", "幼儿绘本", "疫苗攻略", "儿保体检", "幼儿园入园", "幼小衔接", "宝妈日常", "奶爸带娃", "亲子穿搭", "宝宝辅食", "断奶日记"]
        case .travel:
            return ["周末游", "周边游", "city walk", "穷游攻略", "自驾游", "亲子游", "毕业旅行", "蜜月旅行", "机酒套餐", "民宿推荐", "小众景点", "出片机位", "打卡圣地", "特种兵旅行", "慢游", "躺平游", "自由行", "跟团游", "行李打包", "旅行vlog"]
        case .other:
            return ["好物分享", "种草向", "测评向", "干货风", "真实体验", "避雷指南", "问号钩子", "小众宝藏", "懒人必备", "氛围感", "治愈系", "沉浸式", "氛围出片", "细节党", "回购清单", "白月光单品", "上头安利", "避坑实测", "急救方案", "氛围博主"]
        }
    }

    /// 各类别用于"04 风格提示词"的 fallback 池
    var hintFallbackPool: [String] {
        switch self {
        case .beauty:
            return ["显白色号", "持久度测评", "伪素颜", "黄皮亲妈", "氛围感妆容", "约会斩男妆", "日常通勤妆", "不沾杯", "新手友好", "平价彩妆", "大牌平替", "成分党", "学生党彩妆", "彩妆工具", "底妆教程"]
        case .skincare:
            return ["成分党", "敏感肌救星", "早c晚a", "换季护肤", "油皮亲妈", "学生党护肤", "抗老精华", "美白精华", "刷酸入门", "面膜测评", "平价护肤", "大牌护肤", "痘肌自救", "孕妇可用", "闭口粉刺"]
        case .fashion:
            return ["通勤穿搭", "小个子穿搭", "梨形身材", "约会穿搭", "显高显瘦", "高级感", "百搭单品", "小众品牌", "无性别风", "复古风", "少女感", "甜酷风", "极简风", "国潮", "街头风"]
        case .food:
            return ["减脂餐", "懒人食谱", "快手菜", "上班族便当", "学生党早餐", "低卡零食", "甜品教程", "烘焙入门", "探店打卡", "饱腹感", "微波炉美食", "速食推荐", "下午茶", "下饭菜", "火锅推荐"]
        case .fitness:
            return ["居家健身", "帕梅拉跟练", "马甲线", "体态矫正", "瘦腿", "瘦腰", "瘦手臂", "瑜伽入门", "燃脂训练", "增肌", "减肥打卡", "跑步打卡", "撸铁", "拳击", "拉伸"]
        case .home:
            return ["氛围感卧室", "治愈系", "小户型改造", "出租屋改造", "奶油风", "中古风", "极简风", "日式风", "ins风", "氛围灯", "香薰蜡烛", "床品推荐", "小家电", "绿植", "装饰画"]
        case .digital:
            return ["性价比", "开箱测评", "学生党首选", "生产力", "拍照神器", "vlog相机", "降噪耳机", "蓝牙耳机", "快充", "续航", "颜值党", "游戏党", "上班族工具", "学生党攻略", "预算友好"]
        case .parenting:
            return ["待产包清单", "新生儿护理", "母乳喂养", "辅食日记", "哄睡技巧", "早教启蒙", "亲子互动", "幼儿绘本", "宝妈日常", "奶爸带娃", "疫苗攻略", "儿保体检", "幼儿园入园", "幼小衔接", "亲子穿搭"]
        case .travel:
            return ["周末游", "周边游", "city walk", "穷游攻略", "自驾路线", "亲子游", "毕业旅行", "蜜月", "机酒套餐", "民宿", "小众景点", "出片机位", "打卡圣地", "行李打包", "vlog"]
        case .other:
            return ["好物分享", "种草向", "测评向", "干货风", "真实体验", "避雷指南", "小众宝藏", "懒人必备", "氛围感", "治愈系", "沉浸式", "回购清单", "上头安利", "避坑实测", "细节党"]
        }
    }
}

// MARK: - Generation Helpers (LLM & error handling)

struct GenerationHelpers {
    /// "大模型刷新"按钮触发：基于当前选中产品上下文（无则通用风格）
    /// 让模型重写 6-10 个风格定调胶囊词（2-5 字），写入 hintChips。
    /// - nonce 注入：保证每次刷新得到不同结果
    /// - maxTokens 收紧到 150：风格词就 8 个，足够
    static func fetchHintChipsFromLLM(
        product: Product?,
        keyword: String,
        completion: @escaping ([String]) async -> Void
    ) async {
        let category = ProductCategory.infer(product: product, keyword: keyword)
        let ctx = productContextLine(product: product, keyword: keyword)
        let nonce = randomNonce()
        let prompt = """
        任务：基于产品/关键词上下文，输出 8 个**风格 / 角度提示词**，用于引导 AI 撰写小红书笔记。
        【产品类别】\(category.rawValue)
        \(ctx.isEmpty ? "" : ctx)

        硬性要求（**不满足就走 fallback 池**）：
        - 每个 2-5 字
        - 必须**直接命中【产品类别】**——比如口红→「显白色号」「黄皮亲妈」「持久度测评」；护肤→「成分党」「敏感肌救星」「换季护肤」；穿搭→「通勤穿搭」「梨形身材」「小个子显高」
        - 不要泛泛的"测评向""干货风""好物分享"这种**与任何品类都通用的空话**
        - 互补覆盖：测评 / 教程 / 情绪 / 对比 / 避雷 / 种草 至少 4 种角度
        - 本次输出请避免与之前重复（nonce=\(nonce)）

        严格输出 JSON 数组：["提示1","提示2",...]，不要 markdown 不要解释。
        """
        if let list = await chatJSONList(prompt: prompt, maxTokens: 200), !list.isEmpty {
            // 相关性校验：≥50% 的输出必须含类别相关词，否则说明 LLM 没理解产品，
            // 直接用 fallback 池（比"看起来错"的 LLM 输出强）
            let validated = validateRelevance(chips: list, category: category, minHitRate: 0.5)
            if validated.count >= 6 {
                await completion(Array(validated.prefix(10)))
            } else {
                DebugLog.shared.log(.warn, .llm, "hintChips relevance check failed, using fallback pool", details: "category=\(category.rawValue), llmHits=\(validated.count)/\(list.count)")
                await completion(Self.fallbackHintChips(category: category))
            }
        } else {
            await completion(Self.fallbackHintChips(category: category))
        }
    }

    /// 风格 chips fallback 池（按类别给，比 LLM 输出更稳）
    static func fallbackHintChips(category: ProductCategory? = nil) -> [String] {
        let cat = category ?? .other
        return Array(cat.hintFallbackPool.shuffled().prefix(8))
    }

    /// 用 LLM 生成小红书当前热门关键词（≤12 个），如有产品上下文会聚焦该产品所在领域。
    /// - nonce 注入：保证每次刷新得到不同结果
    /// - maxTokens 收紧到 200：12 个短关键词足够
    /// - 内部已 fallback，永远返回非空数组（成功用 LLM 结果，失败用随机池）
    static func fetchKeywordsFromLLM(
        product: Product?,
        keyword: String
    ) async -> [String] {
        let category = ProductCategory.infer(product: product, keyword: keyword)
        let ctx = productContextLine(product: product, keyword: keyword)
        let nonce = randomNonce()
        let prompt = """
        任务：基于产品/关键词上下文，输出 12 个**小红书热门关键词/话题**（每个 2-6 字）。
        【产品类别】\(category.rawValue)
        \(ctx.isEmpty ? "" : ctx)

        硬性要求（**不满足就走 fallback 池**）：
        - **必须直接命中【产品类别】**——比如口红→「显白色号」「黄皮亲妈」「伪素颜口红」；护肤→「学生党护肤」「敏感肌救星」「换季护肤」；穿搭→「通勤穿搭」「梨形身材」「小个子显高」
        - 聚焦该类别的核心痛点 + 人群场景（中国 25-35 岁女性为主）
        - 不要跨品类的"好物分享""种草"等空泛词
        - 互补覆盖：测评 / 教程 / 场景 / 痛点 / 趋势 至少 4 种角度
        - 本次输出请避免与之前重复（nonce=\(nonce)）

        严格输出 JSON 数组：["关键词1","关键词2",...]，不要 markdown 代码块标记，不要解释。
        """
        if let list = await chatJSONList(prompt: prompt, maxTokens: 250), !list.isEmpty {
            // 相关性校验：≥50% 输出必须含类别相关词，否则 LLM 没理解产品，走 fallback
            let validated = validateRelevance(chips: list, category: category, minHitRate: 0.5)
            if validated.count >= 8 {
                return validated
            }
            DebugLog.shared.log(.warn, .llm, "trendingKeywords relevance check failed, using fallback pool", details: "category=\(category.rawValue), llmHits=\(validated.count)/\(list.count)")
            return Self.fallbackTrendingKeywords(category: category)
        }
        // 失败 fallback：按类别抽
        return Self.fallbackTrendingKeywords(category: category)
    }

    /// 关键词失败时的 fallback 池（按类别给）
    static func fallbackTrendingKeywords(category: ProductCategory? = nil) -> [String] {
        let cat = category ?? .other
        return Array(cat.trendingFallbackPool.shuffled().prefix(12))
    }

    /// 相关性校验：每个 chip 至少含 1 个类别相关词，才算"命中"。
    /// - minHitRate: 至少多少比例的 chip 命中，才算 LLM 输出可用
    /// - 返回值：只保留命中的 chip（如果全不命中，返回空数组 → 触发 fallback）
    static func validateRelevance(chips: [String], category: ProductCategory, minHitRate: Double) -> [String] {
        // .other 类别没有相关词库，跳过校验（直接用 LLM 输出）
        guard category != .other else { return chips }

        let lex = category.relevanceLexicon
        let hits = chips.filter { chip in
            lex.contains(where: { keyword in
                chip.lowercased().contains(keyword.lowercased())
            })
        }
        let rate = chips.isEmpty ? 0 : Double(hits.count) / Double(chips.count)
        if rate >= minHitRate {
            return chips  // 整体通过 — 全保留（不只保留命中的，避免过度清洗）
        }
        return hits  // 整体不通过 — 只返回命中的（即使 <minHitRate），让上层判断
    }

    /// 给 prompt 加一个不可预测的随机串，确保每次生成的 prompt 不同 → 输出也不同
    private static func randomNonce() -> String {
        // 6 位字母数字即可，避免 prompt 太长
        let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<6).map { _ in chars.randomElement()! })
    }

    /// 把选中产品 / 当前关键词 / 风格提示 拼成简短上下文段落，给 LLM 做 prompt 参考。
    static func productContextLine(product: Product?, keyword: String) -> String {
        guard let p = product else {
            let kw = keyword.trimmingCharacters(in: .whitespaces)
            return kw.isEmpty ? "" : "\n[当前关键词]\n\(kw)"
        }
        var lines = ["产品名称：\(p.name)", "卖点：\(p.sellingPoint)"]
        if let t = p.targetAudience, !t.isEmpty { lines.append("目标人群：\(t)") }
        if let s = p.scenario, !s.isEmpty { lines.append("场景：\(s)") }
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        if !kw.isEmpty { lines.append("当前关键词：\(kw)") }
        return "\n[产品上下文]\n" + lines.joined(separator: "\n")
    }

    /// 通用 LLM JSON 数组返回工具：发请求 → 期望 content 是 JSON 数组 → 解析返回。
    static func chatJSONList(prompt: String, maxTokens: Int) async -> [String]? {
        // 走 LLMConfigStore — 兼容默认/自定义两种模式
        let cfg = LLMConfigStore.config(for: .text)
        let urlStr = cfg.baseURL
        let key = cfg.apiKey
        let model = cfg.model
        guard cfg.isValid,
              let url = URL(string: urlStr.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20  // Agnes API 响应本身偏慢，6s 必超时；给到 20s 留够 buffer
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "你是一个 JSON 输出机器人，只输出 JSON 数组，不输出任何其它内容。"],
                ["role": "user", "content": prompt]
            ],
            "temperature": 1.2,    // 加速分散度：0.9 → 1.2，配合 nonce 保证每次不同
            "max_tokens": maxTokens
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let message = first["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.hasPrefix("```") {
                if let nl = cleaned.firstIndex(of: "\n") {
                    cleaned = String(cleaned[cleaned.index(after: nl)...])
                }
                if cleaned.hasSuffix("```") {
                    cleaned = String(cleaned.dropLast(3))
                }
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard let arr = try? JSONSerialization.jsonObject(with: cleaned.data(using: .utf8) ?? Data()) as? [String] else {
                return nil
            }
            return arr.filter { !$0.isEmpty }
        } catch {
            return nil
        }
    }

    /// 把底层网络/解析错误转成用户能直接看懂的中文短句。
    static func friendlyErrorMessage(raw: String, error: Error) -> String {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .timedOut:
                return "网络超时，请检查 LLM 服务可达性或更换网络"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "无法连接到 LLM 服务，请到 设置 → 大模型 检查 URL"
            case .notConnectedToInternet:
                return "当前无网络连接"
            default:
                break
            }
        }
        if raw.contains("HTTP 401") || raw.contains("HTTP 403") {
            return "API Key 无效，请到 设置 → 大模型 检查"
        }
        if raw.contains("HTTP 429") {
            return "调用过于频繁，请稍后再试"
        }
        if raw.contains("HTTP 5") {
            return "LLM 服务异常，请稍后再试"
        }
        if raw.contains("URL / Key / Model 三件套未配齐") {
            return "尚未配置大模型，请到 设置 → 大模型 填写 URL/Key/Model"
        }
        if raw.contains("API URL 无效") {
            return "LLM URL 格式有误，请到 设置 → 大模型 修正"
        }
        if raw.contains("未返回合法 JSON") || raw.contains("响应缺少") || raw.contains("非 UTF-8") {
            return "模型返回格式异常，请换一个模型或重试"
        }
        return raw
    }
}
