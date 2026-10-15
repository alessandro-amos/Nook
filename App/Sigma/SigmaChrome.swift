// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaChrome.swift
//  Sigma
//
//  Layout da janela do Sigma: faixa do topo de 48pt (semáforos, sidebar, clean up, busca,
//  pílula de URL), sidebar abaixo dela e a página num cartão arredondado com margem de 8.
//

import AppKit
import SwiftUI
import WebKit
import NookTabsCore
import NookWeb
import NookUI

/// Raiz do layout do Sigma. `content` é a área da página (WebsiteView e companhia).
struct SigmaWindowLayout<Content: View, Trailing: View>: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @ViewBuilder let content: () -> Content
    /// Painel à direita da página (chat da Airis).
    @ViewBuilder let trailing: () -> Trailing

    private var trailingWidth: CGFloat {
        windowState.isSidebarAIChatVisible ? windowState.aiSidebarWidth + SigmaMetrics.contentInset : 0
    }

    private var contentX: CGFloat {
        windowState.isSidebarVisible ? SigmaMetrics.sidebarWidth : SigmaMetrics.contentInset
    }

    var body: some View {
        @Bindable var ui = SigmaUIState.of(windowState)
        ZStack(alignment: .topLeading) {
            SigmaPalette.zero
                .overlay(windowState.isIncognito ? Color.purple.opacity(0.12) : Color.clear)
                .ignoresSafeArea()
                .backgroundDraggable()

            // Cartão da página: recorte raio 8 recuado 1,5; moldura `PanelOverlay` (traço primary 5%,
            // sombra branca 0,1 a 3%).
            content()
                .clipShape(RoundedRectangle(cornerRadius: SigmaMetrics.pageRadius, style: .continuous).inset(by: 1.5))
                .overlay(
                    RoundedRectangle(cornerRadius: SigmaMetrics.pageRadius, style: .continuous)
                        .inset(by: 0.5)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .shadow(color: Color(.sRGB, white: 0.1, opacity: 1).opacity(0.03), radius: 3, x: 0, y: 1)
                .overlay {
                    if ui.confirmingCleanUp {
                        ZStack {
                            Color.black.opacity(0.18)
                                .onTapGesture { ui.confirmingCleanUp = false }
                            SigmaCleanUpConfirm(
                                count: SigmaActions(tabs: tabs, window: windowState).cleanableItems.count,
                                space: SigmaActions(tabs: tabs, window: windowState).currentSpace,
                                onCancel: { ui.confirmingCleanUp = false },
                                onConfirm: { SigmaActions(tabs: tabs, window: windowState).cleanUp() }
                            )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: SigmaMetrics.pageRadius, style: .continuous).inset(by: 1.5))
                        .transition(.opacity)
                    }
                }
                .padding(.leading, contentX)
                .padding(.top, SigmaMetrics.chromeHeight)
                .padding(.bottom, SigmaMetrics.contentInset)
                .padding(.trailing, SigmaMetrics.contentInset + trailingWidth)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.top, SigmaMetrics.chromeHeight)
            .padding([.trailing, .bottom], SigmaMetrics.contentInset)

            if windowState.isSidebarVisible {
                SigmaSidebar()
                    .padding(.top, SigmaMetrics.chromeHeight)
                    .padding(.bottom, SigmaMetrics.contentInset)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            SigmaChromeBar(contentX: contentX)

            if let notice = ui.notice {
                SigmaNoticeView(notice: notice)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, contentX)
                    .padding(.top, SigmaMetrics.chromeHeight + 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let request = ui.commandRequest {
                SigmaPalette.modalDim
                    .ignoresSafeArea()
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.spring(response: 0.4, dampingFraction: 1)),
                        removal: .opacity.animation(.spring(response: 0.12, dampingFraction: 1))
                    ))
                    .onTapGesture { ui.commandRequest = nil }
                // Painel a 26% da altura da janela, com largura min(janela, 822).
                GeometryReader { proxy in
                    SigmaCommandBar(request: request) { withAnimation(SigmaMotion.standard) { ui.commandRequest = nil } }
                        .frame(width: min(proxy.size.width, 822))
                        .padding(.top, proxy.size.height * 0.26)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .zIndex(2)
                .transition(.opacity)
            }

            if ui.showingCheatSheet {
                SigmaPalette.focusOverlay
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { ui.showingCheatSheet = false }
                SigmaCheatSheet()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .onExitCommand { ui.showingCheatSheet = false }
            }
        }
        .sigmaTooltipLayer()
        .animation(SigmaMotion.fade, value: ui.showingCheatSheet)
        .animation(SigmaMotion.standard, value: ui.commandRequest)
        .animation(SigmaMotion.fade, value: ui.confirmingCleanUp)
        .animation(SigmaMotion.standard, value: windowState.isSidebarAIChatVisible)
        .animation(SigmaMotion.standard, value: windowState.isSidebarVisible)
        .ignoresSafeArea(.container, edges: .top)
    }
}

