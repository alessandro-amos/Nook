// Licensed under GPL-3.0. See LICENSE.
//
//  SigmaLocks.swift
//  Sigma
//
//  Páginas travadas do Sigma: ficam no lugar, guardam o endereço travado e não podem ser
//  concluídas nem limpas. Navegar para longe oferece voltar ou atualizar o endereço travado.
//  Fora do TabTree para não mudar o formato que o Nook persiste.
//

import Foundation
import Observation

@MainActor
@Observable
final class SigmaLocks {
    static let shared = SigmaLocks()

    private(set) var lockedURLs: [UUID: URL]

    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let key = "sigma.lockedPages"

    private init() {
        let stored = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        lockedURLs = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            guard let id = UUID(uuidString: key), let url = URL(string: value) else { return nil }
            return (id, url)
        })
    }

    func isLocked(_ id: UUID) -> Bool { lockedURLs[id] != nil }

    func lock(_ id: UUID, at url: URL) {
        lockedURLs[id] = url
        save()
    }

    func unlock(_ id: UUID) {
        lockedURLs[id] = nil
        save()
    }

    /// A página saiu do endereço travado (outro host ou caminho).
    func hasLeft(_ id: UUID, current: URL?) -> Bool {
        guard let locked = lockedURLs[id], let current else { return false }
        return locked.host != current.host || locked.path != current.path
    }

    func forget(_ ids: some Sequence<UUID>) {
        for id in ids { lockedURLs[id] = nil }
        save()
    }

    private func save() {
        defaults.set(Dictionary(uniqueKeysWithValues: lockedURLs.map { ($0.key.uuidString, $0.value.absoluteString) }),
                     forKey: Self.key)
    }
}
