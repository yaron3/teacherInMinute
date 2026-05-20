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
    @Environment(\.colorScheme) private var colorScheme

    init(url: URL, title: String = "About") {
        self.url = url
        self.title = title
    }

    var body: some View {
        WebContentView(url: url, colorScheme: colorScheme)
            .background(Color(.systemBackground))
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(LocalizationSupport.localized(title))
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(AnalyticsScreen.about)
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
    
    init(url: URL, title: String = "About") {
        self.url = url
        self.title = title
    }
    
    var body: some View {
        Link("Open \(title)", destination: url)
            .font(.system(size: 16, weight: .semibold))
            .navigationTitle(LocalizationSupport.localized(title))
            .navigationBarTitleDisplayMode(.inline)
            .trackScreen(AnalyticsScreen.about)
    }
}
#endif
