// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaModel.swift
//  Sigma
//
//  Estado da interface do Sigma por janela, cor da página extraída do favicon e as ações do
//  Sigma (concluir, clean up, travar, mover, novo workspace) traduzidas para o TabsController.
//

import AppKit
import SwiftUI
import NookTabsCore
import NookWeb

/// Estado efêmero da interface, um por janela. Os comandos de menu chegam aqui pela janela ativa.
@MainActor
@Observable
final class SigmaUIState {
    /// O que o título do workspace está editando (renomear, ícone, configurações).
    var workspaceEditing: SigmaWorkspaceEditing?
    var renamingItemID: UUID?
    var showingCheatSheet = false
    var confirmingCleanUp = false
    /// Modo leitura aberto sobre a página.
    var reader: SigmaReaderContent?
    /// Barra de comando sobreposta aberta (lupa, ⌘L, clique na pílula).
    var commandRequest: SigmaCommandRequest?
    /// Aviso curto no topo da janela ("destrave antes de concluir", "página concluída").
    var notice: SigmaNotice?

    private static var byWindow: [UUID: SigmaUIState] = [:]

    static func of(_ window: BrowserWindowState) -> SigmaUIState {
        if let state = byWindow[window.id] { return state }
        let state = SigmaUIState()
        byWindow[window.id] = state
        return state
    }

    func notify(_ text: String, canUndo: Bool = false) {
        let notice = SigmaNotice(text: text, canUndo: canUndo)
        withAnimation(SigmaMotion.standard) { self.notice = notice }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(canUndo ? 4 : 2.5))
            guard let self, self.notice?.id == notice.id else { return }
            withAnimation(SigmaMotion.standard) { self.notice = nil }
        }
    }
}

struct SigmaNotice: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var canUndo: Bool
}

/// Cor de destaque por host, tirada do favicon em cache (nil para favicons monocromáticos).
@MainActor
@Observable
final class SigmaPageColor {
    static let shared = SigmaPageColor()

    private var colors: [String: Color] = [:]
    @ObservationIgnored private var resolved: Set<String> = []

    func color(for url: URL?) -> Color? {
        guard let host = url?.host else { return nil }
        return colors[host]
    }

    /// Lê o favicon do cache e calcula a cor uma vez por host. Tenta de novo enquanto o favicon
    /// ainda não chegou.
    func resolve(_ url: URL?) async {
        guard let host = url?.host, !resolved.contains(host) else { return }
        for _ in 0..<6 {
            if let image = await FaviconCache.shared.cachedImage(for: host) {
                resolved.insert(host)
                if let data = image.tiffRepresentation, let accent = Self.accent(from: data) {
                    colors[host] = Color(nsColor: accent)
                }
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
            if Task.isCancelled { return }
        }
    }

    /// Média dos pixels saturados, normalizada para um tom vivo.
    static func accent(from data: Data) -> NSColor? {
        guard let image = NSImage(data: data),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))

        var r = 0.0, g = 0.0, b = 0.0, weight = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3]) / 255
            guard a > 0.5 else { continue }
            let pr = Double(pixels[i]) / 255 / a, pg = Double(pixels[i + 1]) / 255 / a, pb = Double(pixels[i + 2]) / 255 / a
            let maxC = max(pr, pg, pb), minC = min(pr, pg, pb)
            let sat = maxC == 0 ? 0 : (maxC - minC) / maxC
            guard sat > 0.25, maxC > 0.25 else { continue }
            let w = sat * maxC
            r += pr * w; g += pg * w; b += pb * w; weight += w
        }
        guard weight > 0.5 else { return nil }
        let avg = NSColor(srgbRed: r / weight, green: g / weight, blue: b / weight, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0
        avg.usingColorSpace(.sRGB)?.getHue(&h, saturation: &s, brightness: &v, alpha: nil)
        return NSColor(hue: h, saturation: min(max(s, 0.55), 0.85), brightness: 1, alpha: 1)
    }
}

/// Ações do Sigma sobre a janela. Página travada do Sigma = aba fixada do Nook: fica no topo do
/// workspace, guarda o endereço travado (home URL) e não pode ser concluída.
@MainActor
struct SigmaActions {
    let tabs: TabsController
    let window: BrowserWindowState

    var ui: SigmaUIState { .of(window) }

    var currentSpace: SpaceRecord? { window.spaceID.flatMap { tabs.space($0) } }

    /// Cor que tinge a interface: a da página atual ou, sem ela, a do workspace.
    var pageColor: Color {
        let url = window.selectedItemID.flatMap { tabs.item($0) }.flatMap { tabs.currentURL(for: $0) }
        return SigmaPageColor.shared.color(for: url) ?? currentSpace?.accentColor ?? SigmaPalette.raspberry
    }

