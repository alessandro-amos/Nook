// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaSidebar.swift
//  Sigma
//
//  Sidebar do Sigma abaixo da faixa do topo: trilho de workspaces (spaces do Nook) e a coluna
//  com título do workspace, lista de abas e rodapé.
//

import AppKit
import SwiftUI
import NookSettings
import NookTabsCore
import NookWeb
import NookUI

struct SigmaSidebar: View {
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        let actions = SigmaActions(tabs: tabs, window: windowState)
        HStack(alignment: .top, spacing: 0) {
            SigmaWorkspaceRail()
                .frame(width: SigmaMetrics.railWidth)
                .padding(.leading, SigmaMetrics.railX)

            VStack(alignment: .leading, spacing: SigmaMetrics.tabListSpacing) {
                if let space = actions.currentSpace {
                    SigmaWorkspaceTitle(space: space)
                        .padding(.bottom, 5)
                    SigmaTabList(spaceID: space.id)
                        .id(space.id)
                        .transition(.opacity)
                } else {
                    Spacer()
                }
                SigmaSidebarFooter()
            }
            .padding(.leading, SigmaMetrics.listX - SigmaMetrics.railX - SigmaMetrics.railWidth)
            .padding(.trailing, SigmaMetrics.listTrailing)
        }
        .padding(.top, 1)
        .frame(width: SigmaMetrics.sidebarWidth)
    }
}

// MARK: - Trilho de workspaces

/// Coluna de workspaces (`WorkspaceList` do SigmaOS): botões 38×38 com 3pt de respiro em volta
/// (passo de 44), sem espaçamento próprio no VStack.
struct SigmaWorkspaceRail: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        let actions = SigmaActions(tabs: tabs, window: windowState)
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(tabs.switchableSpaces(for: windowState)) { space in
                    SigmaWorkspaceButton(space: space, isActive: space.id == windowState.spaceID) {
                        actions.switchTo(space)
                    }
                    .padding(3)
                    .contextMenu { if !windowState.isIncognito { SigmaWorkspaceMenu(space: space) } }
                }
                if !windowState.isIncognito {
                    SigmaRailPlusButton { actions.addSpace() }
                        .padding(3)
                }
            }
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity)
        }
        .padding(.top, -3)
        .padding(.bottom, 7)
    }
}

/// Menu do botão direito no trilho e no título (`FUN_10065c34c`): título, renomear, ícone,
/// configurações, clean up e excluir.
struct SigmaWorkspaceMenu: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    let space: SpaceRecord

    var body: some View {
        let actions = SigmaActions(tabs: tabs, window: windowState)
        Text("Configurações de \(space.isEmojiIcon ? space.icon + " " : "")\(space.name)")
        Divider()
        Button("Renomear") {
            actions.switchTo(space)
            actions.ui.workspaceEditing = .title
        }
        Button("Mudar ícone") {
            actions.switchTo(space)
            actions.ui.workspaceEditing = .icon
        }
        Button("Mais configurações…") {
            actions.switchTo(space)
            actions.ui.workspaceEditing = .settings
        }
        Divider()
        Button("Clean up") {
            actions.switchTo(space)
            if !actions.cleanableItems.isEmpty { actions.ui.confirmingCleanUp = true }
        }
        Button("Excluir") {
            browserManager.confirmSpaceDeletion(
                spaceName: space.name,
                tabCount: tabs.tabCount(inSpace: space.id),
                isLastSpace: tabs.orderedSpaces.count <= 1
            ) { tabs.deleteSpace(space.id) }
        }
        .disabled(tabs.orderedSpaces.count <= 1)
    }
}

/// Botão do workspace (`WorkspaceRow`): ativo = raspberry a 25%; hover = `zero.highlighted(.low)`.
/// Soltar uma imagem no botão vira o ícone do workspace.
struct SigmaWorkspaceButton: View {
    @Environment(TabsController.self) private var tabs
    let space: SpaceRecord
    let isActive: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var isDropTarget = false

