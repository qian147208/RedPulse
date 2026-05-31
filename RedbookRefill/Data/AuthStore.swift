//
//  AuthStore.swift
//  RedPulse
//
//  Tracks login / guest state. Persists token + account in Keychain and the
//  guest generation counter in UserDefaults. Default credentials per V3.2
//  module 7: account `10000000000` / password `000000`.
//
//  V3.2 update: guest limit changed from single 3-count to dual rolling
//  window — 6 generations per day AND 18 per week.
//

import Foundation
import Observation

@Observable
final class AuthStore {
    // Persisted credentials (hard-coded prototype account)
    private static let validAccount = "10000000000"
    private static let validPassword = "000000"

    // Keys
    private static let tokenKey = "auth.token"
    private static let accountKey = "auth.account"
    private static let guestModeKey = "guest.mode.active"
    private static let dailyCountKey = "guest.daily.count"
    private static let dailyDateKey = "guest.daily.date"   // yyyy-MM-dd
    private static let weeklyCountKey = "guest.weekly.count"
    private static let weeklyStartKey = "guest.weekly.start" // yyyy-MM-dd (Monday)

    // Guest limits (V3.2 rolling window)
    static let guestDailyLimit = 6
    static let guestWeeklyLimit = 18

    // Back-compat exposed limit (used by some UI strings that want a single
    // headline number). Now equals the daily cap.
    static let guestGenerationLimit = guestDailyLimit

    // Observable state
    var isLoggedIn: Bool = false
    var isGuest: Bool = false
    var guestDailyCount: Int = 0
    var guestWeeklyCount: Int = 0

    /// 当前账号手机号（从 Keychain 恢复）。未登录时为空。
    var phone: String = ""
    /// 用户邮箱，落到 UserDefaults，setter 自动同步。
    var email: String = "" {
        didSet { UserDefaults.standard.set(email, forKey: Self.emailKey) }
    }
    private static let emailKey = "user.email"

    // Back-compat: legacy callers read `guestGenerationCount` to compute
    // remaining quota. Keep returning the daily count (the tighter bound for
    // any single day).
    var guestGenerationCount: Int {
        get { guestDailyCount }
        set { guestDailyCount = newValue }
    }

    /// Min of remaining daily quota and remaining weekly quota — what the
    /// user actually has left right now.
    var guestRemaining: Int {
        let dailyRemain = max(0, Self.guestDailyLimit - guestDailyCount)
        let weeklyRemain = max(0, Self.guestWeeklyLimit - guestWeeklyCount)
        return min(dailyRemain, weeklyRemain)
    }

    init() {
        restore()
    }

    // MARK: - Restore

    private func restore() {
        // 恢复 email（即使访客也读，因为 email 不绑定账号）
        email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""

        if let token = KeychainHelper.read(key: Self.tokenKey), !token.isEmpty {
            isLoggedIn = true
            isGuest = false
            phone = KeychainHelper.read(key: Self.accountKey) ?? ""
            return
        }

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.guestModeKey) {
            isGuest = true
            isLoggedIn = false
            rollWindowsAndLoadCounts()
        }
    }

    // MARK: - Login

    func login(account: String, password: String) -> Bool {
        guard account == Self.validAccount, password == Self.validPassword else {
            DebugLog.shared.warn(.auth, "login rejected", details: "account=\(account)")
            return false
        }

        let token = UUID().uuidString
        KeychainHelper.save(token, key: Self.tokenKey)
        KeychainHelper.save(account, key: Self.accountKey)

        isLoggedIn = true
        isGuest = false
        phone = account

        UserDefaults.standard.set(false, forKey: Self.guestModeKey)

        DebugLog.shared.info(.auth, "login success", details: "account=\(account)")
        return true
    }

    // MARK: - Guest

    func enterGuestMode() {
        isGuest = true
        isLoggedIn = false
        UserDefaults.standard.set(true, forKey: Self.guestModeKey)
        rollWindowsAndLoadCounts()
        DebugLog.shared.info(.auth, "enter guest mode", details: "daily=\(guestDailyCount)/\(Self.guestDailyLimit), weekly=\(guestWeeklyCount)/\(Self.guestWeeklyLimit)")
    }

    func incrementGuestCount() {
        // First make sure counters are valid for the current day/week.
        rollWindowsAndLoadCounts()

        let defaults = UserDefaults.standard
        guestDailyCount += 1
        guestWeeklyCount += 1
        defaults.set(guestDailyCount, forKey: Self.dailyCountKey)
        defaults.set(guestWeeklyCount, forKey: Self.weeklyCountKey)
    }

    func canGuestGenerate() -> Bool {
        rollWindowsAndLoadCounts()
        return guestDailyCount < Self.guestDailyLimit
            && guestWeeklyCount < Self.guestWeeklyLimit
    }

    // MARK: - Logout

    func logout() {
        KeychainHelper.delete(key: Self.tokenKey)
        KeychainHelper.delete(key: Self.accountKey)
        isLoggedIn = false
        isGuest = false
        phone = ""
        DebugLog.shared.info(.auth, "logout")
    }

    // MARK: - Rolling window bookkeeping

    /// If today is a new day relative to the stored daily date, reset the
    /// daily count. If we're in a new week relative to the stored week
    /// start, reset the weekly count. Persist any resets.
    private func rollWindowsAndLoadCounts() {
        let defaults = UserDefaults.standard
        let today = Self.dayString(for: Date())
        let weekStart = Self.mondayString(for: Date())

        let storedDay = defaults.string(forKey: Self.dailyDateKey)
        if storedDay != today {
            defaults.set(today, forKey: Self.dailyDateKey)
            defaults.set(0, forKey: Self.dailyCountKey)
        }
        guestDailyCount = defaults.integer(forKey: Self.dailyCountKey)

        let storedWeek = defaults.string(forKey: Self.weeklyStartKey)
        if storedWeek != weekStart {
            defaults.set(weekStart, forKey: Self.weeklyStartKey)
            defaults.set(0, forKey: Self.weeklyCountKey)
        }
        guestWeeklyCount = defaults.integer(forKey: Self.weeklyCountKey)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    private static func dayString(for date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// Returns yyyy-MM-dd for the Monday of the week containing `date`,
    /// using the user's current calendar (ISO 8601 week boundaries).
    private static func mondayString(for date: Date) -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let monday = cal.date(from: comps) ?? date
        return dateFormatter.string(from: monday)
    }
}