    var locks: SigmaLocks { .shared }

    /// Travada pelo Sigma, ou fixada no Nook (a seção de fixadas também é poupada).
    func isLocked(_ id: UUID) -> Bool {
        if locks.isLocked(id) { return true }
        if case .pinned = tabs.section(of: id) { return true }
        return false
    }

    /// A página travada saiu do endereço travado.
    func hasLeftLocked(_ id: UUID) -> Bool {
        guard let item = tabs.item(id) else { return false }
        if locks.isLocked(id) { return locks.hasLeft(id, current: tabs.currentURL(for: item)) }
        return tabs.hasLeftHome(id)
    }

    func goBackToLocked(_ id: UUID) {
        if let url = locks.lockedURLs[id] {
            tabs.ensureSession(for: id)?.load(url)
        } else {
            tabs.resetToHome(id)
        }
    }

    func updateLocked(_ id: UUID) {
        guard let item = tabs.item(id) else { return }
        if locks.isLocked(id), let url = tabs.currentURL(for: item) {
            locks.lock(id, at: url)
        } else {
            tabs.setHomeToCurrent(id)
        }
    }

    /// Páginas que o clean up concluiria: todas as não travadas do workspace.
    var cleanableItems: [UUID] {
        guard let spaceID = window.spaceID else { return [] }
        return tabs.rows(space: spaceID)
            .filter { $0.section == .tabs && !$0.item.isFolder && !locks.isLocked($0.item.id) }
            .map(\.item.id)
    }

    /// Conclui a página: ela some (com desfazer). Travadas precisam ser destravadas antes.
    func markDone(_ id: UUID? = nil) {
        guard let id = id ?? window.selectedItemID, let item = tabs.item(id), !item.isFolder else { return }
        if isLocked(id) {
            ui.notify("Destrave esta página antes de marcar como concluída!")
            return
        }
        withAnimation(SigmaMotion.list) { tabs.close(id) }
        locks.forget([id])
        ui.notify("Página concluída", canUndo: true)
    }

    /// Conclui todas as páginas não travadas do workspace.
    func cleanUp() {
        let ids = cleanableItems
        guard !ids.isEmpty else { return }
        withAnimation(SigmaMotion.list) {
            ui.confirmingCleanUp = false
            for id in ids where tabs.item(id) != nil { tabs.close(id) }
        }
        ui.notify(ids.count == 1 ? "1 página concluída" : "\(ids.count) páginas concluídas", canUndo: ids.count == 1)
    }

    func undo() {
        tabs.reopenLastClosed(in: window)
        withAnimation(SigmaMotion.standard) { ui.notice = nil }
    }

    /// Travar guarda o endereço atual; a página fica no lugar.
    func toggleLocked(_ id: UUID? = nil) {
        guard let id = id ?? window.selectedItemID, let item = tabs.item(id), !item.isFolder else { return }
        withAnimation(SigmaMotion.standard) {
            if locks.isLocked(id) {
                locks.unlock(id)
            } else if case .pinned = tabs.section(of: id) {
                tabs.unpin(id)
            } else if let url = tabs.currentURL(for: item) {
                locks.lock(id, at: url)
            }
        }
    }

    /// Põe a aba arrastada logo antes de `target`, no mesmo nível dele. Soltar na área travada trava.
    func move(_ id: UUID, before target: Item) {
        guard id != target.id, tabs.item(id) != nil else { return }
        let siblings = tabs.children(of: target.parent).filter { $0.id != id }
        guard let index = siblings.firstIndex(where: { $0.id == target.id }) else { return }
        let after = index > 0 ? siblings[index - 1].id : nil
        withAnimation(SigmaMotion.list) { tabs.move(id, to: target.parent, after: after) }
    }

    /// Pasta nova no fim da lista de abas, já em modo de renomear.
    func newFolder() {
        guard let spaceID = window.spaceID else { return }
        let parent = Parent.tabs(spaceID: spaceID)
        guard let id = tabs.createFolder(title: "Nova pasta", in: parent, after: tabs.children(of: parent).last?.id) else { return }
        ui.renamingItemID = id
    }

    /// Guarda a aba (ou pasta) arrastada no fim de `folderID` e abre a pasta.
    func putInFolder(_ id: UUID, folderID: UUID) {
        guard id != folderID, tabs.item(id) != nil else { return }
        let parent = Parent.folder(itemID: folderID)
        let last = tabs.children(of: parent).last(where: { $0.id != id })?.id
        withAnimation(SigmaMotion.list) {
            tabs.move(id, to: parent, after: last)
            if !tabs.isOpen(folder: folderID) { tabs.toggleFolder(folderID) }
        }
    }