    var body: some View {
        Button(action: action) {
            SigmaSpaceIcon(space: space, font: .system(size: 18, weight: .medium), size: 24)
                .frame(width: SigmaMetrics.workspaceButton, height: SigmaMetrics.workspaceButton)
                .background(
                    RoundedRectangle(cornerRadius: SigmaMetrics.cornerRadius, style: .continuous)
                        .fill(isActive || isDropTarget
                              ? SigmaPalette.raspberry.opacity(SigmaOpacity.workspaceActive)
                              : SigmaPalette.zero.sigmaHighlighted())
                        .opacity(isActive || isDropTarget || isHovered ? 1 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .sigmaTooltip(isHovered ? SigmaTooltip(text: space.name) : nil)
        .onDrop(of: [.image], isTargeted: $isDropTarget) { providers in
            guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) else { return false }
            _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                guard let image = object as? NSImage else { return }
                Task { @MainActor in
                    if let path = SigmaCustomIcons.store(image) {
                        tabs.updateSpace(space.id, name: nil, icon: path, accentHex: nil)
                    }
                }
            }
            return true
        }
    }
}

/// "+" do trilho (`CreateButton`): `.title` medium em `secondary`, 50% em repouso e 100% no hover,
/// com o fundo `zero.highlighted(.low)` aparecendo no hover.
struct SigmaRailPlusButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title.weight(.medium))
                .foregroundStyle(Color.secondary)
                .opacity(isHovered ? 1 : 0.5)
                .frame(width: SigmaMetrics.workspaceButton, height: SigmaMetrics.workspaceButton)
                .background(
                    RoundedRectangle(cornerRadius: SigmaMetrics.cornerRadius, style: .continuous)
                        .fill(SigmaPalette.zero.sigmaHighlighted())
                        .opacity(isHovered ? 1 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .sigmaTooltip(isHovered ? SigmaTooltip(text: "Novo workspace") : nil)
    }
}

// MARK: - Título do workspace

/// O que o título está editando (`editingAttribute` do `WorkspaceTitleView`).
enum SigmaWorkspaceEditing {
    case title, icon, settings
}

/// Título do workspace (`WorkspaceTitleView`): nome e emoji colados, engrenagem no fim que só
/// aparece com o mouse na área. Altura 35.
struct SigmaWorkspaceTitle: View {
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    let space: SpaceRecord
    @State private var hoveringArea = false
    @State private var hovered: SigmaWorkspaceEditing?

    var body: some View {
        @Bindable var ui = SigmaUIState.of(windowState)
        HStack(spacing: 0) {
            if ui.workspaceEditing == .title {
                SigmaWorkspaceRenameField(space: space) { ui.workspaceEditing = nil }
            } else {
                nameButton(ui)
                iconButton(ui)
                Spacer(minLength: 0)
                gearButton(ui)
            }
        }
        .frame(height: SigmaMetrics.workspaceTitleHeight)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { hoveringArea = $0 }
        .contextMenu { if !windowState.isIncognito { SigmaWorkspaceMenu(space: space) } }
        .animation(SigmaMotion.standard, value: ui.workspaceEditing)
    }

