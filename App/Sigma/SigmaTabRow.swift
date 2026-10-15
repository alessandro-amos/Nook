// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaTabRow.swift
//  Sigma
//
//  Linha de aba do Sigma sobre um Row do Nook, no formato do `TabRow` do SigmaOS
//  (~/Development/sigmaos/decomp/specs/tabrow.md). Sub-abas vêm achatadas pelo TabsController
//  com `depth`; abas com filhas mostram o triângulo.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import NookTabsCore
import NookWeb
import NookUI

struct SigmaTabRow: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.colorScheme) private var colorScheme
    let row: Row

    @State private var isHovered = false
    /// 0,3s depois de entrar na linha: aparecem ⋮ e cadeado.
    @State private var isLongHovered = false
    /// 0,3s parado no título: aparece "clique duas vezes para renomear".
    @State private var longHoverTitle = false
    @State private var isHoveringDone = false
    @State private var isDropTarget = false
    @State private var hoverWork: DispatchWorkItem?
    @State private var titleWork: DispatchWorkItem?
    @State private var progress: Double = 1

    private var item: Item { row.item }
    private var id: UUID { row.item.id }
    private var actions: SigmaActions { SigmaActions(tabs: tabs, window: windowState) }
    private var ui: SigmaUIState { SigmaUIState.of(windowState) }

    private var isSelected: Bool { windowState.selectedItemID == id }
    private var isLocked: Bool { actions.isLocked(id) }
    private var isRenaming: Bool { ui.renamingItemID == id }
    /// Prévia do clean up: as páginas que serão concluídas aparecem riscadas.
    private var isCleanUpPreview: Bool { ui.confirmingCleanUp && actions.cleanableItems.contains(id) }
    private var isCollapsedParent: Bool { row.hasChildren && !tabs.isOpen(folder: id) }
    private var isNewPage: Bool { SigmaNewPage.isNewPage(tabs.currentURL(for: item)) }
    private var title: String { isNewPage ? "Nova página" : tabs.title(for: item) }

    var body: some View {
        let session = tabs.session(for: id)
        HStack(alignment: .center, spacing: 0) {
            if row.depth > 0 {
                SigmaSubPageConnector(highlighted: isSelected, isHovered: isHovered)
                    .frame(width: SigmaTabMetrics.iconColumn)
                    .padding(.leading, CGFloat(row.depth - 1) * SigmaMetrics.subPageIndent + SigmaTabMetrics.padding)
            }
            Button { tabs.select(id, in: windowState) } label: {
                rowLabel(session: session)
            }
            .buttonStyle(SigmaBouncyStyle())
            .simultaneousGesture(TapGesture(count: 2).onEnded { ui.renamingItemID = id })
            .contextMenu { menuItems }
        }
        .draggable(id.uuidString)
        // Soltar no terço de cima põe antes; no resto junta como sub-aba.
        .dropDestination(for: String.self) { items, location in
            guard let raw = items.first, let dragged = UUID(uuidString: raw) else { return false }
            if location.y < SigmaMetrics.tabRowHeight / 3 || !tabs.tree.canTakeChild(id) {
                actions.move(dragged, before: item)
            } else {
                actions.nest(dragged, under: id)
            }
            return true
        } isTargeted: { targeted in
            withAnimation(SigmaMotion.standard) { isDropTarget = targeted }
        }
        .task(id: tabs.currentURL(for: item)?.host) {
            await SigmaPageColor.shared.resolve(tabs.currentURL(for: item))
        }
        .task(id: session.map { ObjectIdentifier($0) }) { await trackProgress(session) }
        .onChange(of: session?.isLoading) { _, loading in if loading != true { progress = 1 } }
    }

    // MARK: Label

    private func rowLabel(session: PageSession?) -> some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(alignment: .center, spacing: SigmaTabMetrics.padding) {
                leadingIcon(session: session)
                    .frame(width: SigmaTabMetrics.iconColumn)
                if row.hasChildren && (isHovered || isCollapsedParent) {
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.secondary)
                        .rotationEffect(.radians(isCollapsedParent ? 0 : .pi / 2))
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(SigmaMotion.standard) { tabs.toggleFolder(id) } }
                        .transition(.offset(x: -10).combined(with: .opacity))
                }
                VStack(alignment: .leading, spacing: 0) {
                    if isRenaming {
                        SigmaTabRenameField(text: title) { newTitle in
                            if let newTitle { tabs.rename(id, newTitle.isEmpty ? nil : newTitle) }
                            ui.renamingItemID = nil
                        }
                    } else {
                        titleText(session: session)
                        if showRenameNudge {
                            Text("clique duas vezes para renomear")
                                .font(.caption)
                                .foregroundStyle(Color.primary.opacity(0.8))
                                .colorMultiply(SigmaPalette.mandarin)
                                .modifier(SigmaShimmer(
                                    active: true,
                                    animation: .linear(duration: 1.25).delay(0.25).repeatCount(4, autoreverses: true),
                                    stops: [.init(color: .black.opacity(0.6), location: 0), .init(color: .black, location: 0.35),
                                            .init(color: .black, location: 0.65), .init(color: .black.opacity(0.6), location: 1)]
                                ))
                                .transition(.opacity)
                        }
                    }
                }
                .padding(.vertical, -SigmaTabMetrics.padding)
                .animation(.spring(response: 0.2, dampingFraction: 1), value: showRenameNudge)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(SigmaMotion.standard, value: isHovered && row.hasChildren)

            rowActions(session: session)
        }
        .padding(.horizontal, SigmaTabMetrics.padding)
        .padding(.vertical, SigmaTabMetrics.padding)
        .frame(height: SigmaMetrics.tabRowHeight)
        .background(SigmaTabBackground(
            color: backgroundColor,
            fraction: isSelected && !isNewPage ? SigmaTabBackground.fraction(progress: loadProgress(session)) : 1
        ))
        .overlay(
            RoundedRectangle(cornerRadius: SigmaMetrics.cornerRadius, style: .continuous)
                .strokeBorder(SigmaPalette.mandarin.opacity(isDropTarget ? 0.6 : 0), lineWidth: 2)
        )
        .contentShape(RoundedRectangle(cornerRadius: SigmaMetrics.cornerRadius, style: .continuous))
        .onHover(perform: rowHover)
    }

    private func titleText(session: PageSession?) -> some View {
        Text(title)
            .font(isNewPage && !isLocked ? .body.italic() : .body)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(session == nil || session?.isUnloaded == true
                             ? Color.secondary : Color.primary.opacity(isSelected ? 1 : 0.7))
            .brightness(isHovered && !isSelected ? (colorScheme == .dark ? 0.2 : -0.2) : 0)
            .animation(.easeInOut(duration: 0.1), value: isHovered)
            .modifier(SigmaStrikethrough(visible: isHoveringDone || isCleanUpPreview))
            .help(title)
            .padding(.trailing, 2)
            .onHover(perform: titleHover)
    }

    /// Só na aba selecionada, depois de 0,3s parado no título, se não travada e nunca renomeada.
    private var showRenameNudge: Bool {
        longHoverTitle && isSelected && !isLocked && !isRenaming && item.customTitle == nil
    }

    /// Accent da paleta (mandarin): 25% na selecionada, metade disso no hover.
    private var backgroundColor: Color {
        let accent = SigmaPalette.mandarin.opacity(SigmaOpacity.pageSelected)
        if isSelected { return accent }
        if isHovered { return accent.opacity(0.5) }
        return .clear
    }

    /// `loadState`: carregando → progresso; carregada → 1; não carregada → 0.
    private func loadProgress(_ session: PageSession?) -> Double {
        guard let session, !session.isUnloaded else { return 0 }
        return session.isLoading ? progress : 1
    }

    private func trackProgress(_ session: PageSession?) async {
        guard let webView = session?.webView else { return }
        for await value in webView.publisher(for: \.estimatedProgress).values {
            withAnimation(SigmaMotion.standard) { progress = value }
        }
    }

    // MARK: Hover

    private func rowHover(_ hovering: Bool) {
        isHovered = hovering
        hoverWork?.cancel()
        if hovering {
            let work = DispatchWorkItem { withAnimation(SigmaMotion.standard) { isLongHovered = true } }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        } else {
            withAnimation(SigmaMotion.standard) {
                isLongHovered = false
                isHoveringDone = false
            }
        }
    }

    private func titleHover(_ hovering: Bool) {
        titleWork?.cancel()
        if hovering {
            let work = DispatchWorkItem { longHoverTitle = true }
            titleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        } else {
            longHoverTitle = false
        }
    }

    // MARK: Ícone

    @ViewBuilder
    private func leadingIcon(session: PageSession?) -> some View {
        if isRenaming {
            Image(systemName: "highlighter")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.primary.opacity(0.7))
                .frame(width: SigmaMetrics.faviconSize)
        } else {
            ItemFavicon(item: item, session: session)
                .frame(width: SigmaMetrics.faviconSize, height: SigmaMetrics.faviconSize)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
    }

    // MARK: Ações

    /// Ordem do SigmaOS: ⋮, cadeado, ✓, áudio. ⋮ e cadeado entram depois de 0,3s de hover; o
    /// cadeado de página travada fica sempre, a 20% fora da selecionada.
    @ViewBuilder
    private func rowActions(session: PageSession?) -> some View {
        HStack(spacing: 0) {
            if !isRenaming {
                if isLongHovered {
                    Menu { menuItems } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.radians(-.pi / 2))
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(SigmaTabActionStyle())
                    .fixedSize(horizontal: true, vertical: false)
                    .transition(SigmaMotion.actionTransition)
                }
                if isLongHovered || isLocked {
                    Button { actions.toggleLocked(id) } label: {
                        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    }
                    .buttonStyle(SigmaTabActionStyle())
                    .opacity(isSelected ? 1 : (isHovered ? 1 : 0.2))
                    .help(isLocked ? "Destravar página" : "Travar página")
                    .transition(SigmaMotion.actionTransition)
                }
                if isHovered {
                    Button { actions.markDone(id) } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(SigmaTabActionStyle(verticalPadding: 5))
                    .onHover { hovering in withAnimation(.easeInOut(duration: 0.2)) { isHoveringDone = hovering } }
                    .help("Marcar como concluída")
                    .transition(.scale.animation(SigmaMotion.standard))
                }
                if session?.hasPlayingAudio == true {
                    Button { session?.toggleMute() } label: {
                        Image(systemName: session?.isAudioMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .buttonStyle(SigmaTabActionStyle(verticalPadding: 5))
                }
            }
        }
        .animation(SigmaMotion.standard, value: isLongHovered)
        .animation(SigmaMotion.standard, value: isLocked)
    }

    /// Menu do ⋮ e do clique direito, na ordem do SigmaOS. Ficam de fora o que o motor do Nook não
    /// tem: adiar, tags, mini-janela, seleção múltipla, co-browsing e ajustes do site.
    @ViewBuilder
    private var menuItems: some View {
        let session = tabs.session(for: id)
        Button { actions.markDone(id) } label: { Label("Marcar como concluída", systemImage: "checkmark") }
            .disabled(isLocked)
        Button { tabs.unload(id) } label: { Label("Liberar memória", systemImage: "bolt.fill") }
            .disabled(session == nil || session?.isUnloaded == true || isSelected)
        Divider()
        Button { actions.toggleLocked(id) } label: {
            Label(isLocked ? "Destravar" : "Travar", systemImage: isLocked ? "lock.open.fill" : "lock.fill")
        }
        Menu {
            Button { actions.goBackToLocked(id) } label: { Label("Voltar à URL travada", systemImage: "arrow.left") }
            Button { actions.updateLocked(id) } label: { Label("Trocar a URL travada pela atual", systemImage: "lock.doc") }
        } label: {
            Label("Navegação travada", systemImage: "lock.rotation")
        }
        .disabled(!(isLocked && actions.hasLeftLocked(id)))
        Divider()
        Button { ui.renamingItemID = id } label: { Label("Renomear", systemImage: "character.cursor.ibeam") }
        Button { if let parent = indentTarget { actions.nest(id, under: parent) } } label: {
            Label("Recuar", systemImage: "chevron.right")
        }
        .disabled(indentTarget == nil)
        if row.depth > 0 {
            Button { removeIndent() } label: { Label("Remover recuo", systemImage: "chevron.left") }
        }
        Button { _ = tabs.duplicate(id, in: windowState) } label: { Label("Duplicar", systemImage: "doc.on.doc") }
        Button { session?.toggleMute() } label: {
            Label(session?.isAudioMuted == true ? "Reativar som" : "Silenciar página", systemImage: "speaker.wave.2.fill")
        }
        .disabled(session == nil)
        Divider()
        Button {
            browserManager.splitManager.enterSplit(with: id, placeOn: .right, in: windowState)
        } label: {
            Label("Levar para o split", systemImage: "rectangle.lefthalf.inset.fill")
        }
        .disabled(isSelected)
        Menu {
            ForEach(tabs.switchableSpaces(for: windowState).filter { $0.id != windowState.spaceID }) { space in
                Button("\(space.isEmojiIcon ? space.icon + " " : "")\(space.name)") {
                    withAnimation(SigmaMotion.list) { tabs.move(id, to: .tabs(spaceID: space.id), after: nil) }
                }
            }
        } label: {
            Label("Mover para…", systemImage: "arrow.left.arrow.right")
        }
        .disabled(tabs.switchableSpaces(for: windowState).count < 2 || windowState.isIncognito)
        Divider()
        Menu {
            Button("Copiar link") { actions.copyLink(item) }
        } label: {
            Label("Compartilhar", systemImage: "paperplane.fill")
        }
    }

    /// "Recuar" vira sub-página da página logo acima no mesmo nível.
    private var indentTarget: UUID? {
        let siblings = tabs.children(of: item.parent)
        guard let index = siblings.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        let above = siblings[index - 1]
        guard !above.isFolder, tabs.tree.canTakeChild(above.id) else { return nil }
        return above.id
    }

    /// "Remover recuo" sobe um nível, logo depois da página-mãe.
    private func removeIndent() {
        guard case .folder(let parentID) = item.parent, let parent = tabs.item(parentID) else { return }
        withAnimation(SigmaMotion.list) { tabs.move(id, to: parent.parent, after: parentID) }
    }
}

