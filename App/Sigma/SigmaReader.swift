// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaReader.swift
//  Sigma
//
//  Modo leitura e tradução da pílula de URL. O leitor extrai título e parágrafos da página e
//  mostra numa folha limpa sobre o conteúdo; a tradução abre a página pelo Google Tradutor.
//

import SwiftUI
import WebKit
import NookWeb

struct SigmaReaderContent: Equatable {
    var title: String
    var site: String
    var paragraphs: [String]
}

@MainActor
enum SigmaReader {
    /// Pega o artigo principal: <article>, <main> ou o corpo; só parágrafos e títulos com texto.
    private static let script = """
    (() => {
      const root = document.querySelector('article') || document.querySelector('main') || document.body;
      const nodes = Array.from(root.querySelectorAll('h1, h2, h3, p, li, blockquote'));
      const text = nodes
        .map(n => ({ tag: n.tagName, text: (n.innerText || '').trim() }))
        .filter(n => /^H[1-3]$/.test(n.tag) ? n.text.length > 0 : n.text.length > 40)
        .map(n => n.text);
      return JSON.stringify({ title: document.title, paragraphs: text.slice(0, 400) });
    })()
    """

    static func open(session: PageSession, webView: WKWebView?, window: BrowserWindowState) {
        guard let webView else { return }
        webView.evaluateJavaScript(script) { result, _ in
            MainActor.assumeIsolated {
                guard let json = result as? String, let data = json.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                let paragraphs = (object["paragraphs"] as? [String]) ?? []
                guard !paragraphs.isEmpty else {
                    SigmaUIState.of(window).notify("Não encontrei texto para ler nesta página")
                    return
                }
                let content = SigmaReaderContent(title: object["title"] as? String ?? session.title,
                                                 site: session.url.host ?? "", paragraphs: paragraphs)
                withAnimation(SigmaMotion.fade) { SigmaUIState.of(window).reader = content }
            }
        }
    }

    static func translationURL(for url: URL) -> URL? {
        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        var components = URLComponents(string: "https://translate.google.com/translate")
        components?.queryItems = [
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: Locale.current.language.languageCode?.identifier ?? "pt"),
            URLQueryItem(name: "u", value: url.absoluteString),
        ]
        return components?.url
    }
}

struct SigmaReaderView: View {
    let content: SigmaReaderContent
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SigmaPalette.content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(content.site)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SigmaPalette.mandarin)
                    Text(content.title)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(0.9))
                    ForEach(Array(content.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(.system(size: 19))
                            .lineSpacing(6)
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.vertical, 60)
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity)
            }
            SigmaChromeButton(systemName: "xmark",
                              tooltip: SigmaTooltip(text: "Sair do modo leitura", keys: ["esc"], placement: .below), action: onClose)
                .padding(12)
        }
        .onExitCommand(perform: onClose)
    }
}