/// Faixa do topo (48pt).
struct SigmaChromeBar: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    let contentX: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            SigmaTrafficLights()

            SigmaChromeButton(systemName: "sidebar.left",
                              tooltip: SigmaTooltip(text: "Mostrar/ocultar sidebar", keys: ["⌘", "S"], placement: .below)) {
                browserManager.toggleSidebar(for: windowState)
            }
            .offset(x: 75, y: 6)

            if windowState.isSidebarVisible {
                HStack(spacing: 0) {
                    SigmaCleanUpButton()
                    SigmaChromeButton(systemName: "magnifyingglass",
                                      tooltip: SigmaTooltip(text: "Buscar", keys: ["⌘", "L"], placement: .below)) {
                        SigmaActions(tabs: tabs, window: windowState).openCommandBar()
                    }
                }
                .frame(width: SigmaMetrics.sidebarWidth - 3, height: SigmaMetrics.chromeButton.height, alignment: .trailing)
                .offset(y: 6)
            }

            HStack(spacing: 8) {
                if let session = tabs.selectedSession(in: windowState) {
                    SigmaURLPill(session: session)
                } else {
                    Spacer()
                }
                SigmaChromeButton(systemName: windowState.isSidebarVisible ? "circle.circle" : "target",
                                  tooltip: SigmaTooltip(text: windowState.isSidebarVisible ? "Entrar no modo foco" : "Sair do modo foco",
                                                        placement: .below)) {
                    browserManager.toggleSidebar(for: windowState)
                }
                SigmaChromeButton(tooltip: SigmaTooltip(text: "Perguntar à Airis", keys: ["A"], placement: .below), label: {
                    SigmaAirisIcon(active: windowState.isSidebarAIChatVisible)
                }) {
                    browserManager.toggleAISidebar(for: windowState)
                }
                SigmaChromeButton(systemName: "sidebar.right",
                                  tooltip: SigmaTooltip(text: "Nova página lateral", keys: ["⇧", "␣"], placement: .below)) {
                    if browserManager.splitManager.isSplit(for: windowState.id) {
                        browserManager.splitManager.exitSplit(keep: .left, for: windowState.id)
                    } else {
                        SigmaActions(tabs: tabs, window: windowState).openCommandBar(split: true)
                    }
                }
            }
            .padding(.leading, windowState.isSidebarVisible ? contentX : 130)
            .padding(.trailing, 2)
            .offset(y: 6)
        }
        .frame(height: SigmaMetrics.chromeHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Semáforos (`AppVisibilityButtons`, estilo colorido): framboesa, tangerina e fig a 50% com
/// contorno de 1pt em multiply; cinza a 50% com a janela inativa. O símbolo aparece no hover de
/// cada botão. Os do sistema ficam ocultos.
struct SigmaTrafficLights: View {
    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            SigmaTrafficLight(color: SigmaPalette.raspberry, symbol: "multiply") { NSApp.keyWindow?.performClose(nil) }
            SigmaTrafficLight(color: SigmaPalette.mandarin, symbol: "minus") { NSApp.keyWindow?.performMiniaturize(nil) }
            SigmaTrafficLight(color: SigmaPalette.fig, symbol: "arrow.up.backward.and.arrow.down.forward") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: (SigmaMetrics.trafficLight + 10) / 2, style: .continuous))
        .offset(x: SigmaMetrics.trafficLightX[0], y: SigmaMetrics.trafficLightY)
        .frame(width: 70, height: SigmaMetrics.chromeHeight, alignment: .topLeading)
    }
}

