// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaIconPicker.swift
//  Sigma
//
//  Seletor do ícone do workspace (`WorkspaceIconEditor` do SigmaOS), aberto ao clicar no emoji
//  ao lado do título: abas Emojis / Ícones / Personalizado com indicador que desliza, busca,
//  grade de 7 colunas, tom de pele e preenchido. Medidas em ~/Development/sigmaos/decomp/specs/
//  workspaces.md §4. A lista de emojis (categorias e palavras-chave) é lida do SigmaOS
//  instalado em /Applications, nunca copiada; sem ele, só os favoritos aparecem.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import NookTabsCore
import NookWeb

struct SigmaEmoji: Identifiable, Hashable {
    let char: String
    let name: String
    var id: String { char }
}

struct SigmaEmojiGroup: Identifiable {
    let name: String
    let emojis: [SigmaEmoji]
    var id: String { name }
}

@MainActor
final class SigmaEmojiCatalog {
    static let shared = SigmaEmojiCatalog()

    private static let resources = "/Applications/SigmaOS.app/Contents/Frameworks/Model.framework/Versions/A/Resources"
    private static let tones = ["light skin tone", "medium-light skin tone", "medium skin tone", "medium-dark skin tone", "dark skin tone"]
    private static let groupNames = [
        "Smileys & Emotion": "Carinhas e emoções",
        "People & Body": "Pessoas e corpo",
        "Animals & Nature": "Animais e natureza",
        "Food & Drink": "Comida e bebida",
        "Travel & Places": "Viagens e lugares",
        "Activities": "Atividades",
        "Objects": "Objetos",
        "Symbols": "Símbolos",
        "Flags": "Bandeiras",
    ]

    let groups: [SigmaEmojiGroup]
    private let keywords: [String: String]
    /// Emoji base → as cinco variações de tom de pele, na ordem de `tones`.
    private let toneVariants: [String: [String]]

