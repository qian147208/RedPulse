//
//  LoginView.swift
//  RedPulse
//
//  登录页 — 现代简洁风格
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore
    
    @State private var account: String = ""
    @State private var password: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    
    var body: some View {
        ZStack {
            Color.bg.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)
                    
                    // Logo 区
                    logoSection
                        .padding(.bottom, 48)
                    
                    // 欢迎文案
                    welcomeSection
                        .padding(.bottom, 40)
                    
                    // 输入表单
                    formSection
                        .padding(.horizontal, Adaptive.horizontalPageMargin + 8)
                    
                    Spacer(minLength: 40)
                    
                    // 页脚
                    footerSection
                        .padding(.horizontal, Adaptive.horizontalPageMargin + 8)
                        .padding(.bottom, 40)
                }
                .frame(minHeight: ScreenMetrics.shared.height - 60)
            }
            .scrollIndicators(.hidden)
            
            if showError { toastOverlay }
            if isLoading { loadingOverlay }
        }
    }
    
    // MARK: - Logo
    
    private var logoSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.brand, Color.brand.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 88, height: 88)
                    .shadow(color: Color.brand.opacity(0.3), radius: 20, x: 0, y: 8)
                
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            Text("RedPulse")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(Color.ink)
            
            Text("AI 小红书创作助手")
                .font(.system(size: 15))
                .foregroundStyle(Color.ink3)
        }
    }
    
    // MARK: - Welcome
    
    private var welcomeSection: some View {
        VStack(spacing: 8) {
            Text("欢迎回来")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.ink)
            
            Text("输入账号开始创作")
                .font(.system(size: 15))
                .foregroundStyle(Color.ink3)
        }
    }
    
    // MARK: - Form
    
    private var formSection: some View {
        VStack(spacing: 16) {
            // 账号
            VStack(alignment: .leading, spacing: 6) {
                Text("账号")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ink2)
                
                TextField("请输入手机号", text: $account)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    .textContentType(.telephoneNumber)
                    #endif
                    .font(.system(size: 17))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.border, lineWidth: BorderWidth.thin)
                    )
            }
            
            // 密码
            VStack(alignment: .leading, spacing: 6) {
                Text("密码")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ink2)
                
                SecureField("请输入密码", text: $password)
                    #if os(iOS)
                    .textContentType(.password)
                    #endif
                    .font(.system(size: 17))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.border, lineWidth: BorderWidth.thin)
                    )
            }
            
            // 提示
            Text("默认账号 10000000000 / 密码 000000")
                .font(.system(size: 12))
                .foregroundStyle(Color.ink4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            
            // 登录按钮
            Button(action: handleLogin) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.9)
                    }
                    Text("登录")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.brand, Color.brand.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color.brand.opacity(0.25), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .padding(.top, 8)
            
            // 访客入口
            Button(action: handleGuest) {
                Text("先体验，无需登录")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.ink3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }
    
    // MARK: - Footer
    
    private var footerSection: some View {
        VStack(spacing: 16) {
            Text("登录即代表同意用户协议和隐私政策")
                .font(.system(size: 12))
                .foregroundStyle(Color.ink4)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Overlays
    
    private var loadingOverlay: some View {
        Color.black.opacity(0.15)
            .ignoresSafeArea()
            .overlay {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(Color.brand)
            }
    }
    
    private var toastOverlay: some View {
        VStack {
            Spacer()
            Text(errorMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Capsule().fill(Color.black.opacity(0.85)))
                .padding(.bottom, 120)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showError)
    }
    
    // MARK: - Actions
    
    private func handleLogin() {
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let ok = authStore.login(account: account, password: password)
            isLoading = false
            if !ok { showToast("账号或密码错误") }
        }
    }
    
    private func handleGuest() { authStore.enterGuestMode() }
    
    private func showToast(_ msg: String) {
        errorMessage = msg
        withAnimation { showError = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { showError = false }
        }
    }
}