    private func nameButton(_ ui: SigmaUIState) -> some View {
        Button {
            if !windowState.isIncognito { ui.workspaceEditing = .title }
        } label: {
            Text(space.name.isEmpty ? "Workspace sem nome" : space.name)
                .font(SigmaType.workspaceTitle)
                .kerning(0.1)
                .foregroundStyle(Color.primary.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .buttonStyle(SigmaStandardStyle(
            color: Color.primary.opacity(0),
            hoveredColor: Color.primary.opacity(0.08),
            pressedColor: Color.primary.opacity(0.05),
            horizontalPadding: 6,
            verticalPadding: 5
        ))
        .padding(.leading, 4)
        .onHover { hovered = $0 ? .title : nil }
        .sigmaTooltip(hovered == .title && !windowState.isIncognito
                      ? SigmaTooltip(text: "Renomear workspace", placement: .below) : nil)
    }

    private func iconButton(_ ui: SigmaUIState) -> some View {
        Button {
            ui.workspaceEditing = ui.workspaceEditing == .icon ? nil : .icon
        } label: {
            SigmaSpaceIcon(space: space, font: .system(size: 20, weight: .regular), size: 25)
                .frame(width: SigmaMetrics.workspaceTitleHeight, height: SigmaMetrics.workspaceTitleHeight)
        }
        .buttonStyle(SigmaStandardStyle(
            color: Color.primary.opacity(ui.workspaceEditing == .icon ? 0.08 : 0),
            hoveredColor: Color.primary.opacity(0.08),
            pressedColor: Color.primary.opacity(0.05),
            scaleAmount: 0.97
        ))
        .disabled(windowState.isIncognito)
        .onHover { hovered = $0 ? .icon : nil }
        .sigmaTooltip(hovered == .icon && ui.workspaceEditing != .icon ? SigmaTooltip(text: "Mudar ícone", placement: .below) : nil)
        .popover(isPresented: Binding(
            get: { ui.workspaceEditing == .icon },
            set: { if !$0, ui.workspaceEditing == .icon { ui.workspaceEditing = nil } }
        ), arrowEdge: .trailing) {
            SigmaIconPicker(space: space)
                .environment(tabs)
        }
    }

    private func gearButton(_ ui: SigmaUIState) -> some View {
        Button {
            ui.workspaceEditing = ui.workspaceEditing == .settings ? nil : .settings
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.title3)
                .foregroundStyle(Color.primary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 2)
        .opacity(!windowState.isIncognito && (ui.workspaceEditing == .settings || hoveringArea) ? 1 : 0)
        .animation(SigmaMotion.standard, value: hoveringArea)
        .disabled(windowState.isIncognito)
        .onHover { hovered = $0 ? .settings : nil }
        .sigmaTooltip(hovered == .settings && ui.workspaceEditing != .settings
                      ? SigmaTooltip(text: "Configurações do workspace", placement: .below) : nil)
        .popover(isPresented: Binding(
            get: { ui.workspaceEditing == .settings },
            set: { if !$0, ui.workspaceEditing == .settings { ui.workspaceEditing = nil } }
        ), arrowEdge: .trailing) {
            SigmaWorkspaceSettings(space: space)
        }
    }
}

/// Modo renomear: campo 17 medium sobre fundo `zero.highlighted(.low)` arredondado que ocupa a
/// coluna, e à direita o botão "Salvar" (mandarin 30%) ou "Cancelar" (secundário) com o campo
/// vazio. Enter salva, Esc descarta.
struct SigmaWorkspaceRenameField: View {
    @Environment(TabsController.self) private var tabs
    let space: SpaceRecord
    let done: () -> Void
    @State private var value: String
    @FocusState private var focused: Bool

    init(space: SpaceRecord, done: @escaping () -> Void) {
        self.space = space
        self.done = done
        _value = State(initialValue: space.name)
    }

    private var trimmed: String { value.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            TextField("", text: $value)
                .textFieldStyle(.plain)
                .font(SigmaType.workspaceTitle)
                .kerning(0.1)
                .focused($focused)
                .onSubmit(save)
                .onExitCommand(perform: done)
                .onChange(of: focused) { _, isFocused in if !isFocused { save() } }

            let base = trimmed.isEmpty ? Color.secondary.opacity(0.5) : SigmaPalette.mandarin
            Button(trimmed.isEmpty ? "Cancelar" : "Salvar", action: save)
                .buttonStyle(SigmaStandardStyle(
                    color: base.opacity(0.3),
                    hoveredColor: base.opacity(0.5),
                    cornerRadius: 5,
                    scaleAmount: 0.97,
                    horizontalPadding: 10,
                    verticalPadding: 5
                ))
                .frame(maxHeight: .infinity)
                .padding(.vertical, 4)
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: SigmaMetrics.workspaceTitleHeight)
        .background(SigmaPalette.zero.sigmaHighlighted(), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { focused = true }
    }

    private func save() {
        if !trimmed.isEmpty && trimmed != space.name {
            tabs.updateSpace(space.id, name: trimmed, icon: nil, accentHex: nil)
        }
        done()
    }
}

/// Popover "Configurações de X" (`WorkspaceSettingsPopover`): 310 de largura, padding 15, fundo
/// `zero`. Cada space do Nook já tem cookies e logins próprios, então "Perfis separados" fica
/// ligado; Incógnito, Auto-close e Co-browsing do SigmaOS não existem no motor do Nook.
struct SigmaWorkspaceSettings: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(\.nookSettings) private var nookSettings
    let space: SpaceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text("Preferências")
                .font(.headline)
                .fontWeight(.medium)
                .padding(.top, 15)
                .padding(.bottom, 5)
            VStack(alignment: .leading, spacing: 6) {
                SigmaSettingsToggle(
                    text: "Perfis separados",
                    hint: "Entre em várias contas, se as páginas estiverem em workspaces diferentes.",
                    isOn: .constant(true)
                )
            }

            pinnedExtensions
        }
        .padding(15)
        .frame(width: 310)
        .background(SigmaPalette.zero.padding(-20))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 6) {
            SigmaSpaceIcon(space: space, font: .headline.weight(.regular), size: 20, imageRadius: 4)
            Text("Configurações de \(space.name.isEmpty ? "este workspace" : space.name)")
                .font(.headline)
                .fontWeight(.regular)
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // No SigmaOS o Reset também não faz nada (closure vazia).
            Button {} label: {
                Text("Redefinir").font(.callout).foregroundStyle(Color.secondary)
            }
            .buttonStyle(SigmaStandardStyle(
                color: Color.secondary.opacity(0.3),
                hoveredColor: Color.secondary.opacity(0.2),
                cornerRadius: 5,
                scaleAmount: 0.97,
                horizontalPadding: 10,
                verticalPadding: 2
            ))
        }
    }

    @ViewBuilder
    private var pinnedExtensions: some View {
        let installed = browserManager.extensionManager?.installedExtensions ?? []
        VStack(alignment: .leading) {
            Text("Extensões fixadas")
                .font(.headline)
                .fontWeight(.medium)
            Text(installed.isEmpty ? "Você não tem extensões instaladas." : "Escolha uma extensão para fixar:")
                .foregroundStyle(Color.secondary)
        }
        .padding(.top, 15)
        .padding(.bottom, 5)

        if !installed.isEmpty {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 8), spacing: 10) {
                    ForEach(installed, id: \.id) { ext in
                        let pinned = nookSettings.pinnedExtensionIDs.contains(ext.id)
                        Button {
                            nookSettings.pinnedExtensionIDs.removeAll { $0 == ext.id }
                            if !pinned { nookSettings.pinnedExtensionIDs.append(ext.id) }
                        } label: {
                            extensionIcon(ext.iconPath)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(SigmaIconCellStyle(isSelected: pinned))
                        .help(ext.name)
                    }
                }
            }
            .frame(maxHeight: 100)

            Button("Gerenciar todas as extensões") { browserManager.openSettingsAction?() }
                .buttonStyle(SigmaStandardStyle(
                    color: Color.secondary.opacity(0.3),
                    hoveredColor: Color.secondary.opacity(0.2),
                    cornerRadius: 5,
                    scaleAmount: 0.97,
                    horizontalPadding: 10,
                    verticalPadding: 5,
                    fillContainer: true
                ))
                .padding(.top, 5)
        }
    }

    @ViewBuilder
    private func extensionIcon(_ path: String?) -> some View {
        if let path, let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 20, height: 20)
        } else {
            Image(systemName: "puzzlepiece.extension.fill").font(.body).foregroundStyle(Color.secondary)
        }
    }
}