    private init() {
        struct Entry: Decodable { let char: String; let name: String; let group: String }
        let url = URL(fileURLWithPath: Self.resources + "/emojis.json")
        let entries = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []

        var baseByName: [String: String] = [:]
        var variantsByName: [String: [Int: String]] = [:]
        var order: [String] = []
        var byGroup: [String: [SigmaEmoji]] = [:]
        for entry in entries where entry.group != "Component" {
            if let colon = entry.name.range(of: ": "), entry.name.hasSuffix("skin tone") {
                let tone = String(entry.name[colon.upperBound...])
                if let index = Self.tones.firstIndex(of: tone) {
                    variantsByName[String(entry.name[..<colon.lowerBound]), default: [:]][index] = entry.char
                }
                continue
            }
            baseByName[entry.name] = entry.char
            if byGroup[entry.group] == nil { order.append(entry.group) }
            byGroup[entry.group, default: []].append(SigmaEmoji(char: entry.char, name: entry.name))
        }
        groups = order.map { SigmaEmojiGroup(name: Self.groupNames[$0] ?? $0, emojis: byGroup[$0] ?? []) }

        var variants: [String: [String]] = [:]
        for (name, tones) in variantsByName where tones.count == 5 {
            if let base = baseByName[name] { variants[base] = (0..<5).compactMap { tones[$0] } }
        }
        toneVariants = variants

        let keywordsURL = URL(fileURLWithPath: Self.resources + "/emoji_keywords.json")
        keywords = (try? Data(contentsOf: keywordsURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    /// `tone` 0 é o amarelo padrão; 1…5 seguem `tones`.
    func apply(tone: Int, to char: String) -> String {
        guard tone > 0, let variants = toneVariants[char] else { return char }
        return variants[tone - 1]
    }

    func search(_ query: String) -> [SigmaEmoji] {
        let terms = SigmaIconPicker.normalize(query).split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        return groups.flatMap(\.emojis).filter { emoji in
            let haystack = (emoji.name + " " + (keywords[emoji.char] ?? "")).lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }
}

/// Favoritos: os escolhidos por último vêm primeiro.
enum SigmaEmojiFavorites {
    private static let key = "sigma.emojiFavorites"
    private static let seed = ["🛝", "😇", "❤️", "💬", "🧠", "👀", "🐵", "🦄", "🥑", "🧭", "🚀", "🎲", "💻", "📖",
                               "✉️", "📝", "💼", "📅", "📈", "🧬", "✅"]

    static var all: [String] { UserDefaults.standard.stringArray(forKey: key) ?? seed }

    static func use(_ char: String) {
        var list = all.filter { $0 != char }
        list.insert(char, at: 0)
        UserDefaults.standard.set(Array(list.prefix(seed.count)), forKey: key)
    }
}

struct SigmaIconPicker: View {
    @Environment(TabsController.self) private var tabs
    let space: SpaceRecord

    enum Section: String, CaseIterable { case emojis = "Emojis", icons = "Ícones", custom = "Personalizado" }

    @State private var section: Section = .emojis
    @Namespace private var namespace

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            tabBar
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(height: 30)
            switch section {
            case .emojis: SigmaEmojiGrid(space: space)
            case .icons: SigmaSymbolGrid(space: space)
            case .custom: SigmaCustomIconUpload(space: space)
            }
        }
        .padding(10)
        .frame(width: 300, height: 280)
        .background(SigmaPalette.zero, ignoresSafeAreaEdges: .all)
    }

    /// `SectionPicker`: rótulos .headline medium, ativo mandarin, inativos primary 80%; o fundo
    /// mandarin 10% (raio 5) desliza para a aba escolhida.
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Section.allCases, id: \.self) { candidate in
                Button {
                    withAnimation(SigmaMotion.standard) { section = candidate }
                } label: {
                    Text(candidate.rawValue)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(section == candidate ? SigmaPalette.mandarin : Color.primary.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .matchedGeometryEffect(id: candidate, in: namespace, isSource: true)
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(SigmaPalette.mandarin.opacity(0.1))
                .matchedGeometryEffect(id: section, in: namespace, properties: .frame, anchor: .center, isSource: false)
        )
    }

    static func normalize(_ query: String) -> String {
        query.lowercased().trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Peças comuns

/// Campo de busca do `IconPicker`: lupa 12 medium, texto 12, botão de limpar; fundo
/// `zero.highlighted(.low)` com raio 5.
private struct SigmaIconSearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool
    @State private var isHoveringClear = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(query.isEmpty ? 0.5 : 1))
            TextField("Buscar emojis por palavra-chave", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
            Button { query = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(Color.secondary.opacity(
                        SigmaIconPicker.normalize(query).isEmpty ? 0 : (isHoveringClear ? 1 : 0.5)))
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClear = $0 }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(SigmaPalette.zero.sigmaHighlighted(), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .onAppear { focused = true }
    }
}

/// Cabeçalho de seção fixado: .subheadline medium secundário, com uma faixa de 5pt que esmaece
/// o conteúdo que passa por baixo.
private struct SigmaIconSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.secondary)
            .padding(.top, 15)
            .padding(.bottom, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SigmaPalette.zero, ignoresSafeAreaEdges: .all)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [SigmaPalette.zero, SigmaPalette.zero.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 5)
                    .offset(y: 5)
            }
    }
}

/// Grade de 7 colunas em 280pt (40 por coluna), 1pt entre linhas.
private let sigmaIconColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

/// Barra de baixo com o seletor (tom de pele / preenchido) à direita, sobre um gradiente que
/// cobre o fim da grade.
private struct SigmaIconBottomBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(
                LinearGradient(colors: [SigmaPalette.zero.opacity(0), SigmaPalette.zero, SigmaPalette.zero, SigmaPalette.zero],
                               startPoint: .top, endPoint: .bottom)
                    .padding(.top, -10)
            )
    }
}

/// Botão do seletor da barra de baixo: `Standard` mandarin 30% (20% no hover), raio 5, escala 0.97.
private func sigmaSelectorStyle(selected: Bool = false) -> SigmaStandardStyle {
    SigmaStandardStyle(
        color: SigmaPalette.mandarin.opacity(selected ? 1 : 0.3),
        hoveredColor: SigmaPalette.mandarin.opacity(selected ? 1 : 0.2),
        cornerRadius: 5,
        scaleAmount: 0.97,
        horizontalPadding: 10,
        verticalPadding: 2
    )
}

// MARK: - Emojis

