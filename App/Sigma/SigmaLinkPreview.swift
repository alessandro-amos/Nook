// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaLinkPreview.swift
//  Sigma
//
//  Prévia de link: com ⌘ pressionado sobre um link, um cartão junto do cursor mostra a página
//  de destino (snapshot de uma web view fora da tela, com os cookies do workspace) e o domínio.
//

import AppKit
import SwiftUI
import WebKit
import NookWeb

/// Gera e guarda snapshots de páginas para a prévia. Uma web view fora da tela por vez.
@MainActor
@Observable
final class SigmaLinkSnapshots: NSObject, WKNavigationDelegate {
    static let shared = SigmaLinkSnapshots()

    private(set) var images: [URL: NSImage] = [:]
    @ObservationIgnored private var webView: WKWebView?
    @ObservationIgnored private var loading: URL?
    @ObservationIgnored private var order: [URL] = []

    private static let pageSize = CGSize(width: 1280, height: 800)
    private static let limit = 20

    func request(_ url: URL, dataStore: WKWebsiteDataStore?) {
        guard images[url] == nil, loading != url, url.scheme == "http" || url.scheme == "https" else { return }
        loading = url
        let config = WKWebViewConfiguration()
        if let dataStore { config.websiteDataStore = dataStore }
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: CGRect(origin: .zero, size: Self.pageSize), configuration: config)
        view.navigationDelegate = self
        view.customUserAgent = nil
        webView = view
        view.load(URLRequest(url: url, timeoutInterval: 15))
    }

    func cancel() {
        webView?.stopLoading()
        webView = nil
        loading = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            guard webView === self.webView, let url = loading else { return }
            // Um instante para fontes e imagens acima da dobra.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, webView === self.webView else { return }
                webView.takeSnapshot(with: nil) { image, _ in
                    MainActor.assumeIsolated {
                        if let image { self.store(image, for: url) }
                        self.cancel()
                    }
                }
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { if webView === self.webView { cancel() } }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { if webView === self.webView { cancel() } }
    }

    private func store(_ image: NSImage, for url: URL) {
        images[url] = image
        order.append(url)
        if order.count > Self.limit { images[order.removeFirst()] = nil }
    }
}

/// Camada sobre a página: posiciona o cartão junto do cursor, sem sair da área.
struct SigmaLinkPreviewLayer: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    let url: URL
    @State private var pointer: CGPoint?

    private let cardSize = CGSize(width: 400, height: 250)

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .global)
            Group {
                if let pointer {
                    let local = CGPoint(x: pointer.x - frame.minX, y: pointer.y - frame.minY)
                    let x = min(max(local.x + 12, 8), proxy.size.width - cardSize.width - 8)
                    let below = local.y + 24 + cardSize.height < proxy.size.height
                    let y = below ? local.y + 24 : max(local.y - cardSize.height - 16, 8)
                    SigmaLinkPreviewCard(url: url)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .offset(x: x, y: y)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear { pointer = Self.pointerInWindow() }
            .onChange(of: url) { _, _ in pointer = Self.pointerInWindow() }
        }
        .task(id: url) {
            let session = browserManager.tabs.controllableSession(in: windowState)
            let store = session.flatMap { browserManager.getWebView(for: $0.itemID, in: windowState.id) }?
                .configuration.websiteDataStore
            SigmaLinkSnapshots.shared.request(url, dataStore: store)
        }
        .onDisappear { SigmaLinkSnapshots.shared.cancel() }
    }

    /// Cursor no espaço global do SwiftUI (origem no canto superior esquerdo da janela).
    private static func pointerInWindow() -> CGPoint? {
        guard let window = NSApp.keyWindow, let content = window.contentView else { return nil }
        let point = window.mouseLocationOutsideOfEventStream
        return CGPoint(x: point.x, y: content.bounds.height - point.y)
    }
}

struct SigmaLinkPreviewCard: View {
    let url: URL

    var body: some View {
        let image = SigmaLinkSnapshots.shared.images[url]
        ZStack(alignment: .bottomLeading) {
            SigmaPalette.content
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
                    .transition(.opacity)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(url.host ?? url.absoluteString)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.55)))
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .animation(SigmaMotion.fade, value: image != nil)
    }
}