/// Linha de preferência (`CreateWorkspaceToggleView`): texto primário com o toggle ligado e
/// secundário desligado; "?" que acende no hover com um anel que fecha em 1,6s; switch a 80%
/// tingido de mandarin.
struct SigmaSettingsToggle: View {
    let text: String
    let hint: String
    @Binding var isOn: Bool
    var disabled = false
    @State private var showHint = false

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            Text(text)
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
                .opacity(disabled ? 0.5 : 1)
            Image(systemName: "questionmark.circle.fill")
                .font(.body)
                .foregroundStyle(Color.secondary.opacity(showHint ? 1 : 0.2))
                .overlay(
                    Circle()
                        .trim(from: 0, to: showHint ? 1 : 0)
                        .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, miterLimit: 10))
                        .rotationEffect(.radians(-.pi / 2))
                        .opacity(showHint ? 1 : 0)
                )
                .animation(.easeInOut(duration: showHint ? 1.6 : 0.35), value: showHint)
                .onHover { showHint = $0 }
                .help(hint)
            Spacer(minLength: 5)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.8, anchor: .center)
                .tint(SigmaPalette.mandarin)
                .disabled(disabled)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Célula de grade de ícones (`IconButtonStyle`): mandarin a 50% na escolhida, +20% no hover, raio 8.
