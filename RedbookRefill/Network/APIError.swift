//
//  APIError.swift
//  RedPulse
//
//  Mirrors the error code contract in requirements V3.2 §10.1. Each case
//  carries a Chinese user-facing message via `userMessage`.
//

import Foundation

enum APIError: Error, Equatable {
    case invalidParam      // E_INVALID_PARAM   400
    case signInvalid       // E_SIGN_INVALID    401
    case rateLimit         // E_RATE_LIMIT      429
    case dailyQuota        // E_DAILY_QUOTA     429
    case guestQuota        // E_GUEST_QUOTA     429
    case llmParse          // E_LLM_PARSE       502
    case llmFormat         // E_LLM_FORMAT      502
    case imageAnalysis     // E_IMAGE_ANALYSIS  502
    case llmUnavailable    // E_LLM_UNAVAILABLE 503
    case timeout           // E_TIMEOUT         504
    case network           // E_NETWORK         client side

    var userMessage: String {
        switch self {
        case .invalidParam:   return "输入参数有误，请检查"
        case .signInvalid:    return "请求异常，请重启 App"
        case .rateLimit:      return "生成太频繁啦，休息 1 分钟再来"
        case .dailyQuota:     return "今日生成次数已用完，明日再来"
        case .guestQuota:     return "访客体验次数已用完，登录后无限制生成"
        case .llmParse:       return "生成失败，点击重试"
        case .llmFormat:      return "生成格式异常，点击重试"
        case .imageAnalysis:  return "图片处理失败，可尝试减少图片"
        case .llmUnavailable: return "服务繁忙，稍后再试"
        case .timeout:        return "网络较慢，点击重试"
        case .network:        return "请检查网络连接"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .rateLimit, .llmParse, .llmFormat, .imageAnalysis,
             .llmUnavailable, .timeout, .network:
            return true
        case .invalidParam, .signInvalid, .dailyQuota, .guestQuota:
            return false
        }
    }
}
