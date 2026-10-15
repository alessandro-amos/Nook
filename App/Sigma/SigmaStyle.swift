// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaStyle.swift
//  Sigma
//
//  Peças de estilo que o SigmaOS reusa em quase todo botão, lidas da decompilação
//  (~/Development/sigmaos/decomp/specs): `Color.highlighted(_:)`, que mexe só na luminosidade
//  HSLuv, e o ButtonStyle `Standard`.
//

import AppKit
import SwiftUI

// MARK: - highlighted

/// Quanto `highlighted` clareia/escurece: delta `a` e limiar `t` em luminosidade HSLuv (0–100).
enum SigmaHighlight {
    case low, mild, medium, strong, extreme

    fileprivate var delta: Double {
        switch self { case .low: 3; case .mild: 5; case .medium: 14; case .strong: 20; case .extreme: 30 }
    }

    fileprivate var threshold: Double {
        switch self { case .low, .mild: 10; case .medium: 14; case .strong: 20; case .extreme: 30 }
    }
}

extension NSColor {
    /// Regra do SigmaOS (Utilities): L < t → L + 2,5a; 50 ≤ L ≤ 100 − t → L + a; senão L − a.
    /// Matiz, saturação e alfa ficam iguais.
    func sigmaHighlighted(_ amount: SigmaHighlight = .low) -> NSColor {
        guard let rgb = usingColorSpace(.sRGB) else { return self }
        var (h, s, l) = SigmaHSLuv.fromRGB(Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
        if l < amount.threshold {
            l += amount.delta * 2.5
        } else if l >= 50 && l <= 100 - amount.threshold {
            l += amount.delta
        } else {
            l -= amount.delta
        }
        let (r, g, b) = SigmaHSLuv.toRGB(h, s, min(max(l, 0), 100))
        return NSColor(srgbRed: r, green: g, blue: b, alpha: rgb.alphaComponent)
    }
}

extension Color {
    /// `Color.highlighted(.low)` do SigmaOS, resolvido para claro e escuro.
    func sigmaHighlighted(_ amount: SigmaHighlight = .low) -> Color {
        let base = NSColor(self)
        return Color(nsColor: NSColor(name: nil) { appearance in
            var resolved = base
            appearance.performAsCurrentDrawingAppearance { resolved = base.usingColorSpace(.sRGB) ?? base }
            return resolved.sigmaHighlighted(amount)
        })
    }
}

/// Conversão sRGB ↔ HSLuv (algoritmo de referência do HSLuv).
enum SigmaHSLuv {
    private static let m: [[Double]] = [
        [3.240969941904521, -1.537383177570093, -0.498610760293],
        [-0.96924363628087, 1.87596750150772, 0.041555057407175],
        [0.055630079696993, -0.20397695888897, 1.056971514242878],
    ]
    private static let minv: [[Double]] = [
        [0.41239079926595, 0.35758433938387, 0.18048078840183],
        [0.21263900587151, 0.71516867876775, 0.072192315360733],
        [0.019330818715591, 0.11919477979462, 0.95053215224966],
    ]
    private static let refU = 0.19783000664283
    private static let refV = 0.46831999493879
    private static let kappa = 903.2962962
    private static let epsilon = 0.0088564516

    static func fromRGB(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let lin = [toLinear(r), toLinear(g), toLinear(b)]
        let xyz = minv.map { $0[0] * lin[0] + $0[1] * lin[1] + $0[2] * lin[2] }
        let (l, u, v) = xyzToLuv(xyz[0], xyz[1], xyz[2])
        let c = (u * u + v * v).squareRoot()
        var h = 0.0
        if c >= 1e-8 {
            h = atan2(v, u) * 180 / .pi
            if h < 0 { h += 360 }
        }
        if l > 99.9999999 { return (h, 0, 100) }
        if l < 1e-8 { return (h, 0, 0) }
        return (h, c / maxChroma(l, h) * 100, l)
    }

    static func toRGB(_ h: Double, _ s: Double, _ l: Double) -> (Double, Double, Double) {
        let c: Double
        if l > 99.9999999 || l < 1e-8 { c = 0 } else { c = maxChroma(l, h) / 100 * s }
        let hrad = h / 180 * .pi
        let (x, y, z) = luvToXyz(l, cos(hrad) * c, sin(hrad) * c)
        let rgb = m.map { $0[0] * x + $0[1] * y + $0[2] * z }
        return (fromLinear(rgb[0]), fromLinear(rgb[1]), fromLinear(rgb[2]))
    }

