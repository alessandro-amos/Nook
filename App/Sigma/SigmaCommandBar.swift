// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaCommandBar.swift
//  Sigma
//
//  Barra de comando do Sigma. Embutida na aba "Nova página" (⌘T cria uma aba de verdade) ou
//  sobreposta à janela (lupa, ⌘L, clique na pílula). Enter abre; ⌥ substitui a página atual;
//  ⇧ abre em split. Resultados: abas abertas, histórico e busca.
//

import AppKit
import SwiftUI
import NookTabsCore
import NookWeb
import NookUI

/// Aba "Nova página": uma aba em about:blank que mostra a barra de comando no lugar da página.
enum SigmaNewPage {
    static let url = URL(string: "about:blank")!

    static func isNewPage(_ url: URL?) -> Bool { url?.scheme == "about" }
}

/// Pedido para abrir a barra sobreposta.
struct SigmaCommandRequest: Equatable {
    var prefill = ""
    /// Enter troca a página atual em vez de abrir uma nova.
    var replace = false
    /// Enter abre em split (página lateral).
    var split = false
}

struct SigmaCommandResult: Identifiable {
    enum Kind {
        case openTab(itemID: UUID, spaceID: UUID)
        case url(URL)
        case search(String)
        case space(UUID)
    }

    let id: String
    var kind: Kind
    var title: String
    var detail: String?
    var url: URL?
    var symbol: String?
    var spaceIcon: SpaceRecord?
}

struct SigmaCommandSection: Identifiable {
    var id: String { title }
    var title: String
    var results: [SigmaCommandResult]
}

