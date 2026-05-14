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
    
    init(url: URL, title: String = "About") {
        self.url = url
        self.title = title
    }
    
    var body: some View {
        WebContentView(url: url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WebContentView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> WKWebView {
        WKWebView(frame: .zero)
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        webView.load(URLRequest(url: url))
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
