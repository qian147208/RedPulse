//
//  LegalView.swift
//  RedPulse
//
//  隐私协议与服务条款
//
//  P1:与 docs/TERMS_AND_PRIVACY.md 保持一致,反映代码里真实数据流:
//  - 4 个 AI provider(Agnes / DeepSeek / Doubao / Mock)
//  - 内置一个 Agnes 默认 API Key(代码 hardcodedDefaultAPIKey)
//  - 视频本地缓存路径 Documents/videos/{taskId}.mp4
//  - AI 助手对话(ChatSession / NoteComment 复用)
//  - 无任何追踪 / 分析 SDK
//

import SwiftUI

enum LegalType: String, CaseIterable {
    case privacy = "隐私协议"
    case terms = "服务条款"
}

struct LegalView: View {
    let type: LegalType

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                switch type {
                case .privacy:
                    privacyContent
                case .terms:
                    termsContent
                }
            }
            .padding(Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
        .background(Color.bg)
        .navigationTitle(type.rawValue)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Privacy Policy

    private var privacyContent: some View {
        Group {
            section("引言") {
                """
                RedPulse(以下简称"本应用"或"我们")尊重并保护您的隐私。本隐私协议旨在向您说明我们如何收集、使用、存储和保护您的个人信息。

                本应用采用本地优先(Local-First)架构,所有创作数据默认存储在您的设备本地(沙箱),开发者无法访问您的个人数据。我们不运营服务器,不收集您的个人信息。

                使用本应用即表示您已阅读并同意本隐私协议的条款。
                """
            }

            section("一、数据存储(全部在您设备本地)") {
                """
                本应用所有结构化数据存储在 SwiftData(SQLite)+ 沙箱文件系统中,卸载即永久删除,无法恢复。

                1.1 我们存储在您设备的数据

                • 产品信息:产品名称、卖点、目标人群、使用场景 — SwiftData 本地
                • 产品图片:产品照片、风格参考图 — 沙箱 Documents 目录
                • 生成记录(GenerationRecord):笔记标题、正文、标签、配图/视频 URL — SwiftData 本地
                • AI 对话(ChatSession + NoteComment):与 AI 助手的对话历史 — SwiftData 本地
                • 灵感条目(InspirationItem):创作灵感收集 — SwiftData 本地
                • 用户反馈(Feedback):文字、截图 — SwiftData 本地
                • 生成视频缓存:Documents/videos/{taskId}.mp4 — 沙箱 Documents 目录
                • 本地设置:外观模式、Tab 选择、质量模式
                • API 配置:API URL、API Key、模型名称 — UserDefaults

                1.2 我们不收集的信息

                • 手机号、真实姓名、电子邮件、物理地址
                • 通讯录、相册内容(除非您主动选择)
                • 设备标识符(IDFA、IMEI、IDFV)
                • 位置信息、IP 地址(除调用第三方 API 时由服务商接收)
                • 使用行为分析数据、点击记录
                • 本应用不集成任何追踪 / 分析 / 广告 SDK(Firebase / Sentry / AppsFlyer / 神策 / 友盟 均无)

                1.3 系统权限

                • 本应用当前版本不主动请求相册 / 相机权限;若未来增加图片选取功能,会先弹系统授权框
                """
            }

            section("二、第三方 AI 服务") {
                """
                本应用本身不运行 AI 模型。所有生成能力由以下第三方服务提供,您使用即视为同意对应服务商的服务条款与隐私政策:

                • Agnes AI(https://apihub.agnes-ai.com) — 文案 / 图片 / 视频生成
                • DeepSeek(https://www.deepseek.com) — 文案生成
                • 火山引擎方舟(https://www.volcengine.com) — Doubao 视频生成

                使用 AI 功能时,以下数据会发送至您配置的对应服务商:

                • 文案生成(Agnes / DeepSeek):产品名称、卖点、关键词、风格提示、对话消息
                • 图片生成(Agnes):产品描述文本、参考图、文生图提示词
                • 视频生成(Agnes / 方舟):视频提示词、参考图(最多 2 张,本地压缩至 1024px JPEG)

                开发者不缓存、不存储、不审查这些 API 请求和响应的内容。所有调用直接由您的设备发往您配置的 API 服务商。
                """
            }

            section("三、关于内置 API Key") {
                """
                本应用代码中嵌入了一个 Agnes API Key 作为默认配置,用于让用户在不填写自己 Key 时也能体验功能。该 Key 由开发者承担调用费用。

                建议长期使用的用户在「设置 → API 配置」填写自己的 Key:

                • 使用自己的 Key,调用更稳定、数据走自己的额度
                • 卸载本应用 = 内置 Key 不再被您的设备使用
                • 您填写的 Key 仅存储在本地 UserDefaults,**不加密**(沙箱受系统保护)

                本应用不收集您的 API Key 上传至任何服务器。
                """
            }

            section("四、数据安全") {
                """
                • 结构化数据:SwiftData(SQLite)— 沙箱隔离
                • 图片 / 视频文件:沙箱 Documents 目录 — 沙箱隔离
                • 零服务器架构:数据不上传至任何开发者控制的服务器
                • API Key 存储:明文 UserDefaults — 受沙箱保护,普通用户无法读取

                已知局限:
                • 共享设备时,其他用户可能看到您的生成历史
                • 设备未设锁屏密码时,设备丢失时他人可读取本地数据
                • UserDefaults 不抗高级攻击者(需设备物理访问 + 越狱)

                您可以在「设置 → 清除所有数据」一键删除全部本地数据。
                """
            }

            section("五、您的权利") {
                """
                由于数据全部存在本地,您拥有完全控制权:

                • 访问权:应用内可查看所有生成记录、对话历史、反馈
                • 更正权:应用内可直接编辑修改
                • 删除权:单条删除,或「设置 → 清除所有数据」一键清除
                • 撤回同意权:卸载应用 = 撤回对数据处理的同意
                • 离线使用:除 AI 生成功能外,本应用无需联网即可使用
                """
            }

            section("六、儿童隐私") {
                """
                本应用不面向 14 周岁以下的儿童。我们不会故意收集儿童的个人信息。如发现儿童未经监护人同意使用本应用,请联系开发者协助处理(尽管数据本就只存在本地)。
                """
            }

            section("七、隐私政策变更") {
                """
                本隐私政策可能不定期更新。重大变更会在应用首次启动时重新弹窗征求您的同意。版本号与日期见下方。

                版本 1.2 · 更新日期 2026-06-26
                """
            }
        }
    }

    // MARK: - Terms of Service

    private var termsContent: some View {
        Group {
            section("一、服务说明") {
                """
                RedPulse 是一款面向小红书创作者的 AI 辅助创作桌面工具(iPhone / iPad / Mac),提供产品库管理、AI 文案生成、笔记编辑、AI 配图与视频、历史记录管理、AI 助手对话等功能。

                本应用本身不运营 AI 模型,所有生成能力由第三方服务提供。本应用提供的是工具,而非内容。
                """
            }

            section("二、用户资格") {
                """
                • 您须年满 18 周岁,或已满 14 周岁且在监护人陪同下使用
                • 本应用无需注册或登录即可使用,首次启动同意本条款与隐私协议即可
                • 如代表法人或组织使用,您声明已获得相应授权
                """
            }

            section("三、用户行为规范") {
                """
                您承诺不会利用本应用从事以下行为:

                违法内容:
                • 反对宪法所确定的基本原则的
                • 危害国家安全、泄露国家秘密
                • 损害国家荣誉和利益
                • 煽动民族仇恨、民族歧视
                • 散布淫秽、色情、赌博、暴力、恐怖内容
                • 侮辱或诽谤他人、侵害他人合法权益

                知识产权侵权:
                • 侵犯他人著作权、商标权、专利权
                • 未经授权使用他人享有著作权的作品

                平台合规:
                • 不得用于绕过小红书、抖音等平台的 AI 内容标识规则
                • 不得用于虚假宣传、刷量、引流等违规行为

                滥用行为:
                • 逆向工程或反编译本应用(法律允许的合理审查除外)
                • 利用自动化工具批量调用、对第三方服务发起攻击

                您对通过本应用生成、编辑、发布的所有内容负全部责任。
                """
            }

            section("四、AI 生成内容风险提示") {
                """
                AI 生成内容可能存在以下风险,您同意在发布前进行人工审核:

                • 不准确性:AI 可能生成包含事实错误的内容
                • 偏见性:AI 模型可能包含训练数据中的偏见
                • 版权风险:生成内容可能与已有作品相似
                • 合规风险:可能无意中包含违反平台规则的内容
                • 时效性:训练数据有截止日期,信息可能过时
                """
            }

            section("五、第三方 API 与计费") {
                """
                5.1 API Provider

                本应用支持的第三方 AI 服务:
                • Agnes AI — 文案 / 图片 / 视频生成
                • DeepSeek — 文案生成
                • 火山引擎方舟 — Doubao 视频生成
                • OpenAI 兼容 API — 您可配置任意 OpenAI 兼容 endpoint(文案 / 图片生成)

                5.2 内置 API Key

                • 本应用内置了一个 Agnes 默认 Key,用于零配置体验
                • 使用内置 Key 产生的费用由开发者承担
                • 您可在「设置 → API 配置」填写自己的 Key 替换

                5.3 您自填的 Key

                • 您填写的 Key 仅存储在本地 UserDefaults,不加密但受沙箱保护
                • 您的 Key 由您保管,泄露导致的损失由您自行承担
                • API 费用从您的对应服务商账户扣除,与本应用无关

                5.4 服务可用性

                • 开发者不对第三方 API 服务的可用性、安全性、准确性负责
                • 第三方服务政策变更、模型下架、限流等,可能影响本应用功能
                """
            }

            section("六、知识产权") {
                """
                • 本应用的源代码、UI 设计、品牌标识、Logo 的知识产权归开发者所有
                • 您通过本应用**创作的内容**(经您编辑、修改的产物)知识产权归您
                • AI 服务原始输出的知识产权,以您使用 AI 服务商的服务条款为准
                • 本应用使用的开源组件,遵循对应开源协议
                """
            }

            section("七、服务的变更与终止") {
                """
                • 本应用可能随时更新功能、调整内置 Key 策略
                • 本应用可能因不可抗力、政策原因停止运营
                • 如停止运营,我们会**尽力提前 30 天**通过应用内公告通知
                • 停止运营不构成对您的违约或赔偿责任
                """
            }

            section("八、免责与责任限制") {
                """
                本应用按「现状」和「可用」基础提供。

                在法律允许的最大范围内,开发者不承担因以下情况导致的任何责任:

                • AI 生成内容的事实错误、遗漏或偏差
                • 生成内容被第三方平台判定违规、限流、封禁
                • 因第三方 API 故障、限流、计费导致的损失
                • 因设备故障、数据丢失导致的损失(建议定期备份)
                • 因不可抗力(自然灾害、政策变化、网络中断)导致的服务中断

                如本应用需承担赔偿责任,在法律允许范围内,总额不超过您为使用本应用实际支付的金额(如未支付则为 100 元人民币)。
                """
            }

            section("九、法律适用") {
                """
                本条款适用中华人民共和国法律。因本条款引起的争议,双方应友好协商解决;协商不成的,提交开发者所在地有管辖权的人民法院诉讼解决。
                """
            }

            section("十、联系方式") {
                """
                如有任何问题:

                • 项目仓库:[GitHub 仓库链接]
                • 反馈邮箱:[开发者邮箱]
                • 应用内:「我的 → 反馈」

                我们将在 7 个工作日内回复。

                版本 1.2 · 更新日期 2026-06-26
                """
            }
        }
    }

    // MARK: - Section Builder

    private func section(_ title: String, content: () -> String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.ink)

            Text(content())
                .font(.system(size: 14))
                .foregroundStyle(Color.ink2)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}