    /// Junta a aba arrastada como última sub-aba de `parentID`.
    func nest(_ id: UUID, under parentID: UUID) {
        guard id != parentID, tabs.item(id) != nil, tabs.tree.canTakeChild(parentID) else { return }
        let parent = Parent.folder(itemID: parentID)
        let last = tabs.children(of: parent).last(where: { $0.id != id })?.id
        withAnimation(SigmaMotion.list) {
            tabs.move(id, to: parent, after: last)
            if !tabs.isOpen(folder: parentID) { tabs.toggleFolder(parentID) }
        }
    }

    func switchTo(_ space: SpaceRecord) {
        withAnimation(SigmaMotion.workspaceSwitch) { tabs.setSpace(space.id, in: window) }
    }

    func selectAdjacentSpace(_ delta: Int) {
        withAnimation(SigmaMotion.workspaceSwitch) {
            delta > 0 ? tabs.selectNextSpace(in: window) : tabs.selectPreviousSpace(in: window)
        }
    }

    func addSpace() {
        let count = tabs.orderedSpaces.count
        guard let id = tabs.createSpace(
            name: "Novo workspace",
            icon: SigmaPalette.workspaceEmojis[count % SigmaPalette.workspaceEmojis.count],
            accentHex: SigmaPalette.workspaceHexes[count % SigmaPalette.workspaceHexes.count],
            after: tabs.orderedSpaces.last?.id
        ) else { return }
        withAnimation(SigmaMotion.workspaceSwitch) { tabs.setSpace(id, in: window) }
        ui.workspaceEditing = .title
    }

    /// ⌘T e "Nova página": como no SigmaOS, abre a barra de comando; a aba só nasce ao escolher.
    func newPage() {
        openCommandBar()
    }

    /// Barra sobreposta. `replace` troca a página atual (⌘L, clique na pílula).
    func openCommandBar(prefill: String = "", replace: Bool = false, split: Bool = false) {
        withAnimation(SigmaMotion.fade) { ui.commandRequest = SigmaCommandRequest(prefill: prefill, replace: replace, split: split) }
    }

    func copyLink(_ item: Item) {
        guard let url = tabs.currentURL(for: item) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}

extension SpaceRecord {
    /// O ícone do space é emoji (Sigma, import do Arc) ou nome de SF Symbol (padrão do Nook).
    var isEmojiIcon: Bool {
        guard let scalar = icon.unicodeScalars.first else { return false }
        return scalar.properties.isEmojiPresentation || (icon.unicodeScalars.count > 1 && scalar.properties.isEmoji)
    }
}

/// Ícone do space, como o `IconViewPrime` do SigmaOS: emoji ou SF Symbol na fonte dada, ou
/// imagem (aba Custom, guardada como caminho de arquivo) recortada com `imageRadius`, num quadro
/// `size`×`size`. Sem fonte, usa `.system(size: size)` (chamadas antigas).
struct SigmaSpaceIcon: View {
    let space: SpaceRecord
    var font: Font?
    var size: CGFloat = 22
    var imageRadius: CGFloat = 5

    var body: some View {
        Group {
            if let image = SigmaCustomIcons.image(for: space.icon) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: imageRadius, style: .continuous))
            } else if space.isEmojiIcon {
                Text(space.icon).font(font ?? .system(size: size))
            } else {
                Image(systemName: space.icon.isEmpty ? "square.grid.2x2" : space.icon)
                    .font(font ?? .system(size: size * 0.75))
                    .foregroundStyle(Color.primary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Ícones enviados pela aba Custom: ficam em Application Support/Sigma/WorkspaceIcons e o space
/// guarda o caminho do arquivo no lugar do emoji.
enum SigmaCustomIcons {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sigma/WorkspaceIcons", isDirectory: true)
    }()

    private static var cache: [String: NSImage] = [:]

    static func isCustom(_ icon: String) -> Bool { icon.hasPrefix(directory.path) }

    static func image(for icon: String) -> NSImage? {
        guard isCustom(icon) else { return nil }
        if let cached = cache[icon] { return cached }
        let image = NSImage(contentsOfFile: icon)
        cache[icon] = image
        return image
    }

    /// Grava a imagem como PNG e devolve o caminho a guardar no space.
    static func store(_ image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString + ".png")
        guard (try? png.write(to: url)) != nil else { return nil }
        return url.path
    }
}
