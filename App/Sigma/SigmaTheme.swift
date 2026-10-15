// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaTheme.swift
//  Sigma
//
//  Tokens visuais do Sigma (paleta, medidas, opacidades, tipografia, movimento), lidos do
//  SigmaOS original. Usados só pela interface do Sigma em Navigation/Sigma.
//

import AppKit
import CoreText
import SwiftUI

extension Color {
    /// Cor com variante clara/escura resolvida pela aparência atual.
    init(sigmaLight light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

private func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: alpha)
}

private func p3(_ hex: UInt32) -> NSColor {
    NSColor(displayP3Red: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1)
}

enum SigmaPalette {
    // Superfícies
    static let base = Color(sigmaLight: srgb(0xFFFEFD), dark: srgb(0x14161E))
    static let zero = Color(sigmaLight: srgb(0xFFFCFA), dark: srgb(0x15171E))
    static let content = Color(sigmaLight: srgb(0xFFFFFF), dark: srgb(0x1B1D25))
    /// Fundo pêssego das abas e campos dos popovers (seletor de ícone).
    static let peachCarbon = Color(sigmaLight: srgb(0xFFF1E6), dark: srgb(0x494C50))

    // Acentos
    static let sigmaPurple = Color(sigmaLight: srgb(0xA38CF6), dark: srgb(0xB7A8F5))
    static let fig = Color(sigmaLight: p3(0x9272FF), dark: p3(0xC1B4FF))
    static let sigmaOrange = Color(sigmaLight: srgb(0xEB802F), dark: srgb(0xF79C6D))
    static let mandarin = Color(sigmaLight: p3(0xFF9638), dark: p3(0xFFB472))
    static let raspberry = Color(sigmaLight: p3(0xFF4D70), dark: p3(0xFF7893))
    static let sectionBlue = Color(sigmaLight: srgb(0x5B9CF2), dark: srgb(0x7FB1F5))

    // Camadas
    static let focusOverlay = Color.black.opacity(0.4)
    /// Fundo atrás da barra de comando (`ExitModalRectangle`): cinza 0.6 / 0.4 a 30%.
    static let modalDim = Color(sigmaLight: NSColor(white: 0.6, alpha: 1), dark: NSColor(white: 0.4, alpha: 1)).opacity(0.3)
    static let divider = Color.primary.opacity(0.08)

    /// Cores de workspace novas, em hex porque o Nook guarda o acento do space assim.
    static let workspaceHexes = ["#FF4D70", "#FF9638", "#9272FF", "#5B9CF2", "#EB802F", "#A38CF6"]
    static let workspaceEmojis = ["🌱", "📚", "🎨", "🚀", "🧪", "🏝️", "🎯", "🍕"]
}

enum SigmaMetrics {
    static let cornerRadius: CGFloat = 10
    /// Cartão da página (`CornerRadius(8, inset: 1.5)`).
    static let pageRadius: CGFloat = 8

    // Janela
    static let chromeHeight: CGFloat = 48
    static let contentInset: CGFloat = 8
    static let trafficLight: CGFloat = 12
    static let trafficLightX: [CGFloat] = [15, 34, 53]
    static let trafficLightY: CGFloat = 19

    // Barra de URL
    static let urlBarHeight: CGFloat = 30
    static let urlBarRadius: CGFloat = 5
    static let urlBarButton = CGSize(width: 24, height: 30)
    static let chromeButton = CGSize(width: 45, height: 38)

    // Sidebar
    static let sidebarWidth: CGFloat = 315
    static let railX: CGFloat = 5
    static let railWidth: CGFloat = 50
    static let railSpacing: CGFloat = 6
    static let listX: CGFloat = 60
    static let listTrailing: CGFloat = 8

    // Lista de abas
    static let tabListSpacing: CGFloat = 0
    static let tabRowHeight: CGFloat = 40
    static let newPageRowHeight: CGFloat = 46
    static let tabRowHorizontalPadding: CGFloat = 10
    static let tabRowSpacing: CGFloat = 10
    static let faviconSize: CGFloat = 15
    static let subPageIndent: CGFloat = 30
    static let scrollFadeHeight: CGFloat = 5

