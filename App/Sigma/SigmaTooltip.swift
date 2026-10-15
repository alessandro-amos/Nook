// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaTooltip.swift
//  Sigma
//
//  Tooltip desenhado no nível da janela (pode sair da sidebar por cima do conteúdo), campo de
//  renomear inline e a folha de atalhos.
//

import AppKit
import SwiftUI

struct SigmaTooltip: Equatable {
    enum Placement { case trailing, below }

    var text: String
    var keys: [String] = []
    var placement: Placement = .trailing
}

extension View {
    /// Mostra o tooltip junto desta view enquanto `tooltip` não for nil. Como no SigmaOS
    /// (`AddTooltip`), é um NSPopover de verdade que abre 0,3s depois do hover.
    func sigmaTooltip(_ tooltip: SigmaTooltip?) -> some View {
        background(SigmaTooltipAnchor(tooltip: tooltip))
    }

    /// Mantido por compatibilidade: os tooltips agora são popovers e não precisam de camada.
    func sigmaTooltipLayer() -> some View { self }
}

/// Âncora AppKit do popover de tooltip.
private struct SigmaTooltipAnchor: NSViewRepresentable {
    let tooltip: SigmaTooltip?

    func makeNSView(context: Context) -> SigmaTooltipAnchorView { SigmaTooltipAnchorView() }

    func updateNSView(_ view: SigmaTooltipAnchorView, context: Context) { view.update(tooltip) }

    static func dismantleNSView(_ view: SigmaTooltipAnchorView, coordinator: ()) { view.update(nil) }
}

final class SigmaTooltipAnchorView: NSView {
    private var popover: NSPopover?
    private var pending: DispatchWorkItem?
    private var current: SigmaTooltip?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ tooltip: SigmaTooltip?) {
        guard tooltip != current else { return }
        current = tooltip
        pending?.cancel()
        guard let tooltip else {
            popover?.close()
            popover = nil
            return
        }
        if let popover, popover.isShown {
            (popover.contentViewController as? NSHostingController<SigmaTooltipContent>)?.rootView = SigmaTooltipContent(tooltip: tooltip)
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.show(tooltip) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func show(_ tooltip: SigmaTooltip) {
        guard window != nil, current == tooltip else { return }
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = true
        let host = NSHostingController(rootView: SigmaTooltipContent(tooltip: tooltip))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.show(relativeTo: bounds, of: self, preferredEdge: tooltip.placement == .below ? .minY : .maxX)
        self.popover = popover
    }
}

/// Conteúdo do tooltip (`ToolTipView`): texto do sistema em primary, teclas à direita, padding
/// 10×2, altura mínima 35, fundo `zero` cobrindo o popover.
struct SigmaTooltipContent: View {
    let tooltip: SigmaTooltip

    var body: some View {
        HStack {
            Text(tooltip.text)
                .foregroundStyle(Color.primary)
                .padding(.vertical, 5)
            ForEach(tooltip.keys, id: \.self) { SigmaKeyBadge(key: $0) }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .frame(minHeight: 35)
        .background(SigmaPalette.zero.padding(-80))
    }
}

/// Tecla (`KeyboardShortcutView`, size 20, filled): raio 3, altura 20, texto em maiúsculas com
/// kerning −0,75. As cores do keycap no tooltip não foram confirmadas na decompilação.
struct SigmaKeyBadge: View {
    let key: String

    var body: some View {
        Text(key.uppercased())
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .kerning(-0.75)
            .foregroundStyle(.white)
            .padding(.vertical, 1)
            .padding(.horizontal, 2)
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(SigmaPalette.mandarin))
    }
}

struct SigmaTooltipBubble: View {
    let tooltip: SigmaTooltip
    var arrow = false
    var arrowOffset: CGFloat = 0

    var body: some View {
        SigmaTooltipContent(tooltip: tooltip)
            .background(SigmaBubbleShape(arrow: arrow, arrowOffset: arrowOffset).fill(SigmaPalette.zero))
            .padding(.top, arrow ? 7 : 0)
    }
}

/// Retângulo arredondado com seta opcional centralizada no topo.
struct SigmaBubbleShape: Shape {
    var arrow: Bool
    /// Deslocamento da seta a partir do centro, para apontar o botão quando a bolha encosta na margem.
    var arrowOffset: CGFloat = 0
    var radius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: min(radius, rect.height / 2), style: .continuous)
        if arrow {
            let w: CGFloat = 16, h: CGFloat = 7
            let inset = min(radius, rect.height / 2) + w / 2
            let midX = min(max(rect.midX + arrowOffset, rect.minX + inset), rect.maxX - inset)
            var tip = Path()
            tip.move(to: CGPoint(x: midX - w / 2, y: rect.minY + 0.5))
            tip.addQuadCurve(to: CGPoint(x: midX, y: rect.minY - h),
                             control: CGPoint(x: midX - 2, y: rect.minY - h + 1))
            tip.addQuadCurve(to: CGPoint(x: midX + w / 2, y: rect.minY + 0.5),
                             control: CGPoint(x: midX + 2, y: rect.minY - h + 1))
            tip.closeSubpath()
            path.addPath(tip)
        }
        return path
    }
}

/// Campo de renomear inline: Enter confirma, Esc cancela, perder o foco confirma.
struct SigmaRenameField: View {
    @State private var value: String
    @FocusState private var focused: Bool
    var font: Font
    let commit: (String?) -> Void

    init(text: String, font: Font = .system(size: 13), commit: @escaping (String?) -> Void) {
        _value = State(initialValue: text)
        self.font = font
        self.commit = commit
    }

    var body: some View {
        TextField("", text: $value)
            .textFieldStyle(.plain)
            .font(font)
            .focused($focused)
            .onSubmit { commit(value.trimmingCharacters(in: .whitespaces)) }
            .onExitCommand { commit(nil) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit(value.trimmingCharacters(in: .whitespaces)) }
            }
            .onAppear { focused = true }
    }
}

struct SigmaCheatSheet: View {
    private let shortcuts: [(String, [String])] = [
        ("Buscar / nova página", ["⌘", "T"]),
        ("Marcar aba como concluída", ["⌘", "D"]),
        ("Limpar workspace", ["⌘", "⇧", "K"]),
        ("Travar / destravar página", ["⌘", "⇧", "L"]),
        ("Desfazer última ação", ["⌘", "⌥", "⇧", "Z"]),
        ("Mostrar/ocultar sidebar", ["⌘", "S"]),
        ("Workspace anterior / próximo", ["⌘", "⌥", "↑ ↓"]),
        ("Aba anterior / próxima", ["⌃", "⇥"]),
        ("Recarregar", ["⌘", "R"]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Atalhos")
                .font(.system(size: 20, weight: .semibold))
                .padding(.bottom, 6)
            ForEach(shortcuts, id: \.0) { item in
                HStack {
                    Text(item.0).font(.system(size: 15)).foregroundStyle(Color.primary.opacity(0.75))
                    Spacer(minLength: 30)
                    HStack(spacing: 4) { ForEach(item.1, id: \.self) { SigmaKeyBadge(key: $0) } }
                }
            }
        }
        .padding(28)
        .frame(width: 440)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SigmaPalette.base))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
    }
}