private struct SigmaEmojiGrid: View {
    @Environment(TabsController.self) private var tabs
    let space: SpaceRecord

    @State private var query = ""
    @State private var favorites = SigmaEmojiFavorites.all
    @State private var showTones = false
    @AppStorage("sigma.emojiTone") private var tone = 0

    private let catalog = SigmaEmojiCatalog.shared

    var body: some View {
        VStack(spacing: 8) {
            SigmaIconSearchField(query: $query)
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if !SigmaIconPicker.normalize(query).isEmpty {
                        Section { cells(catalog.search(query).map(\.char)) } header: { SigmaIconSectionHeader(title: "Resultados") }
                    } else {
                        Section { cells(favorites) } header: { SigmaIconSectionHeader(title: "Favoritos") }
                        ForEach(catalog.groups) { group in
                            Section { cells(group.emojis.map(\.char)) } header: { SigmaIconSectionHeader(title: group.name) }
                        }
                    }
                }
                .frame(width: 280)
                .padding(.bottom, 24)
            }
            .overlay(alignment: .bottom) {
                SigmaIconBottomBar { toneButton }
            }
        }
    }

    private func cells(_ chars: [String]) -> some View {
        LazyVGrid(columns: sigmaIconColumns, alignment: .center, spacing: 1) {
            ForEach(chars, id: \.self) { char in
                let shown = catalog.apply(tone: tone, to: char)
                Button { pick(shown) } label: {
                    Text(shown)
                        .font(.title)
                        .frame(width: 35, height: 35)
                }
                .buttonStyle(SigmaIconCellStyle(isSelected: space.icon == shown))
            }
        }
    }

    /// `SkinToneSelector`: a mão no tom atual abre um popover com os seis tons.
    private var toneButton: some View {
        Button { showTones.toggle() } label: {
            Text(catalog.apply(tone: tone, to: "✋"))
        }
        .buttonStyle(sigmaSelectorStyle())
        .popover(isPresented: $showTones) {
            HStack {
                ForEach(0..<6, id: \.self) { option in
                    Button {
                        tone = option
                        showTones = false
                    } label: {
                        Text(catalog.apply(tone: option, to: "✋"))
                    }
                    .buttonStyle(sigmaSelectorStyle(selected: option == tone))
                }
            }
            .padding(10)
            .background(SigmaPalette.zero.padding(-60))
        }
    }

    private func pick(_ char: String) {
        tabs.updateSpace(space.id, name: nil, icon: char, accentHex: nil)
        SigmaEmojiFavorites.use(char)
        favorites = SigmaEmojiFavorites.all
    }
}

// MARK: - Ícones

private struct SigmaSymbolGrid: View {
    @Environment(TabsController.self) private var tabs
    let space: SpaceRecord

    @State private var query = ""
    @State private var showFilled = false
    @AppStorage("sigma.symbolsFilled") private var filled = true

    static let symbols = [
        "house", "briefcase", "book", "graduationcap", "pencil", "paintbrush", "hammer",
        "wrench.and.screwdriver", "terminal", "globe", "airplane", "car", "cart", "bag", "creditcard",
        "dollarsign.circle", "chart.bar", "calendar", "clock", "bell", "envelope", "bubble.left",
        "phone", "person", "person.2", "heart", "star", "bolt", "flame", "leaf", "drop", "sun.max",
        "moon", "cloud", "music.note", "headphones", "gamecontroller", "film", "camera", "photo",
        "flag", "tag", "bookmark", "folder", "tray", "archivebox", "lightbulb", "puzzlepiece",
        "cup.and.saucer", "fork.knife", "pawprint", "dumbbell", "figure.run", "stethoscope",
    ]

    private func variant(_ name: String) -> String {
        guard filled else { return name }
        let fill = name + ".fill"
        return NSImage(systemSymbolName: fill, accessibilityDescription: nil) != nil ? fill : name
    }