    // Divisor de seção
    static let dividerHeight: CGFloat = 34
    static let dividerLabelSpacing: CGFloat = 6

    // Workspaces
    static let workspaceTitleHeight: CGFloat = 35
    static let workspaceButton: CGFloat = 38

    // Tooltip
    static let tooltipMinHeight: CGFloat = 35
    static let tooltipPaddingH: CGFloat = 10
    static let tooltipPaddingV: CGFloat = 2
}

enum SigmaOpacity {
    static let textActive = 0.85
    static let textInactive = 0.7
    static let textDone = 0.35
    static let pageSelected = 0.25
    static let pageHovered = 0.125
    static let pageBar = 0.14
    static let rowHovered = 0.05
    static let dividerLabel = 0.8
    static let secondaryIcon = 0.5
    static let pressed = 0.8
    static let workspaceActive = 0.25
}

/// Jokker, a fonte do SigmaOS. Não vem no repositório: é registrada para este processo a partir
/// do SigmaOS instalado em /Applications. Sem ele, cai na fonte do sistema.
enum SigmaFont {
    private static let path = "/Applications/SigmaOS.app/Contents/Resources/JokkerVF.ttf"

    static let isAvailable: Bool = {
        let url = URL(fileURLWithPath: path) as CFURL
        guard FileManager.default.fileExists(atPath: path) else { return false }
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url, .process, &error) { return true }
        // Já registrada (outra janela, relançamento da cena) também serve.
        return NSFont(name: "Jokker-Regular", size: 13) != nil
    }()

    /// A Jokker é variável e o padrão do arquivo é peso 100 (Thin); a instância "Regular" não
    /// traz variação e cai nesse padrão. Por isso o peso vai explícito no eixo wght, com os
    /// valores das instâncias do próprio arquivo (RegularItalic = 336, Medium = 470…).
    static func of(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard isAvailable else { return .system(size: size, weight: weight) }
        return Font(nsFont(size, weight))
    }

    private static let weightAxis = 0x77676874 // 'wght'

    static func nsFont(_ size: CGFloat, _ weight: Font.Weight) -> NSFont {
        let value: CGFloat
        switch weight {
        case .ultraLight, .thin: value = 150
        case .light: value = 230
        case .medium: value = 470
        case .semibold: value = 617
        case .bold: value = 767
        case .heavy, .black: value = 900
        default: value = 336
        }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .name: "Jokker-Regular",
            NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [weightAxis: value],
        ])
        return NSFont(descriptor: descriptor, size: size) ?? .systemFont(ofSize: size)
    }
}

enum SigmaType {
    static let tabTitle = Font.body
    static let urlBar = Font.system(.body, design: .default).weight(.medium)
    static let tooltip = Font.body
    static let dividerLabel = Font.system(size: 14, weight: .medium)
    /// `.title2` medium (system 17); o Text leva `.kerning(0.1)`.
    static let workspaceTitle = Font.title2.weight(.medium)
    static let body = Font.body
    static let heading = Font.headline
    static let commandInput = Font.system(size: 18, weight: .regular)
    static let commandRow = Font.system(size: 13, weight: .regular)
    static let commandSection = Font.body
}

enum SigmaMotion {
    /// Mola padrão usada em quase todas as interações.
    static let standard = Animation.spring(response: 0.15, dampingFraction: 0.85, blendDuration: 0.25)
    static let list = Animation.spring(response: 0.5, dampingFraction: 1.0)
    static let workspaceSwitch = Animation.interactiveSpring(response: 0.2, dampingFraction: 0.86, blendDuration: 0.25)
    static let fade = Animation.easeInOut(duration: 0.2)
    /// Mola ao soltar um botão `Standard`.
    static let release = Animation.spring(response: 0.2, dampingFraction: 0.3, blendDuration: 0)
    /// Arrastar no trilho de workspaces.
    static let railDrag = Animation.interactiveSpring(response: 0.15, dampingFraction: 0.6, blendDuration: 0.25)

    /// Entrada dos botões de ação da aba: desliza 10pt da direita com fade.
    static let actionTransition = AnyTransition.offset(x: 10).combined(with: .opacity)
}

struct SigmaPressedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? SigmaOpacity.pressed : 1)
    }
}
