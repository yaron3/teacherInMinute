//
//  AboutWebView.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//

import SwiftUI

#if canImport(WebKit) && canImport(UIKit)
import WebKit

struct AboutWebView: View {
    let url: URL
    let title: String
    /// The back button's name, for Instant Teacher's header.
    let backLabel: String
    @Environment(\.colorScheme) private var colorScheme

    init(url: URL, title: String = "About", backLabel: String = "") {
        self.url = url
        self.title = title
        self.backLabel = backLabel
    }

    var body: some View {
        if AppTheme.isBrand {
            // Instant Teacher's header over the page, which is its own
            // document: set on white, as it is written to be read.
            BrandSubpage(label: "", title: title, backLabel: backLabel, scrolls: false) {
                WebContentView(url: url, colorScheme: .light)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.bottom, 20)
                    .trackScreen(AnalyticsScreen.about)
            }
        } else {
            WebContentView(url: url, colorScheme: colorScheme)
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .trackScreen(AnalyticsScreen.about)
        }
    }
}

private struct WebContentView: UIViewRepresentable {
    let url: URL
    let colorScheme: ColorScheme

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if webView.url != url {
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        }
    }
}
#else
struct AboutWebView: View {
    let url: URL
    let title: String
    let backLabel: String
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    init(url: URL, title: String = "About", backLabel: String = "") {
        self.url = url
        self.title = title
        self.backLabel = backLabel
    }

    var body: some View {
        if AppTheme.isBrand {
            BrandSubpage(label: "", title: title, backLabel: backLabel) {
                Link(destination: url) {
                    Text("Open \(title)")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.brandBackgroundTop)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(theme.brandActionBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .trackScreen(AnalyticsScreen.about)
            }
        } else {
            Link("Open \(title)", destination: url)
                .font(.system(size: 16, weight: .semibold))
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .trackScreen(AnalyticsScreen.about)
        }
    }
}
#endif
