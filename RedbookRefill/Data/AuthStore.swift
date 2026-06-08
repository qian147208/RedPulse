//
//  AuthStore.swift
//  RedPulse
//
//  Simplified: app is always "logged in" — no auth gate.
//  Kept for backward compatibility with existing UI code that reads authStore.
//

import Foundation
import Observation

@Observable
final class AuthStore {
    var isLoggedIn: Bool = true
    var isGuest: Bool = false
    var guestDailyCount: Int = 0
    var guestWeeklyCount: Int = 0
    var guestGenerationCount: Int { guestDailyCount }
    var guestRemaining: Int { Int.max }
    var phone: String = ""
    var email: String = "" {
        didSet { UserDefaults.standard.set(email, forKey: Self.emailKey) }
    }
    private static let emailKey = "user.email"

    init() {
        email = UserDefaults.standard.string(forKey: Self.emailKey) ?? ""
    }

    func login(account: String, password: String) -> Bool { true }
    func enterGuestMode() {}
    func incrementGuestCount() {}
    func canGuestGenerate() -> Bool { true }
    func logout() {}
}
