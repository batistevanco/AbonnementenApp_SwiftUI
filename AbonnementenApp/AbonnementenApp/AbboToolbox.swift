import Foundation

// MARK: - Een heel dunne 'store' wrapper
// VERVANG deze door jouw echte opslaglaag.
// - Vul de twee TODO's in om te lezen/schrijven naar jouw data (SharedDefaults / CoreData).
final class SubscriptionStore {
    static let shared = SubscriptionStore()

    // Houd in-memory kopie bij
    private(set) var items: [AbboInfo] = []

    init() {
        self.items = Self.load()
    }

    func refreshFromDisk() {
        self.items = Self.load()
    }

    func save(_ newItems: [AbboInfo]) {
        self.items = newItems
        Self.persist(newItems)
    }

    private static func load() -> [AbboInfo] {
        let abboLijst = AbonnementenDefaults.load()
        return abboLijst.map { AbboInfo(from: $0) }
    }

    private static func persist(_ items: [AbboInfo]) {
        let abboLijst = items.map { toYourModel($0) }
        if let data = try? JSONEncoder().encode(abboLijst) {
            UserDefaults.standard.set(data, forKey: AbonnementenDefaults.key)
        }
    }
}

// MARK: - Helpers
private let cal = Calendar.current

private func roll(_ date: Date, frequency: String) -> Date {
    if frequency == "yearly" { return cal.date(byAdding: .year, value: 1, to: date) ?? date }
    return cal.date(byAdding: .month, value: 1, to: date) ?? date
}

private func monthValue(for price: Double, frequency: String) -> Double {
    frequency == "yearly" ? (price / 12.0) : price
}

// MARK: - Mapping naar/van jouw model
extension AbboInfo {
    init(from abbo: Abonnement) {
        self.id = abbo.id
        self.naam = abbo.naam
        self.prijs = abbo.prijs
        
        // Frequentie: zet om van jouw enum naar de string die de AI verwacht
        switch abbo.frequentie {
        case .jaarlijks:
            self.frequentie = "yearly"
        default:
            self.frequentie = "monthly" // maandelijks, driemaandelijks, wekelijks => reken als maand
        }
        
        self.vervaldatum = abbo.volgendeVervaldatum
        self.categorie = abbo.categorie
    }
}

// Als je later terug wilt mappen naar jouw model, maak hier de omgekeerde mapping.
private func toYourModel(_ a: AbboInfo) -> Abonnement {
    let freq: Frequentie = a.frequentie == "yearly" ? .jaarlijks : .maandelijks
    return Abonnement(
        id: a.id,
        naam: a.naam,
        prijs: a.prijs,
        frequentie: freq,
        volgendeVervaldatum: a.vervaldatum,
        categorie: a.categorie ?? "Other",
        categorieIcon: nil,
        opzegbaar: true,
        notitie: nil
    )
}


// MARK: - AbboToolbox implementatie
final class AbboToolboxImpl: AbboToolbox {

    private var store = SubscriptionStore.shared

    private func load() -> [AbboInfo] {
        store.refreshFromDisk()
        return store.items
    }

    private func save(_ items: [AbboInfo]) {
        store.save(items)
    }

    // LEZEN
    func totaalMaand() -> Double {
        load().reduce(0.0) { $0 + monthValue(for: $1.prijs, frequency: $1.frequentie) }
    }

    func totaalJaar() -> Double {
        load().reduce(0.0) { $0 + ( $1.frequentie == "yearly" ? $1.prijs : $1.prijs * 12.0 ) }
    }

    func aankomendBinnen(dagen: Int) -> [AbboInfo] {
        let now = Date()
        let maxDate = cal.date(byAdding: .day, value: dagen, to: now) ?? now
        return load()
            .filter { $0.vervaldatum <= maxDate }
            .sorted { $0.vervaldatum < $1.vervaldatum }
    }

    func zoekAbbo(naam: String) -> AbboInfo? {
        let needle = naam.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return load().first {
            $0.naam.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .contains(needle)
        }
    }

    // ACTIES
    func markeerBetaald(id: UUID, op datum: Date?) -> Bool {
        var items = load()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return false }

        var abbo = items[idx]
        let ref = datum ?? Date()

        var next = abbo.vervaldatum
        if ref < next {
            // Vroeg betaald: schuif minstens één periode door
            next = roll(next, frequency: abbo.frequentie)
        } else {
            // Te laat of exact op vervaldag: schuif door tot na referentiedatum
            while next <= ref {
                next = roll(next, frequency: abbo.frequentie)
            }
        }
        abbo.vervaldatum = next

        items[idx] = abbo
        save(items)

        // Laat rest van de app weten dat data veranderde
        NotificationCenter.default.post(name: .abboDataDidChange, object: nil)
        return true
    }

    func voegAbboToe(_ nieuw: NieuwAbbo) -> Bool {
        var items = load()

        // Dubbele naam tegenhouden (case-insensitive)
        if items.contains(where: { $0.naam.lowercased() == nieuw.naam.lowercased() }) {
            return false
        }

        let info = AbboInfo(
            id: UUID(),
            naam: nieuw.naam,
            prijs: nieuw.prijs,
            frequentie: nieuw.frequentie, // "monthly" | "yearly"
            vervaldatum: nieuw.eersteVervaldatum,
            categorie: nieuw.categorie
        )

        items.append(info)
        save(items)
        return true
    }

    func bespaarScenario(opzegIDs: [UUID]) -> (perMaand: Double, perJaar: Double) {
        let set = Set(opzegIDs)
        let perMaand = load()
            .filter { set.contains($0.id) }
            .reduce(0.0) { $0 + monthValue(for: $1.prijs, frequency: $1.frequentie) }
        return (perMaand, perMaand * 12.0)
    }
}

extension Notification.Name {
    static let abboDataDidChange = Notification.Name("abboDataDidChange")
}