struct SigmaCommandBar: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState

    /// Aba "Nova página" que hospeda a barra; nil na barra sobreposta.
    var hostItemID: UUID?
    var request = SigmaCommandRequest()
    var onDismiss: () -> Void = {}

    @State private var query = ""
    @State private var history: [HistoryEntry] = []
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var actions: SigmaActions { SigmaActions(tabs: tabs, window: windowState) }

    @State private var modifiers: NSEvent.ModifierFlags = []
    @State private var flagsMonitor: Any?
    @State private var listHeight: CGFloat = 0

    var body: some View {
        let sections = sections
        let flat = sections.flatMap(\.results)
        VStack(alignment: .leading, spacing: 0) {
            header
            if !flat.isEmpty {
                Divider()
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.results) { result in
                                    let index = flat.firstIndex { $0.id == result.id } ?? 0
                                    SigmaCommandRow(result: result, isSelected: index == selection)
                                        .onTapGesture { run(result) }
                                        .onHover { if $0 { selection = index } }
                                }
                            } header: {
                                Text(section.title)
                                    .font(SigmaType.commandSection)
                                    .fontWeight(.regular)
                                    .foregroundStyle(Color.secondary.opacity(0.8))
                                    .padding(.horizontal, 20)
                                    .padding(.top, 12)
                                    .padding(.bottom, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(SigmaGlass(saturation: 1.0))
                            }
                        }
                        Color.clear.frame(height: 8)
                    }
                    .padding(.bottom, 8)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: SigmaListHeightKey.self, value: proxy.size.height)
                    })
                }
                .onPreferenceChange(SigmaListHeightKey.self) { listHeight = $0 }
                .frame(height: min(listHeight, 430))
            }
        }
        .background(SigmaGlass(saturation: 1.3))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color(.sRGB, white: 0.1, opacity: 1).opacity(0.03), radius: 3, x: 0, y: 1)
        .onAppear {
            query = request.prefill
            focused = true
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                modifiers = event.modifierFlags.intersection([.shift, .option])
                return event
            }
        }
        .onDisappear { if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) } }
        .task(id: query) { await loadHistory() }
        .onChange(of: query) { _, _ in selection = 0 }
        .onExitCommand { onDismiss() }
    }

    /// Linha do campo (`ModalTextFieldBackground`): 60 de altura, lupa 20 medium numa caixa de 25,
    /// texto system 18 e os chips de modificador à direita.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 25, alignment: .leading)
                .padding(.leading, 4)
            TextField("Pesquise ou digite um endereço…", text: $query)
                .textFieldStyle(.plain)
                .font(SigmaType.commandInput)
                .focused($focused)
                .onSubmit { submit() }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
                .padding(.leading, -5)
            HStack(spacing: 8) {
                if hostItemID == nil || windowState.selectedItemID != hostItemID {
                    SigmaModifierChip(symbol: "⌥", text: "Substituir", color: Color(hex: "#F695BF"),
                                      isPressed: modifiers.contains(.option)) { submit(replace: true) }
                }
                SigmaModifierChip(symbol: "⇧", text: "Split Screen", color: SigmaPalette.fig,
                                  isPressed: modifiers.contains(.shift)) { submit(split: true) }
            }
            .padding(.trailing, 20)
        }
        .padding(.leading, 20.5)
        .padding(.vertical, 3)
        .frame(height: 60)
    }

    // MARK: Resultados

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var sections: [SigmaCommandSection] {
        let open = openTabResults
        if trimmed.isEmpty {
            var result: [SigmaCommandSection] = []
            let top = Array(topSites.prefix(3)) + Array(open.filter { $0.detail == "já aberta aqui" }.prefix(3))
            if !top.isEmpty { result.append(.init(title: "Top Hits", results: top)) }
            let workspaces = recentWorkspaces
            if !workspaces.isEmpty { result.append(.init(title: "Workspaces", results: workspaces)) }
            let recent = Array(recentPages.prefix(5))
            if !recent.isEmpty { result.append(.init(title: "Páginas recentes", results: recent)) }
            return result
        }
        let needle = trimmed.lowercased()
        let matches: (SigmaCommandResult) -> Bool = {
            $0.title.lowercased().contains(needle) || ($0.url?.absoluteString.lowercased().contains(needle) ?? false)
        }
        var top: [SigmaCommandResult] = [primaryResult]
        top += open.filter(matches).prefix(4)
        let seen = Set(top.compactMap { $0.url?.absoluteString })
        top += historyResults.filter { !seen.contains($0.url?.absoluteString ?? "") }.prefix(5)
        return [.init(title: "Top Hits", results: top)]
    }

    /// O que o Enter faz com o texto digitado: abrir o endereço ou buscar.
    private var primaryResult: SigmaCommandResult {
        let normalized = normalizeURL(trimmed, queryTemplate: browserManager.nookSettings?.resolvedSearchEngineTemplate ?? "https://www.google.com/search?q=%@")
        let looksLikeURL = !trimmed.contains(" ") && (trimmed.contains(".") || trimmed.hasPrefix("http") || trimmed.hasPrefix("localhost"))
        if looksLikeURL, let url = URL(string: normalized) {
            return SigmaCommandResult(id: "primary", kind: .url(url), title: trimmed, detail: "abrir endereço", url: url, symbol: "globe")
        }
        return SigmaCommandResult(id: "primary", kind: .search(trimmed), title: trimmed, detail: "pesquisar", symbol: "magnifyingglass")
    }

    private var openTabResults: [SigmaCommandResult] {
        tabs.switchableSpaces(for: windowState).flatMap { space in
            tabs.rows(space: space.id)
                .filter { !$0.item.isFolder && $0.item.id != hostItemID }
                .compactMap { row -> SigmaCommandResult? in
                    let url = tabs.currentURL(for: row.item)
                    guard !SigmaNewPage.isNewPage(url) else { return nil }
                    let here = space.id == windowState.spaceID
                    return SigmaCommandResult(
                        id: "tab-\(row.item.id)",
                        kind: .openTab(itemID: row.item.id, spaceID: space.id),
                        title: tabs.title(for: row.item),
                        detail: here ? "já aberta aqui" : "em \(space.name)",
                        url: url,
                        spaceIcon: here ? nil : space
                    )
                }
        }
    }

    private var historyResults: [SigmaCommandResult] {
        history.map { entry in
            SigmaCommandResult(id: "history-\(entry.id)", kind: .url(entry.url), title: entry.displayTitle,
                               detail: entry.url.host, url: entry.url)
        }
    }

    private var topSites: [SigmaCommandResult] {
        let open = Set(openTabResults.compactMap { $0.url?.host })
        var seen = Set<String>()
        return history
            .sorted { $0.visitCount > $1.visitCount }
            .filter { entry in
                guard let host = entry.url.host, !open.contains(host) else { return false }
                return seen.insert(host).inserted
            }
            .map { SigmaCommandResult(id: "top-\($0.id)", kind: .url($0.url), title: $0.displayTitle, url: $0.url) }
    }

    private var recentPages: [SigmaCommandResult] {
        history
            .sorted { $0.lastVisited > $1.lastVisited }
            .map { entry in
                SigmaCommandResult(id: "recent-\(entry.id)", kind: .url(entry.url), title: entry.displayTitle,
                                   detail: entry.lastVisited.formatted(.relative(presentation: .named)), url: entry.url)
            }
    }

    private var recentWorkspaces: [SigmaCommandResult] {
        tabs.switchableSpaces(for: windowState)
            .filter { $0.id != windowState.spaceID }
            .prefix(3)
            .map { SigmaCommandResult(id: "space-\($0.id)", kind: .space($0.id), title: $0.name, spaceIcon: $0) }
    }

    private func loadHistory() async {
        guard let manager = tabs.history else { return }
        if trimmed.isEmpty {
            history = await manager.getHistory(days: 7, limit: 60).entries
        } else {
            try? await Task.sleep(for: .milliseconds(80))
            if Task.isCancelled { return }
            history = Array(await manager.searchHistory(query: trimmed).prefix(12))
        }
    }

    // MARK: Ações

    private func move(_ delta: Int) {
        let count = sections.flatMap(\.results).count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func submit(split: Bool = false, replace: Bool = false) {
        let flat = sections.flatMap(\.results)
        guard !flat.isEmpty else { return }
        let result = flat[min(selection, flat.count - 1)]
        let flags = NSEvent.modifierFlags
        run(result, split: split || request.split || flags.contains(.shift), replace: replace || flags.contains(.option))
    }

    private func run(_ result: SigmaCommandResult, split: Bool = false, replace: Bool = false) {
        switch result.kind {
        case .openTab(let itemID, let spaceID):
            if spaceID != windowState.spaceID { tabs.setSpace(spaceID, in: windowState) }
            if split {
                browserManager.splitManager.enterSplit(with: itemID, placeOn: .right, in: windowState)
            } else {
                tabs.select(itemID, in: windowState)
                closeHostIfUnused()
            }
        case .space(let spaceID):
            tabs.setSpace(spaceID, in: windowState)
        case .url(let url):
            open(url, split: split, replace: replace)
        case .search(let text):
            let template = browserManager.nookSettings?.resolvedSearchEngineTemplate ?? "https://www.google.com/search?q=%@"
            if let url = URL(string: normalizeURL(text, queryTemplate: template)) {
                open(url, split: split, replace: replace)
            }
        }
        onDismiss()
    }

    private func open(_ url: URL, split: Bool, replace: Bool) {
        if split {
            if let id = tabs.open(url: url, in: windowState, placement: .background) {
                browserManager.splitManager.enterSplit(with: id, placeOn: .right, in: windowState)
            }
        } else if let host = hostItemID, let session = tabs.ensureSession(for: host) {
            // Na aba "Nova página", a própria aba vira o site.
            session.load(url)
        } else if replace || request.replace {
            tabs.open(url: url, in: windowState, placement: .replaceCurrent)
        } else {
            tabs.open(url: url, in: windowState, placement: .newTab)
        }
    }

    /// Ir para uma aba já aberta a partir da "Nova página" descarta a aba vazia.
    private func closeHostIfUnused() {
        guard let host = hostItemID, let item = tabs.item(host), SigmaNewPage.isNewPage(tabs.currentURL(for: item)) else { return }
        tabs.remove(host)
    }
}