    private static func toLinear(_ c: Double) -> Double { c > 0.04045 ? pow((c + 0.055) / 1.055, 2.4) : c / 12.92 }
    private static func fromLinear(_ c: Double) -> Double {
        min(max(c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055, 0), 1)
    }

    private static func xyzToLuv(_ x: Double, _ y: Double, _ z: Double) -> (Double, Double, Double) {
        let divider = x + 15 * y + 3 * z
        let l = y <= epsilon ? y * kappa : 116 * cbrt(y) - 16
        guard l > 0, divider != 0 else { return (0, 0, 0) }
        let varU = 4 * x / divider, varV = 9 * y / divider
        return (l, 13 * l * (varU - refU), 13 * l * (varV - refV))
    }

    private static func luvToXyz(_ l: Double, _ u: Double, _ v: Double) -> (Double, Double, Double) {
        guard l > 0 else { return (0, 0, 0) }
        let varU = u / (13 * l) + refU, varV = v / (13 * l) + refV
        let y = l <= 8 ? l / kappa : pow((l + 16) / 116, 3)
        let x = 0 - (9 * y * varU) / ((varU - 4) * varV - varU * varV)
        let z = (9 * y - 15 * varV * y - varV * x) / (3 * varV)
        return (x, y, z)
    }

    private static func maxChroma(_ l: Double, _ h: Double) -> Double {
        let hrad = h / 360 * .pi * 2
        let sub1 = pow(l + 16, 3) / 1560896
        let sub2 = sub1 > epsilon ? sub1 : l / kappa
        var result = Double.greatestFiniteMagnitude
        for row in m {
            let (m1, m2, m3) = (row[0], row[1], row[2])
            for t in [0.0, 1.0] {
                let top1 = (284517 * m1 - 94839 * m3) * sub2
                let top2 = (838422 * m3 + 769860 * m2 + 731718 * m1) * l * sub2 - 769860 * t * l
                let bottom = (632260 * m3 - 126452 * m2) * sub2 + 126452 * t
                let length = (top2 / bottom) / (sin(hrad) - (top1 / bottom) * cos(hrad))
                if length >= 0 { result = min(result, length) }
            }
        }
        return result
    }
}

// MARK: - Standard

/// O ButtonStyle `Standard` do SigmaOS: fundo arredondado contínuo que troca no hover e ao
/// pressionar (sem cor própria, cai em `color.highlighted(.low)`), escala opcional ao
/// pressionar, mola (0.15, 0.85, 0.25) ao apertar e (0.2, 0.3, 0) ao soltar.
struct SigmaStandardStyle: ButtonStyle {
    var color: Color = .clear
    var hoveredColor: Color?
    var pressedColor: Color?
    var cornerRadius: CGFloat = 10
    var scaleAmount: CGFloat?
    var foregroundColor: Color = .primary
    var font: Font? = .headline.weight(.medium)
    var horizontalPadding: CGFloat = 0
    var verticalPadding: CGFloat = 0
    var fillContainer = false

    func makeBody(configuration: Configuration) -> some View {
        SigmaStandardBody(style: self, configuration: configuration)
    }
}

private struct SigmaStandardBody: View {
    let style: SigmaStandardStyle
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var fill: Color {
        if configuration.isPressed { return style.pressedColor ?? style.color.sigmaHighlighted() }
        if isHovered { return style.hoveredColor ?? style.color.sigmaHighlighted() }
        return style.color
    }

    var body: some View {
        configuration.label
            .font(style.font)
            .foregroundStyle(style.foregroundColor)
            .padding(.horizontal, style.horizontalPadding)
            .padding(.vertical, style.verticalPadding)
            .frame(maxWidth: style.fillContainer ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous).fill(fill))
            .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? (style.scaleAmount ?? 1) : 1)
            .animation(configuration.isPressed ? SigmaMotion.standard : SigmaMotion.release, value: configuration.isPressed)
            .animation(SigmaMotion.standard, value: isHovered)
            .onHover { hovering in isHovered = hovering && isEnabled }
    }
}
