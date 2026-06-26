//
//  PhoneSimulatorView.swift
//  灵芯
//
//  iPhone simulator shell: dark bezel + Dynamic Island + Home indicator.
//  Wraps any content to look like it's running on a real iPhone.
//

import SwiftUI

// MARK: - Metrics (non-generic, avoids "static stored properties in generic types" error)

private enum PhoneMetrics {
    static let screenWidth: CGFloat = 393
    static let screenHeight: CGFloat = 852
    static let cornerRadius: CGFloat = 56
    static let bezelWidth: CGFloat = 6
}

// MARK: - PhoneSimulatorView

struct PhoneSimulatorView<Content: View>: View {
    let content: Content
    var hideBezel: Bool = false
    var scale: CGFloat = 1.0

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    private var frameWidth: CGFloat { PhoneMetrics.screenWidth * scale }
    private var frameHeight: CGFloat { PhoneMetrics.screenHeight * scale }
    private var contentWidth: CGFloat { (PhoneMetrics.screenWidth - PhoneMetrics.bezelWidth * 2) * scale }
    private var contentHeight: CGFloat { (PhoneMetrics.screenHeight - PhoneMetrics.bezelWidth * 2) * scale }

    var body: some View {
        if hideBezel {
            content
                .background(Color.black)
                .ignoresSafeArea()
                .overlay(alignment: .top) { dynamicIslandPill }
                .overlay(alignment: .bottom) { homeIndicator }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: PhoneMetrics.cornerRadius * scale, style: .continuous)
                    .fill(Color(white: 0.12))
                    .frame(width: frameWidth, height: frameHeight)
                    .shadow(color: .black.opacity(0.5), radius: 30 * scale, x: 0, y: 16 * scale)

                ZStack(alignment: .top) {
                    content
                        .frame(width: contentWidth, height: contentHeight)
                        .clipShape(RoundedRectangle(cornerRadius: (PhoneMetrics.cornerRadius - PhoneMetrics.bezelWidth) * scale, style: .continuous))

                    dynamicIslandPill
                        .padding(.top, 8 * scale)
                }
                .frame(width: contentWidth, height: contentHeight)

                sideButtons
            }
            .overlay(alignment: .bottom) {
                homeIndicator
                    .offset(y: -(PhoneMetrics.bezelWidth + 6) * scale)
            }
            .overlay(alignment: .topTrailing) {
                if !hideBezel {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 20 * scale, y: -20 * scale)
                }
            }
        }
    }

    // MARK: - Dynamic Island

    private var dynamicIslandPill: some View {
        Capsule()
            .fill(Color.black)
            .frame(width: 126 * scale, height: 34 * scale)
            .overlay(
                Capsule()
                    .stroke(Color(white: 0.2), lineWidth: 0.5)
            )
    }

    // MARK: - Home Indicator

    private var homeIndicator: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.35))
            .frame(width: 134 * scale, height: 5 * scale)
            .padding(.bottom, 8 * scale)
    }

    // MARK: - Side Buttons

    private var sideButtons: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2 * scale)
                .fill(Color(white: 0.25))
                .frame(width: 3 * scale, height: 60 * scale)
                .offset(x: frameWidth / 2 + 1.5 * scale, y: 80 * scale)

            RoundedRectangle(cornerRadius: 2 * scale)
                .fill(Color(white: 0.25))
                .frame(width: 3 * scale, height: 28 * scale)
                .offset(x: -frameWidth / 2 - 1.5 * scale, y: -60 * scale)

            RoundedRectangle(cornerRadius: 2 * scale)
                .fill(Color(white: 0.25))
                .frame(width: 3 * scale, height: 42 * scale)
                .offset(x: -frameWidth / 2 - 1.5 * scale, y: -20 * scale)

            RoundedRectangle(cornerRadius: 2 * scale)
                .fill(Color(white: 0.25))
                .frame(width: 3 * scale, height: 42 * scale)
                .offset(x: -frameWidth / 2 - 1.5 * scale, y: 28 * scale)
        }
    }
}

// MARK: - PhonePreviewSheet

struct PhonePreviewSheet<Content: View>: View {
    let content: Content
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            if sizeClass == .compact {
                PhoneSimulatorView(content: content, hideBezel: true)
                    .ignoresSafeArea()
            } else {
                PhoneSimulatorView(content: content, scale: 0.62)
            }
        }
    }
}