struct SigmaIconCellStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SigmaIconCellBody(isSelected: isSelected, configuration: configuration)
    }
}

private struct SigmaIconCellBody: View {
    let isSelected: Bool
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SigmaPalette.mandarin.opacity((isSelected ? 0.5 : 0) + (isHovered ? 0.2 : 0)))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

// MARK: - Lista de abas

struct SigmaTabList: View {
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    let spaceID: UUID

    var body: some View {
        let rows = tabs.rows(space: spaceID)
        let pinned = rows.filter { $0.section == .pinned }
        let open = rows.filter { $0.section == .tabs }
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: SigmaMetrics.tabListSpacing) {
                // Páginas travadas ficam no topo, separadas das demais por um fio.
                if !pinned.isEmpty {
                    ForEach(pinned) { row in rowView(row) }
                    Rectangle()
                        .fill(SigmaPalette.divider)
                        .frame(height: 1)
                        .padding(.horizontal, SigmaMetrics.tabRowHorizontalPadding)
                        .padding(.vertical, 2)
                }
                ForEach(open) { row in rowView(row) }
                SigmaNewPageRow { SigmaActions(tabs: tabs, window: windowState).newPage() }
                    .contextMenu {
                        Button("Nova pasta") { SigmaActions(tabs: tabs, window: windowState).newFolder() }
                    }
            }
            .padding(.bottom, SigmaMetrics.contentInset)
            .animation(SigmaMotion.list, value: rows.map(\.id))
        }
        .contextMenu {
            Button("Nova pasta") { SigmaActions(tabs: tabs, window: windowState).newFolder() }
        }
    }

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        if row.item.isFolder {
            SigmaFolderHeader(row: row)
        } else {
            SigmaTabRow(row: row)
        }
    }
}

/// Cabeçalho de seção: título na cor da seção, ícone opcional.
struct SigmaSectionHeader: View {
    let title: String
    var color: Color = SigmaPalette.sectionBlue
    var symbol: String?
    var isCollapsed: Bool?
    var depth = 0
    var onToggle: (() -> Void)?
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SigmaMetrics.dividerLabelSpacing) {
            Text(title)
                .font(SigmaType.dividerLabel)
                .foregroundStyle(color)
                .lineLimit(1)
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
            }
            if let isCollapsed, isHovered || isCollapsed {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(SigmaOpacity.dividerLabel))
                    .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, SigmaMetrics.tabRowHorizontalPadding + CGFloat(depth) * SigmaMetrics.subPageIndent)
        .padding(.trailing, SigmaMetrics.tabRowHorizontalPadding)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .frame(height: SigmaMetrics.dividerHeight)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(SigmaMotion.standard) { isHovered = hovering } }
        .onTapGesture { withAnimation(SigmaMotion.standard) { onToggle?() } }
    }
}

/// Pasta do Nook desenhada como seção do Sigma; a cor vem do workspace.
struct SigmaFolderHeader: View {
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    let row: Row
    @State private var isDropTarget = false

