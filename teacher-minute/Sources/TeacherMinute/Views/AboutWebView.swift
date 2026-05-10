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
    
    var body: some View {
        NavigationStack {
            WebContentView(url: url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("About")
                .navigationBarTitleDisplayMode(.inline)
        }
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
    
    var body: some View {
        NavigationStack {
            Link("Open About", destination: url)
                .font(.system(size: 16, weight: .semibold))
                .navigationTitle("About")
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