enum SigmaTabMetrics {
    /// `tabPadding` do TabRow.
    static let padding: CGFloat = 5
    /// `leftIconWidth` do TabRow.
    static let iconColumn: CGFloat = 25
}

/// Fundo da aba (`Background`): pílula centralizada que cresce para os dois lados com o progresso
/// do carregamento, largura W·(p² + 0,3)/1,3.
struct SigmaTabBackground: View {
    let color: Color
    let fraction: Double

    static func fraction(progress p: Double) -> Double { (p * p + 0.3) / 1.3 }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Color.clear
                RoundedRectangle(cornerRadius: SigmaMetrics.cornerRadius, style: .continuous)
                    .fill(color)
                    .frame(width: proxy.size.width * fraction)
                Color.clear
            }
        }
        .animation(SigmaMotion.standard, value: fraction)
    }
}

/// `AnimatedStrikethrough`: texto a 50% com uma barra de 2pt secundária que cresce da esquerda.
struct SigmaStrikethrough: ViewModifier {
    let visible: Bool

    func body(content: Content) -> some View {
        content
            .layoutPriority(1)
            .opacity(visible ? 0.5 : 1)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary)
                    .frame(height: 2)
                    .scaleEffect(x: visible ? 1 : 0, anchor: .leading)
            }
            .animation(.easeInOut(duration: 0.2), value: visible)
    }
}