/// Linha (`SkinnyModalOption2`): 45 de altura, ícone 20, título 13 primário e subtítulo 13
/// secundário; a destacada ganha o fundo tingido e "Ir ›" na cor do destaque.
struct SigmaCommandRow: View {
    let result: SigmaCommandResult
    let isSelected: Bool

    /// Páginas aceitam ⇧ (split), então destacam em fig; workspaces não têm cor própria.
    private var highlightColor: Color {
        if case .space = result.kind { return Color.secondary.opacity(0.5) }
        return SigmaPalette.fig
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            icon
            HStack(spacing: 3) {
                Text(result.title)
                    .font(SigmaType.commandRow)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                if let detail = result.detail {
                    Text(detail)
                        .font(SigmaType.commandRow)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                if let space = result.spaceIcon, case .openTab = result.kind {
                    SigmaSpaceIcon(space: space, font: .system(size: 12), size: 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isSelected {
                HStack(spacing: 4) {
                    Text("Ir").fontWeight(.medium)
                    Image(systemName: "chevron.right").font(.body.weight(.semibold))
                }
                .font(.body)
                .foregroundStyle(highlightColor)
                .padding(.leading, 15)
            }
        }
        .padding(.vertical, 3)
        .frame(height: 45)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .background(alignment: .trailing) {
            SigmaHoveredSurface(tint: highlightColor, cornerRadius: 8)
                .opacity(isSelected ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if case .space = result.kind, let space = result.spaceIcon {
            SigmaSpaceIcon(space: space, font: .system(size: 16), size: 20)
        } else if let symbol = result.symbol {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.primary)
                .frame(width: 20, height: 20)
        } else {
            SigmaFavicon(url: result.url)
                .frame(width: 20, height: 20)
        }
    }
}

/// Chip de modificador (`TagView2`): "⇧ Split Screen" em body 13 medium com kerning 0.3. Parado o
/// texto fica secundário a 30% e o fundo some; no hover, texto na cor do chip e fundo a 25%; com a
/// tecla segurada, fundo a 80% e texto na cor de fundo.
struct SigmaModifierChip: View {
    let symbol: String
    let text: String
    let color: Color
    let isPressed: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text("\(symbol) \(text)")
                .font(.system(.body, design: .default).weight(.medium))
                .kerning(0.3)
                .foregroundStyle(isPressed ? SigmaPalette.zero : (isHovered ? color : Color.secondary.opacity(0.3)))
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(isPressed ? 0.8 : (isHovered ? 0.25 : 0)))
                )
                .padding(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.4, dampingFraction: 1), value: isPressed)
    }
}