    var body: some View {
        let needle = SigmaIconPicker.normalize(query)
        let shown = Self.symbols.filter { needle.isEmpty || $0.contains(needle) }.map(variant)
        VStack(spacing: 8) {
            SigmaIconSearchField(query: $query)
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: sigmaIconColumns, alignment: .center, spacing: 1) {
                    ForEach(shown, id: \.self) { symbol in
                        Button {
                            tabs.updateSpace(space.id, name: nil, icon: symbol, accentHex: nil)
                        } label: {
                            Image(systemName: symbol)
                                .font(.title2)
                                .foregroundStyle(Color.primary)
                                .frame(width: 35, height: 35)
                        }
                        .buttonStyle(SigmaIconCellStyle(isSelected: space.icon == symbol))
                    }
                }
                .frame(width: 280)
                .padding(.bottom, 24)
            }
            .overlay(alignment: .bottom) {
                SigmaIconBottomBar { filledButton }
            }
        }
    }

    /// `FilledSelector`: alterna os símbolos entre contorno e preenchido.
    private var filledButton: some View {
        Button { showFilled.toggle() } label: {
            Image(systemName: filled ? "circle.fill" : "circle")
        }
        .buttonStyle(sigmaSelectorStyle())
        .popover(isPresented: $showFilled) {
            HStack {
                ForEach([false, true], id: \.self) { option in
                    Button {
                        filled = option
                        showFilled = false
                    } label: {
                        Image(systemName: option ? "circle.fill" : "circle")
                    }
                    .buttonStyle(sigmaSelectorStyle(selected: option == filled))
                }
            }
            .padding(10)
            .background(SigmaPalette.zero.padding(-60))
        }
    }
}

// MARK: - Personalizado

/// `CustomUploadIcon`: área para soltar ou escolher uma imagem e, embaixo, um campo para colar o
/// link de uma imagem ou site.
private struct SigmaCustomIconUpload: View {
    @Environment(TabsController.self) private var tabs
    let space: SpaceRecord

    @State private var isDropTarget = false
    @State private var link = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 10) {
            Button(action: chooseFile) {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus.fill")
                        .font(.system(size: 40))
                        .frame(width: 55, height: 55)
                    Text("Solte uma imagem aqui ou clique para escolher nos arquivos")
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(isDropTarget ? SigmaPalette.mandarin : Color.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SigmaPalette.mandarin.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(SigmaPalette.mandarin.opacity(isDropTarget ? 1 : 0.5),
                                        style: StrokeStyle(lineWidth: 3, miterLimit: 10, dash: [8, 6], dashPhase: 0))
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onDrop(of: [.image, .png, .gif, .jpeg, .heic, .webP], isTargeted: $isDropTarget) { providers in
                guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) else { return false }
                _ = provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let image = object as? NSImage else { return }
                    Task { @MainActor in apply(image) }
                }
                return true
            }
            .animation(SigmaMotion.standard, value: isDropTarget)

            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.title3)
                    .foregroundStyle(Color.secondary)
                    .frame(width: 14, height: 14)
                TextField("Cole o link de um site ou imagem…", text: $link)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit(loadLink)
                Button(action: loadLink) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(link.isEmpty ? Color.secondary : SigmaPalette.mandarin)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .disabled(link.isEmpty || isLoading)
            }
            .padding(10)
            .padding(.horizontal, 5)
            .background(SigmaPalette.zero.sigmaHighlighted(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .background(SigmaPalette.zero, ignoresSafeAreaEdges: .all)
    }

    private func apply(_ image: NSImage) {
        guard let path = SigmaCustomIcons.store(image) else { return }
        tabs.updateSpace(space.id, name: nil, icon: path, accentHex: nil)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif, .heic, .webP, .image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        apply(image)
    }

    /// Link de imagem vira o ícone direto; link de site usa o ícone grande do site (apple-touch-icon,
    /// depois favicon.ico).
    private func loadLink() {
        let text = link.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let url = URL(string: text.contains("://") ? text : "https://" + text) else { return }
        isLoading = true
        Task {
            var candidates = [url]
            if let host = url.host, let scheme = url.scheme {
                candidates += ["apple-touch-icon.png", "favicon.ico"].compactMap { URL(string: "\(scheme)://\(host)/\($0)") }
            }
            for candidate in candidates {
                if let (data, _) = try? await URLSession.shared.data(from: candidate), let image = NSImage(data: data) {
                    apply(image)
                    link = ""
                    break
                }
            }
            isLoading = false
        }
    }
}