private struct SigmaTrafficLight: View {
    @Environment(\.controlActiveState) private var activeState
    let color: Color
    let symbol: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        let size = SigmaMetrics.trafficLight
        let active = activeState == .key || activeState == .active
        let stroke = active ? color : Color.secondary.opacity(0.5)
        Button(action: action) {
            ZStack {
                Circle().fill(active ? color.opacity(0.5) : Color.gray.opacity(0.5))
                Circle().stroke(stroke, style: StrokeStyle(lineWidth: 1, miterLimit: 10))
                Image(systemName: symbol)
                    .resizable()
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(stroke)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .opacity(isHovered ? 1 : 0)
            }
            .blendMode(.multiply)
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.1)) { isHovered = hovering } }
    }
}

/// Tornado; no hover ou durante a confirmação vira a pílula "clean up 🌪".
struct SigmaCleanUpButton: View {
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isHovered = false

    var body: some View {
        let ui = SigmaUIState.of(windowState)
        let actions = SigmaActions(tabs: tabs, window: windowState)
        let expanded = (isHovered || ui.confirmingCleanUp) && !actions.cleanableItems.isEmpty
        Button {
            if !actions.cleanableItems.isEmpty { ui.confirmingCleanUp = true }
        } label: {
            HStack(alignment: .center, spacing: 6) {
                if expanded {
                    Text("clean up")
                        .font(.body)
                        .fontWeight(.medium)
                        .kerning(-0.2)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                Image(systemName: "tornado")
                    .font(.system(size: 16, weight: .regular))
                    .scaleEffect(expanded ? 1.05 : 1)
            }
            .foregroundStyle(expanded ? SigmaPalette.raspberry : Color.secondary)
            .padding(.leading, 2)
            .padding(6)
            .frame(minWidth: 32, minHeight: 32)
            .background(SigmaPalette.raspberry.opacity(expanded ? 0.1 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(SigmaMotion.standard) { isHovered = hovering } }
        .animation(SigmaMotion.standard, value: expanded)
    }
}

/// Confirmação do clean up, centralizada sobre a página: "sweep sweep".
struct SigmaCleanUpConfirm: View {
    let count: Int
    let space: SpaceRecord?
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("🧹")
                .font(.system(size: 34))
                .padding(.top, 26)
            Text("sweep sweep")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.88))
                .padding(.top, 14)
            message
                .font(.system(size: 15))
                .foregroundStyle(Color.primary.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.top, 22)
                .padding(.horizontal, 24)
            VStack(spacing: 8) {
                Button(action: onConfirm) {
                    HStack {
                        Spacer()
                        Image(systemName: "tornado")
                        Text("Clean up")
                        Spacer()
                    }
                    .overlay(alignment: .trailing) { Image(systemName: "return").opacity(0.7) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SigmaPalette.mandarin))
                }
                .buttonStyle(SigmaPressedStyle())
                .keyboardShortcut(.defaultAction)
                Button(action: onCancel) {
                    HStack {
                        Spacer()
                        Text("Cancelar")
                        Spacer()
                    }
                    .overlay(alignment: .trailing) { Text("esc").opacity(0.5) }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(SigmaPalette.mandarin.opacity(0.08)))
                }
                .buttonStyle(SigmaPressedStyle())
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 28)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 275)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(SigmaPalette.base))
        .shadow(color: .black.opacity(0.2), radius: 24, y: 10)
    }

    private var message: Text {
        let pages = Text(count == 1 ? "1 página" : "\(count) páginas").fontWeight(.semibold).foregroundColor(Color.primary.opacity(0.7))
        let name = Text("\(space?.name ?? "") \(space?.isEmojiIcon == true ? space!.icon : "")").fontWeight(.semibold).foregroundColor(Color.primary.opacity(0.7))
        let tail = count == 1 ? " será marcada como concluída.\n" : " serão marcadas como concluídas.\n"
        return pages + Text(" em ") + name + Text(tail) + Text("Não se preocupe, as páginas travadas serão poupadas.")
    }
}

/// Aviso curto no topo, centralizado na área da página, com "Desfazer" quando cabe.
struct SigmaNoticeView: View {
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    let notice: SigmaNotice