/// `Surface(.hovered(tint:))`: o tint a 30% em modo cor, um cinza #5E5E5E a 17% em color dodge
/// (só no claro) e o tint a 15% por cima.
struct SigmaHoveredSurface: View {
    let tint: Color
    var cornerRadius: CGFloat = 8
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape.fill(tint.opacity(0.3)).blendMode(.color)
            if colorScheme == .light {
                shape.fill(Color(hex: "#5E5E5E").opacity(0.17)).blendMode(.colorDodge)
            }
            shape.fill(tint.opacity(0.15))
        }
        .compositingGroup()
    }
}

/// Vidro do SigmaOS (`Surface(.glass)`): desfoque dentro da janela.
struct SigmaGlass: NSViewRepresentable {
    var saturation: CGFloat = 1.3

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .popover
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct SigmaListHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Favicon pelo host, do cache do Nook; globo enquanto não houver.
struct SigmaFavicon: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primary.opacity(0.4))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .task(id: url?.host) {
            guard let host = url?.host else { return }
            image = await FaviconCache.shared.cachedImage(for: host)
        }
    }
}

/// O que a aba "Nova página" mostra no lugar do site: a barra de comando no fundo do conteúdo.
struct SigmaNewPageView: View {
    let itemID: UUID

    var body: some View {
        ZStack {
            SigmaPalette.content
            SigmaCommandBar(hostItemID: itemID)
                .id(itemID)
                .padding(.top, 40)
        }
    }
}