/// `Shimmer` do SigmaOS: máscara em gradiente que atravessa o texto na diagonal (banda de −0,3 a 1,3).
struct SigmaShimmer: ViewModifier {
    let active: Bool
    let animation: Animation
    let stops: [Gradient.Stop]
    @State private var isInitialState = true

    func body(content: Content) -> some View {
        content
            .mask {
                if active {
                    LinearGradient(
                        stops: stops,
                        startPoint: isInitialState ? UnitPoint(x: -0.3, y: -0.3) : UnitPoint(x: 1, y: 1),
                        endPoint: isInitialState ? UnitPoint(x: 0, y: 0) : UnitPoint(x: 1.3, y: 1.3)
                    )
                } else {
                    Rectangle()
                }
            }
            .animation(animation, value: isInitialState)
            .onAppear { if active { isInitialState = false } }
    }
}

/// `ButtonStyles.Bouncy`: encolhe para 0,98 ao pressionar e volta com mola elástica.
struct SigmaBouncyStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 0.9999, anchor: .center)
            .animation(configuration.isPressed ? SigmaMotion.standard : SigmaMotion.release, value: configuration.isPressed)
    }
}

/// Botões de ação da aba (`TabStyles.Action`): system 13 bold, primary 60% (66% disso em repouso),
/// até 25 de largura, fundo primary 8% no hover com raio 6.
struct SigmaTabActionStyle: ButtonStyle {
    var verticalPadding: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        SigmaTabActionBody(configuration: configuration, verticalPadding: verticalPadding)
    }
}

