//
//  LegalView.swift
//  RedPulse
//
//  隐私协议与服务条款
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
                RedPulse（以下简称"本应用"或"我们"）尊重并保护您的隐私。本隐私协议旨在向您说明我们如何收集、使用、存储和保护您的个人信息。本应用采用本地优先（Local-First）架构，您的创作数据默认存储在设备本地，开发者无法访问您的个人数据。
                
                使用本应用即表示您已阅读并同意本隐私协议的条款。
                """
            }
            
            section("一、信息收集") {
                """
                1.1 您主动提供的信息
                
                • 登录凭证：手机号、密码 — 用于本地身份验证，Keychain 加密存储
                • 产品信息：产品名称、核心卖点、目标人群、使用场景 — SwiftData 本地存储
                • 产品图片：产品照片、风格参考图（最多各5张） — 沙盒 Documents 目录
                • 生成记录：笔记标题、正文、标签、配图建议、优化建议、彩蛋金句等 — SwiftData 本地存储
                • 意见反馈：文字（≤200字）、截图（≤3张） — 本地存储
                • AI 配置：API URL、API Key、模型名称 — UserDefaults 存储
                
                1.2 自动收集的信息
                
                • 本地设置：外观模式、Tab选择、质量模式
                • 调试日志：操作记录、错误信息（仅本地查看）
                • 生成统计：生成次数、访客剩余次数
                
                1.3 我们不收集的信息
                
                • 真实姓名、电子邮件、物理地址
                • 通讯录、相册内容（除非您主动选择）
                • 设备标识符（IDFA、IMEI）
                • 位置信息
                • 使用行为分析数据
                • 本应用不集成任何第三方SDK
                """
            }
            
            section("二、数据使用") {
                """
                您提供的所有数据仅用于本地用途：验证登录身份、管理产品库、生成和编辑笔记草稿、提供历史记录。
                
                API 数据传输：当您使用 AI 生成功能时，以下数据会被发送至您自行配置的第三方 API：
                
                • 文案生成（LLM API）：产品名称和卖点、广告类型、关键词和风格提示、生成上下文
                • 图片/视频生成（即梦/火山引擎）：产品图片描述文本、风格参考图描述、文生图提示词
                
                开发者不缓存、不存储、不审查这些 API 请求和响应的内容。API 调用直接由您的设备发往您配置的 API 服务商。
                """
            }
            
            section("三、数据存储与安全") {
                """
                • 登录凭证：Keychain（iOS钥匙串）— 系统级加密
                • 结构化数据：SwiftData（SQLite）— 沙盒隔离
                • 图片文件：沙盒 Documents 目录 — 沙盒隔离
                • 零服务器架构：您的数据不上传至任何开发者控制的服务器
                
                您可以在「设置」→「清除所有数据」一键删除全部本地数据。
                """
            }
            
            section("四、数据共享") {
                """
                我们不会向任何第三方出售、出租或共享您的个人数据。唯一的数据传输场景是您主动触发的 AI API 调用（详见第二节）。
                
                第三方服务：
                • DeepSeek API — AI 文案生成 — https://platform.deepseek.com/privacy
                • OpenAI 兼容 API — AI 文案生成 — 取决于您配置的提供商
                • 火山引擎方舟 — AI 图片/视频生成 — https://www.volcengine.com/docs/8431
                """
            }
            
            section("五、您的权利") {
                """
                • 访问权：直接在应用内查看您的数据
                • 更正权：在应用内直接编辑修改
                • 删除权：单独删除或「设置→清除所有数据」
                • 撤回同意权：在系统设置中管理相册/相机权限
                • 注销权：卸载应用即注销所有本地数据
                """
            }
            
            section("六、儿童隐私") {
                """
                本应用不面向 13 周岁以下的儿童。我们不会故意收集儿童的个人信息。
                """
            }
            
            section("七、隐私政策变更") {
                """
                本隐私政策可能不时更新。重大变更时将在应用内通知。
                
                版本 1.0 · 更新日期 2026-05-26
                """
            }
        }
    }
    
    // MARK: - Terms of Service
    
    private var termsContent: some View {
        Group {
            section("一、服务说明") {
                """
                RedPulse 是一款面向小红书创作者的 AI 辅助创作工具，提供产品库管理、AI 文案生成、笔记编辑、AI 配图与视频、历史记录管理等本地化功能。
                
                本应用提供的是工具服务，而非内容服务。所有 AI 生成功能依赖于您自行配置的第三方 API。
                """
            }
            
            section("二、用户资格") {
                """
                • 您须年满 18 周岁，或已满 14 周岁且在监护人陪同下使用
                • 访客模式：无需登录，累计生成限制（当前为 3 次）
                • 登录模式：使用预设账号登录，无生成次数限制
                """
            }
            
            section("三、用户行为规范") {
                """
                您承诺不会利用本应用从事以下行为：
                
                违法内容：
                • 反对宪法所确定的基本原则的
                • 危害国家安全、泄露国家秘密
                • 损害国家荣誉和利益
                • 煽动民族仇恨、民族歧视
                • 散布淫秽、色情、赌博、暴力内容
                • 侮辱或诽谤他人、侵害他人合法权益
                
                知识产权侵权：
                • 侵犯他人著作权、商标权、专利权
                • 未经授权使用他人享有著作权的作品
                
                滥用行为：
                • 逆向工程或反编译本应用
                • 利用自动化工具批量调用
                • 绕过访客限制机制
                
                您对通过本应用生成的所有内容负全部责任。
                """
            }
            
            section("四、AI 生成内容风险提示") {
                """
                AI 生成内容可能存在以下风险，您同意在发布前进行人工审核：
                • 不准确性：AI 可能生成包含事实错误的内容
                • 偏见性：AI 模型可能包含训练数据中的偏见
                • 版权风险：生成内容可能与已有作品相似
                • 合规风险：可能无意中包含违反平台规则的内容
                """
            }
            
            section("五、第三方 API") {
                """
                • 您需自行获取并配置 AI 服务的 API Key
                • API 费用由您自行承担
                • 您应妥善保管 API Key，泄露导致的损失由您自行承担
                • 开发者不对第三方 API 服务的可用性、安全性负责
                """
            }
            
            section("六、知识产权") {
                """
                • 本应用的源代码、UI 设计、品牌标识的知识产权归开发者所有
                • 您通过本应用生成的内容的知识产权归您所有
                • AI 生成内容的知识产权归属以您使用的 AI 服务商的条款为准
                """
            }
            
            section("七、免责声明") {
                """
                本应用按「现状」和「可用」基础提供。
                
                我们不承担因以下情况导致的任何责任：
                • AI 生成内容的事实错误或遗漏
                • 生成内容被第三方平台判定违规
                • 数据丢失（建议定期备份）
                • 第三方 API 服务故障
                
                在法律允许的最大范围内，开发者对您的全部赔偿责任总额不超过 100 元人民币。
                """
            }
            
            section("八、法律适用") {
                """
                本条款适用中华人民共和国法律。因本条款引起的争议，双方应友好协商解决；协商不成的，提交开发者所在地有管辖权的人民法院诉讼解决。
                """
            }
            
            section("九、联系方式") {
                """
                如有任何问题，请通过应用内「我的」→「反馈」联系我们。我们将在 7 个工作日内回复。
                
                版本 1.0 · 更新日期 2026-05-26
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