    var body: some View {
        HStack(spacing: 12) {
            Text(notice.text)
                .font(.system(size: 14))
                .foregroundStyle(Color.primary.opacity(0.8))
            if notice.canUndo {
                Button("Desfazer") { SigmaActions(tabs: tabs, window: windowState).undo() }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SigmaPalette.mandarin)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Capsule().fill(SigmaPalette.base))
        .overlay(Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}

/// Pílula de URL (30pt): voltar/avançar à esquerda; favicon + título no centro; recarregar e
/// copiar link à direita. Clique abre a barra de comando com o endereço atual.
struct SigmaURLPill: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    let session: PageSession
    @State private var copied = false
    @State private var isHoveringTitle = false

    var body: some View {
        let actions = SigmaActions(tabs: tabs, window: windowState)
        ZStack {
            HStack(spacing: 9) {
                session.favicon
                    .resizable()
                    .scaledToFit()
                    .frame(width: SigmaMetrics.faviconSize, height: SigmaMetrics.faviconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                Text(SigmaNewPage.isNewPage(session.url) ? "Nova página"
                     : session.title.isEmpty ? (session.url.host ?? session.url.absoluteString) : session.title)
                    .font(SigmaType.urlBar)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 80)
            .onHover { isHoveringTitle = $0 }

            HStack(spacing: 0) {
                SigmaPillButton(systemName: "doc.plaintext", tooltip: "Modo leitura") {
                    SigmaReader.open(session: session, webView: webView, window: windowState)
                }
                Spacer()
                if actions.isLocked(session.itemID) && actions.hasLeftLocked(session.itemID) {
                    SigmaPillButton(systemName: "arrow.uturn.backward", tooltip: "Voltar à página travada") {
                        actions.goBackToLocked(session.itemID)
                    }
                    SigmaPillButton(systemName: "lock.rotation", tooltip: "Atualizar página travada") {
                        actions.updateLocked(session.itemID)
                    }
                }
                SigmaPillButton(systemName: "character.bubble.fill", tooltip: "Traduzir página") {
                    if let url = SigmaReader.translationURL(for: session.url) { session.load(url) }
                }
                SigmaPillButton(systemName: copied ? "checkmark" : "link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.url.absoluteString, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                }
            }
            .padding(.horizontal, 5)
        }
        .frame(height: SigmaMetrics.urlBarHeight)
        .frame(maxWidth: .infinity)
        // `palette.bar` = zero.highlighted(.low); metade com o mouse no título. Recorte raio 5 e a
        // moldura do `PanelOverlay` com raio 8 (os dois valores estão assim no binário).
        .background(SigmaPalette.zero.sigmaHighlighted().opacity(isHoveringTitle ? 0.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: SigmaMetrics.urlBarRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .inset(by: 0.5)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color(.sRGB, white: 0.1, opacity: 1).opacity(0.03), radius: 3, x: 0, y: 1)
        .animation(SigmaMotion.standard, value: isHoveringTitle)
        .contentShape(Rectangle())
        .onTapGesture {
            actions.openCommandBar(prefill: SigmaNewPage.isNewPage(session.url) ? "" : session.url.absoluteString, replace: true)
        }
        .task(id: session.url.host) { await SigmaPageColor.shared.resolve(session.url) }
    }

    private var webView: WKWebView? {
        browserManager.webViewCoordinator?.getWebView(for: session.itemID, in: windowState.id)
    }

    private func goBack() { session.goBack(in: webView) }

    private func goForward() {
        if let webView { webView.goForward() } else { session.goForward() }
    }
}

/// Botão dentro da pílula (`IconButton`): 24 de largura, body bold, `secondary` a 50%.
struct SigmaPillButton: View {
    let systemName: String
    var isEnabled = true
    var tooltip: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.bold))
                .foregroundStyle(Color.secondary.opacity(0.5))
                .frame(width: SigmaMetrics.urlBarButton.width, height: SigmaMetrics.urlBarButton.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .sigmaTooltip(isHovered ? tooltip.map { SigmaTooltip(text: $0, placement: .below) } : nil)
    }
}

/// Ícone da Airis do SigmaOS (asset `airis` / `airis.filled` em fig quando aberto), lido do app
/// instalado; sem ele, `sparkle`.
struct SigmaAirisIcon: View {
    let active: Bool

    var body: some View {
        Group {
            if let image = SigmaOSAssets.image(active ? "airis.filled" : "airis") {
                Image(nsImage: image).resizable().scaledToFit().frame(width: 17, height: 17)
            } else {
                Image(systemName: "sparkle")
            }
        }
        .foregroundStyle(active ? SigmaPalette.fig : Color.secondary)
    }
}