private struct SigmaTabActionBody: View {
    let configuration: ButtonStyleConfiguration
    let verticalPadding: CGFloat
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.primary.opacity(0.6))
            .opacity(isHovered ? 1 : 0.66)
            .padding(.vertical, verticalPadding)
            .frame(width: 25)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
            )
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.1), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

/// Campo de renomear a aba: system 13; à direita o botão Salvar/Cancelar no lugar das ações.
struct SigmaTabRenameField: View {
    @State private var value: String
    @FocusState private var focused: Bool
    let commit: (String?) -> Void

    init(text: String, commit: @escaping (String?) -> Void) {
        _value = State(initialValue: text)
        self.commit = commit
    }

    private var trimmed: String { value.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        HStack(spacing: 5) {
            TextField("Título da página", text: $value)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onSubmit { commit(trimmed) }
                .onExitCommand { commit(nil) }
                .onChange(of: focused) { _, isFocused in if !isFocused { commit(trimmed) } }
            SigmaSaveButton(isEmpty: trimmed.isEmpty) { commit(trimmed.isEmpty ? nil : trimmed) }
        }
        .onAppear { focused = true }
    }
}

/// `SaveFromTextFieldIcon`: "Salvar" em mandarin 30% (50% no hover) ou "Cancelar" secundário com o
/// campo vazio; raio 5, padding 10×5, 13 medium.
struct SigmaSaveButton: View {
    let isEmpty: Bool
    let action: () -> Void