    var body: some View {
        let space = windowState.spaceID.flatMap { tabs.space($0) }
        SigmaSectionHeader(
            title: row.item.displayTitle.isEmpty ? "Nova pasta" : row.item.displayTitle,
            color: space?.accentColor ?? SigmaPalette.sectionBlue,
            isCollapsed: !tabs.isOpen(folder: row.item.id),
            depth: row.depth
        ) { tabs.toggleFolder(row.item.id) }
        .background(
            RoundedRectangle(cornerRadius: SigmaMetrics.cornerRadius, style: .continuous)
                .fill((space?.accentColor ?? SigmaPalette.sectionBlue).opacity(isDropTarget ? 0.15 : 0))
        )
        // Soltar uma aba (ou pasta) no cabeçalho guarda dentro da pasta.
        .dropDestination(for: String.self) { items, _ in
            guard let raw = items.first, let dragged = UUID(uuidString: raw) else { return false }
            SigmaActions(tabs: tabs, window: windowState).putInFolder(dragged, folderID: row.item.id)
            return true
        } isTargeted: { targeted in
            withAnimation(SigmaMotion.standard) { isDropTarget = targeted }
        }
        .draggable(row.item.id.uuidString)
        .contextMenu {
            Button("Renomear pasta") { SigmaUIState.of(windowState).renamingItemID = row.item.id }
            Button("Nova pasta") { SigmaActions(tabs: tabs, window: windowState).newFolder() }
            Divider()
            Button("Excluir pasta e abas", role: .destructive) { tabs.remove(row.item.id) }
        }
        .overlay {
            if SigmaUIState.of(windowState).renamingItemID == row.item.id {
                SigmaRenameField(text: row.item.displayTitle, font: SigmaType.dividerLabel) { title in
                    if let title { tabs.rename(row.item.id, title.isEmpty ? nil : title) }
                    SigmaUIState.of(windowState).renamingItemID = nil
                }
                .padding(.leading, SigmaMetrics.tabRowHorizontalPadding)
                .background(SigmaPalette.zero)
            }
        }
    }
}

/// Linha "Nova página" (`CreatePageButton`): `plus` title3 medium em 15 de largura, texto
/// secundário, 36 de altura; 40% de opacidade em repouso, 100% e fundo primary 10% no hover.
struct SigmaNewPageRow: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
                    .frame(width: 15)
                Text("Nova página")
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.secondary)
            .padding(.leading, 10)
            .frame(height: 36)
            .opacity(isHovered ? 1 : 0.4)
            .background(
                RoundedRectangle(cornerRadius: SigmaMetrics.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}

// MARK: - Rodapé

/// Rodapé: downloads, ajustes e atalhos.
struct SigmaSidebarFooter: View {
    @EnvironmentObject private var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) private var nookSettings

    private var themeSymbol: String {
        switch nookSettings.appearanceMode {
        case .light: "sun.max.circle.fill"
        case .dark: "moon.circle.fill"
        case .system: "circle.lefthalf.filled"
        }
    }

    private var themeName: String {
        switch nookSettings.appearanceMode {
        case .light: "claro"
        case .dark: "escuro"
        case .system: "sistema"
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Spacer()
            SigmaFooterIcon(systemName: themeSymbol, tooltip: "Tema: \(themeName) (também vale para os sites)") {
                let modes: [AppearanceMode] = [.light, .dark, .system]
                let next = modes[((modes.firstIndex(of: nookSettings.appearanceMode) ?? 0) + 1) % modes.count]
                nookSettings.appearanceMode = next
            }
            SigmaFooterIcon(systemName: "gearshape.circle.fill", tooltip: "Ajustes") {
                browserManager.openSettingsAction?()
            }
            SigmaFooterIcon(systemName: "command.circle.fill", tooltip: "Atalhos") {
                SigmaUIState.of(windowState).showingCheatSheet = true
            }
        }
        .padding(.trailing, 10)
        .frame(height: 30)
    }
}

/// Ícone do rodapé (`HelpActionButton`): system 14 semibold, `secondary` a 25% (70% e escala
/// 1,05 no hover), tooltip em popover.
struct SigmaFooterIcon: View {
    let systemName: String
    let tooltip: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(isHovered ? 0.7 : 0.25))
                .scaleEffect(isHovered ? 1.05 : 1)
                .animation(SigmaMotion.standard, value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .sigmaTooltip(isHovered ? SigmaTooltip(text: tooltip) : nil)
    }
}