    var body: some View {
        let base = isEmpty ? Color.secondary.opacity(0.5) : SigmaPalette.mandarin
        Button(isEmpty ? "Cancelar" : "Salvar", action: action)
            .buttonStyle(SigmaStandardStyle(
                color: base.opacity(0.3),
                hoveredColor: base.opacity(0.5),
                cornerRadius: 5,
                scaleAmount: 0.97,
                horizontalPadding: 10,
                verticalPadding: 5
            ))
    }
}

/// Conector das sub-páginas (`SubTabIndicator`): pontos de 2pt com 2 de espaço, ":." ; na cor de
/// destaque quando a sub-aba está selecionada, senão primary 20% (100% no hover).
struct SigmaSubPageConnector: View {
    let highlighted: Bool
    let isHovered: Bool

    var body: some View {
        let color = highlighted ? SigmaPalette.mandarin : Color.primary.opacity(isHovered ? 1 : 0.2)
        VStack(alignment: .leading, spacing: 2) {
            dot(color)
            HStack(spacing: 2) {
                dot(color)
                dot(color)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dot(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 2)
    }
}

/// Botão do topo (`TopBarButtonStyle`): símbolo system 16 em `secondary`, caixa visível de até
/// 35×28 recortada com raio 5; no hover o botão inteiro cresce para 1,2× com a mola padrão. Sem
/// fundo e sem efeito de pressionado; desabilitado fica a 50%. Os 5pt em volta são a área do tooltip.
struct SigmaChromeButton<Label: View>: View {
    var tooltip: SigmaTooltip?
    var isEnabled = true
    let label: () -> Label
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 16, weight: .regular))
                .padding(5)
                .frame(maxWidth: 35, minHeight: 28, maxHeight: 28)
                .contentShape(Rectangle())
                .foregroundStyle(Color.secondary)
                .scaleEffect(isHovered && isEnabled ? 1.2 : 1)
                .animation(SigmaMotion.standard, value: isHovered)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .padding(5)
        .sigmaTooltip(isHovered && isEnabled ? tooltip : nil)
    }
}

extension SigmaChromeButton where Label == Image {
    init(systemName: String, tooltip: SigmaTooltip? = nil, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.init(tooltip: tooltip, isEnabled: isEnabled, label: { Image(systemName: systemName) }, action: action)
    }
}

/// Imagens do SigmaOS instalado (como a fonte e os emojis): lidas do Assets.car em tempo de
/// execução, nunca copiadas.
enum SigmaOSAssets {
    private static let bundle = Bundle(path: "/Applications/SigmaOS.app")

    static func image(_ name: String) -> NSImage? {
        guard let image = bundle?.image(forResource: name) else { return nil }
        image.isTemplate = true
        return image
    }
}
