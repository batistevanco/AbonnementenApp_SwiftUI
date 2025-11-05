import SwiftUI
import Foundation
import Combine

private let sharedDefaults = UserDefaults(
    suiteName: "group.be.vancoilliestudio.abbobuddy.shared"
)

// MARK: - Protocol: Koppeling met jouw data-laag
// Implementeer deze in je bestaande data/service (bv. via SharedDefaults/CoreData).
protocol AbboToolbox {
    // LEZEN
    func totaalMaand() -> Double
    func totaalJaar() -> Double
    func aankomendBinnen(dagen: Int) -> [AbboInfo] // bv. binnen 7 dagen
    func zoekAbbo(naam: String) -> AbboInfo?

    // ACTIES
    @discardableResult func markeerBetaald(id: UUID, op datum: Date?) -> Bool
    @discardableResult func voegAbboToe(_ nieuw: NieuwAbbo) -> Bool

    // ANALYSE
    func bespaarScenario(opzegIDs: [UUID]) -> (perMaand: Double, perJaar: Double)
}

// Minimale struct zodat de chat kan praten met jouw entiteiten.
struct AbboInfo: Identifiable {
    let id: UUID
    let naam: String
    let prijs: Double
    /// "monthly" of "yearly"
    let frequentie: String
    var vervaldatum: Date
    let categorie: String?
}

struct NieuwAbbo {
    let naam: String
    let prijs: Double
    /// "monthly" of "yearly"
    let frequentie: String
    let eersteVervaldatum: Date
    let categorie: String?
}

// MARK: - ViewModel

@MainActor
final class AIChatViewModel: ObservableObject {

    // Eenvoudige, on-device "AI" via intent parsing
    enum Role { case user, bot }
    struct Line: Identifiable {
        let id: UUID
        let role: Role
        let text: String
        init(id: UUID = UUID(), role: Role, text: String) {
            self.id = id
            self.role = role
            self.text = text
        }
    }

    @Published var transcript: [Line] = []
    @Published var input: String = ""
    @Published private var typingID: UUID? = nil

    private let tools: AbboToolbox
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // Localized string helper
    private func tr(_ key: String, _ args: CVarArg...) -> String {
        let fmt = NSLocalizedString(key, comment: "")
        return String(format: fmt, arguments: args)
    }

    // Valuta vanuit de View (AppStorage) doorgeven
    var currencyProvider: (() -> String)?

    // Eenvoudige taalherkenning (NL/EN)
    enum Lang { case nl, en }
    private func detectLanguage(from text: String) -> Lang {
        let t = text.lowercased()
        let nlHits = ["deze","maand","jaar","binnenkort","vervalt","markeer","betaald","voeg","opzeg"].filter { t.contains($0) }.count
        let enHits = ["total","month","year","upcoming","due","mark","paid","add","cancel"].filter { t.contains($0) }.count
        return enHits > nlHits ? .en : .nl
    }

    init(tools: AbboToolbox, currencyProvider: (() -> String)? = nil) {
        self.tools = tools
        self.currencyProvider = currencyProvider
        transcript.append(.init(role: .bot, text: tr("GREETING_TEXT")))
    }

    // Publieke entry om te versturen
    func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        transcript.append(.init(role: .user, text: text))
        input = ""
        showTyping()
        // Typing dots zichtbaar houden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            self.handle(text)
        }
    }

    // MARK: Intent parsing (NL/EN, tolerant voor variaties)
    private func handle(_ text: String) {
        let lower = text.lowercased()
        let lang = detectLanguage(from: text)

        // 1) Totaalvragen maand
        if (lower.contains("totaal") && (lower.contains("maand") || lower.contains("per maand"))) ||
           (lower.contains("total") && (lower.contains("month") || lower.contains("per month"))) {
            let v = tools.totaalMaand()
            bot(tr("TOTAL_MONTH", formatMoney(v)))
            return
        }
        // 1b) Totaalvragen jaar
        if (lower.contains("totaal") && (lower.contains("jaar") || lower.contains("per jaar") || lower.contains("jaarlijks"))) ||
           (lower.contains("total") && (lower.contains("year") || lower.contains("per year") || lower.contains("yearly"))) {
            let v = tools.totaalJaar()
            bot(tr("TOTAL_YEAR", formatMoney(v)))
            return
        }

        // 2) Aankomend / vervalt binnenkort / upcoming / due
        if lower.contains("binnenkort") || lower.contains("vervalt") || lower.contains("aankomend") || lower.contains("upcoming") || lower.contains("due") {
            let binnen = matchInt(in: lower, forAnyOf: ["binnen ", "in "]) ?? 7
            let lijst = tools.aankomendBinnen(dagen: binnen)
            if lijst.isEmpty { bot(tr("DUE_NONE", binnen)); return }
            let lines = lijst.prefix(10).map { "• \($0.naam) – \(dateFormatter.string(from: $0.vervaldatum)) – \(formatMoney(pricePerMaand($0))) /m" }
            let header = tr("DUE_LIST_HEADER", binnen)
            bot(header + lines.joined(separator: "\n"))
            return
        }

        // 3) Markeer betaald / mark as paid
        if (lower.contains("markeer") && lower.contains("betaald")) || lower.contains("gemarkeerd als betaald") || (lower.contains("mark") && lower.contains("paid")) {
            let naam = extractBetween(lower, start: lang == .en ? "mark" : "markeer", end: lang == .en ? "as paid" : "als betaald")?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let naam, let abbo = tools.zoekAbbo(naam: naam), tools.markeerBetaald(id: abbo.id, op: extractDate(from: lower)) {
                if let d = extractDate(from: lower) {
                    bot(tr("MARKED_PAID_WITH_DATE", abbo.naam, dateFormatter.string(from: d)))
                } else {
                    bot(tr("MARKED_PAID", abbo.naam))
                }
            } else {
                bot(tr("MARKED_PAID_FAIL"))
            }
            return
        }

        // 4) Toevoegen / add
        if (lower.contains("voeg") && (lower.contains("toe") || lower.contains("toevoegen"))) || lower.contains("add ") {
            let fallback = (lang == .en ? "New subscription" : "Nieuw abonnement")
            var naam = extractNameForAdd(from: text) ?? fallback
            if naam.caseInsensitiveCompare("voeg") == .orderedSame || naam.caseInsensitiveCompare("add") == .orderedSame {
                naam = fallback
            }
            let prijs = extractPrice(from: lower) ?? 0.0
            let freq = (lower.contains("jaar") || lower.contains("jaarlijks") || lower.contains("year")) ? "yearly" : "monthly"
            let datum = extractDate(from: lower) ?? Date()
            let cat = extractCategory(from: lower)

            let ok = tools.voegAbboToe(.init(naam: naam, prijs: prijs, frequentie: freq, eersteVervaldatum: datum, categorie: cat))
            let freqText = (freq == "monthly") ? tr("PER_MONTH") : tr("PER_YEAR")
            if ok {
                if let cat = cat, !cat.isEmpty {
                    bot(tr("ADDED_WITH_CAT", naam, formatMoney(prijs), freqText, dateFormatter.string(from: datum), cat))
                } else {
                    bot(tr("ADDED", naam, formatMoney(prijs), freqText, dateFormatter.string(from: datum)))
                }
            } else {
                bot(tr("ADD_FAIL"))
            }
            return
        }

        // 5) Bespaar-scenario / savings
        if lower.contains("wat bespaar") || lower.contains("bespaar ik") || lower.contains("besparing") || lower.contains("save if") || lower.contains("how much save") {
            let namen = extractNamesList(from: lower)
            let ids = namen.compactMap { tools.zoekAbbo(naam: $0)?.id }
            if ids.isEmpty { bot(tr("SAVINGS_PROMPT")); return }
            let s = tools.bespaarScenario(opzegIDs: ids)
            bot(tr("SAVINGS_RESULT", formatMoney(s.perMaand), formatMoney(s.perJaar)))
            return
        }

        // Default: hulp / help
        bot(tr("EXAMPLES_TEXT"))
    }

    // MARK: Helpers

    private func bot(_ text: String) {
        // verwijder typing-indicator indien aanwezig
        if let tid = typingID, let idx = transcript.firstIndex(where: { $0.id == tid }) {
            transcript.remove(at: idx)
            typingID = nil
        }
        transcript.append(.init(role: .bot, text: text))
    }

    private func showTyping() {
        let tid = UUID()
        typingID = tid
        transcript.append(.init(id: tid, role: .bot, text: "…"))
    }

    private func formatMoney(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyProvider?() ?? Locale.current.currency?.identifier ?? "EUR"
        f.maximumFractionDigits = 2
        return f.string(from: v as NSNumber) ?? "€\(String(format: "%.2f", v))"
    }

    private func pricePerMaand(_ a: AbboInfo) -> Double {
        a.frequentie == "yearly" ? (a.prijs / 12.0) : a.prijs
    }

    private func matchInt(in text: String, forAnyOf prefixes: [String]) -> Int? {
        for p in prefixes {
            if let r = text.range(of: p), let num = Int(text[r.upperBound...].prefix { $0.isNumber }) {
                return num
            }
        }
        return nil
    }

    private func extractBetween(_ text: String, start: String, end: String) -> String? {
        guard let sr = text.range(of: start) else { return nil }
        guard let er = text.range(of: end, range: sr.upperBound..<text.endIndex) else { return nil }
        return String(text[sr.upperBound..<er.lowerBound])
    }

    private func extractPrice(from text: String) -> Double? {
        // zoekt “€9,99” of “9.99” etc.
        let pattern = #"(?:(?:€|\b)\s?)(\d+(?:[.,]\d{1,2})?)"#
        if let rx = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let m = rx.firstMatch(in: text, range: range), m.numberOfRanges > 1,
               let r = Range(m.range(at: 1), in: text) {
                let raw = text[r].replacingOccurrences(of: ",", with: ".")
                return Double(raw)
            }
        }
        return nil
    }

        private func extractDate(from text: String) -> Date? {
            // simpele herkenning: "op 1 november", "1/11/2025", "01-11-2025", "morgen", "vandaag"
            let lower = text.lowercased()
            let now = Date()
            let cal = Calendar.current

            if lower.contains("vandaag") { return now }
            if lower.contains("morgen") { return cal.date(byAdding: .day, value: 1, to: now) }

            // dd/mm/yyyy of dd-mm-yyyy (jaar optioneel)
            let pattern = #"\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b"#
            if let rx = try? NSRegularExpression(pattern: pattern) {
                let r = NSRange(lower.startIndex..<lower.endIndex, in: lower)
                if let m = rx.firstMatch(in: lower, range: r), m.numberOfRanges >= 3,
                   let dR = Range(m.range(at: 1), in: lower),
                   let mR = Range(m.range(at: 2), in: lower) {
                    let day = Int(lower[dR]) ?? 1
                    let month = Int(lower[mR]) ?? 1
                    var year = cal.component(.year, from: now)
                    if m.numberOfRanges > 3, let yR = Range(m.range(at: 3), in: lower) {
                        let yy = Int(lower[yR]) ?? year
                        year = yy < 100 ? 2000 + yy : yy
                    }
                    var comp = DateComponents()
                    comp.day = day; comp.month = month; comp.year = year
                    return cal.date(from: comp)
                }
            }

            // natuurlijke taal: "op 1 november", "1 november"
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
                let ns = text as NSString
                let range = NSRange(location: 0, length: ns.length)
                let matches = detector.matches(in: text, options: [], range: range)
                if let m = matches.first { return m.date }
            }
            return nil
        }
    }

    private func extractCategory(from text: String) -> String? {
        let lower = text.lowercased()
        guard let r = lower.range(of: "categorie") else { return nil }
        let after = text[r.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return after.isEmpty ? nil : after
    }

    private func extractNamesList(from text: String) -> [String] {
        // Zoek stuk na "als ik"
        let lower = text.lowercased()
        guard let rangeIk = lower.range(of: "als ik") else { return [] }
        var after = lower[rangeIk.upperBound...]
            .replacingOccurrences(of: "opzeggen", with: "")
            .replacingOccurrences(of: "opzeg", with: "")
        // vervang verbindingswoorden door komma en splits
        after = after.replacingOccurrences(of: " en ", with: ",")
                     .replacingOccurrences(of: " of ", with: ",")
        return after.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func extractNameForAdd(from text: String) -> String? {
        var t = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        // 1) Als de naam tussen quotes staat, die prefereren (", ', ‘ ’)
        func between(_ start: Character, _ end: Character, in s: String) -> String? {
            guard let sIdx = s.firstIndex(of: start) else { return nil }
            let afterStart = s.index(after: sIdx)
            guard let eIdx = s[afterStart...].firstIndex(of: end) else { return nil }
            let sub = String(s[afterStart..<eIdx]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            return sub.isEmpty ? nil : sub
        }
        if let q = between("\"", "\"", in: t)
            ?? between("'", "'", in: t)
            ?? between("‘", "’", in: t) {
            return q
        }

        // 2) Leidend werkwoord verwijderen (voeg/add)
        if let r = t.range(of: "(?i)^(voeg|add)\\s+", options: .regularExpression) {
            t = String(t[r.upperBound...])
        }

        // 3) Tokens verzamelen tot we een stop-token raken
        let stopWords: Set<String> = [
            "€", "eur", "euro", "per",
            "maandelijks", "monthly", "jaarlijks", "yearly",
            "toe", "on", "op", "category", "categorie",
            "monthly,", "yearly,", "maandelijks,", "jaarlijks,"
        ]

        var parts: [String] = []
        for raw in t.split(separator: " ") {
            let w = String(raw)
            let lw = w.lowercased()
            if lw.first?.isNumber == true { break }
            if stopWords.contains(lw) { break }
            if lw.hasPrefix("€") { break }
            parts.append(w)
        }

        let name = parts.joined(separator: " ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

// MARK: - View

struct AIChatView: View {
    @StateObject private var vm: AIChatViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showInfoSheet = false
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "EUR"

    // Injecteer jouw implementatie van AbboToolbox hier
    init(toolbox: AbboToolbox) {
        _vm = StateObject(wrappedValue: AIChatViewModel(tools: toolbox, currencyProvider: {
            // eerst proberen uit gedeelde app group te lezen
            if let code = sharedDefaults?.string(forKey: "currencyCode") {
                return code
            }
            // fallback naar standaard
            return UserDefaults.standard.string(forKey: "currencyCode") ?? Locale.current.currency?.identifier ?? "EUR"
        }))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [
                    Color(uiColor: .systemGroupedBackground),
                    Color(uiColor: .secondarySystemGroupedBackground)
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(vm.transcript) { line in
                                ChatBubble(text: line.text, isBot: line.role == .bot)
                                    .id(line.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 90) // ruimte voor inputbar
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: vm.transcript.count) { _, _ in
                        if let last = vm.transcript.last?.id {
                            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
            }
            // Removed custom .safeAreaInset(edge: .top) header to avoid obscuring the system navigation bar.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    InputBar(text: $vm.input, onSend: vm.send)
                }
                .background(
                    Rectangle()
                        .fill(.thinMaterial)
                        // alleen BOVEN afgerond
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
                        // subtiele rand
                        .overlay(
                            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                                .strokeBorder(Color.black.opacity(0.06))
                        )
                        // zachte schaduw aan de bovenrand
                        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: -2)
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(.thinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("AbboBuddy AI").font(.title3).bold()
                }
                ToolbarItem(placement: .topBarLeading) {
                    RoundIconButton(systemName: "info.circle") { showInfoSheet = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    RoundIconButton(systemName: "keyboard.chevron.compact.down") { hideKeyboard() }
                }
            }
            .sheet(isPresented: $showInfoSheet) {
                InfoSheet()
            }
        }
    }
}
// MARK: - RoundIconButton
fileprivate struct RoundIconButton: View {
    let systemName: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Theme.primary)
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

// MARK: - CopyRow (copyable command row)
fileprivate struct CopyRow: View {
    let icon: String
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(text)
                .textSelection(.enabled) // iOS 15+: long-press to select/copy
        }
        .contextMenu {
            Button(action: { copy(text) }) {
                Label("Kopieer", systemImage: "doc.on.doc")
            }
        }
        .overlay(alignment: .trailing) {
            if copied {
                Text("Gekopieerd!")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
    }

    private func copy(_ s: String) {
#if canImport(UIKit)
        UIPasteboard.general.string = s
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
        withAnimation(.easeInOut(duration: 0.6)) {
            copied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.3)) { copied = false }
        }
    }
}

private struct InfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Alles wat je met AbboBuddy AI kunt doen")
                        .font(.title2).bold()
                    Text("U kan de commando's kopieren en plakken in de chat.")
                        .font(.title3)

                    // MARK: – Totale bedragen
                    Group {
                        Text(NSLocalizedString("AI_TOTALS_TITLE", comment: "Section title: totals"))
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            CopyRow(icon: "sum", text: NSLocalizedString("AI_TOTALS_CMD_THIS_MONTH", comment: "Command: total this month"))
                            CopyRow(icon: "sum", text: NSLocalizedString("AI_TOTALS_CMD_PER_YEAR", comment: "Command: total per year"))
                        }
                    }

                    Divider()

                    // MARK: – Vervaldagen
                    Group {
                        Text(NSLocalizedString("AI_DUE_TITLE", comment: "Section title: due dates"))
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            CopyRow(icon: "calendar", text: NSLocalizedString("AI_DUE_CMD_UPCOMING_DEFAULT", comment: "Command: what is due soon (default 7 days)"))
                            CopyRow(icon: "calendar", text: NSLocalizedString("AI_DUE_CMD_UPCOMING_14", comment: "Command: what is due within 14 days"))
                            CopyRow(icon: "calendar", text: NSLocalizedString("AI_DUE_CMD_UPCOMING_3", comment: "Command: upcoming in 3 days"))
                        }
                    }

                    Divider()

                    // MARK: – Markeer als betaald
                    Group {
                        Text(NSLocalizedString("AI_MARKPAID_TITLE", comment: "Section title: mark as paid"))
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            CopyRow(icon: "checkmark.circle", text: NSLocalizedString("AI_MARKPAID_CMD_SIMPLE", comment: "Command: mark Netflix as paid"))
                            CopyRow(icon: "checkmark.circle", text: NSLocalizedString("AI_MARKPAID_CMD_WITH_DATE", comment: "Command: mark Netflix as paid on date"))
                        }
                        Text(NSLocalizedString("AI_MARKPAID_TIP", comment: "Tip text: after marking paid, due date advances"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // MARK: – Abonnement toevoegen
                    Group {
                        Text(NSLocalizedString("AI_ADD_TITLE", comment: "Section title: add subscription"))
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            CopyRow(icon: "plus.circle", text: NSLocalizedString("AI_ADD_CMD_SPOTIFY", comment: "Command: add Spotify monthly with date"))
                            CopyRow(icon: "plus.circle", text: NSLocalizedString("AI_ADD_CMD_ICLOUD", comment: "Command: add iCloud yearly with date"))
                            CopyRow(icon: "plus.circle", text: NSLocalizedString("AI_ADD_CMD_AUDIBLE_CAT", comment: "Command: add Audible monthly with category"))
                        }
                    }

                    Divider()

                    // MARK: – Bespaar-scenario
                    Group {
                        Text(NSLocalizedString("AI_SAVINGS_TITLE", comment: "Section title: savings scenario"))
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            CopyRow(icon: "chart.line.uptrend.xyaxis", text: NSLocalizedString("AI_SAVINGS_CMD_EXAMPLE", comment: "Command: savings if cancel Netflix and Disney+"))
                        }
                        Text(NSLocalizedString("AI_SAVINGS_FOOTNOTE", comment: "Footnote: calculates per month and per year estimate"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Group {
                        Text("Privacy Policy")
                            .font(.headline)

                        Button {
                            if let url = URL(string: "https://www.vancoillieithulp.be/privacyPolicyAbboBuddy.html") {
                                openURL(url)
                            }
                        } label: {
                            Label("Bekijk privacy policy", systemImage: "lock.doc")
                                .font(.body)
                        }
                        .buttonStyle(.bordered)
                        .tint(.accentColor)
                    }

                }
                .padding(20)
            }
            .navigationTitle("Over AbboBuddy AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Gereed") { dismiss() }
                }
            }
        }
    }
}

private struct TypingDots: View {
    @State private var animate = false
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .frame(width: 6, height: 6)
                    .scaleEffect(animate ? 1.0 : 0.4)
                    .opacity(animate ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                        value: animate
                    )
            }
        }
        .foregroundStyle(.secondary)
        .onAppear { animate = true }
    }
}

private struct ChatBubble: View {
    let text: String
    let isBot: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isBot {
                avatar
                bubble
                Spacer(minLength: 24)
            } else {
                Spacer(minLength: 24)
                bubble
                avatar
            }
        }
    }

    private var bubble: some View {
        Group {
            if isBot {
                Group {
                    if text == "…" {
                        TypingDots()
                            .padding(12)
                    } else {
                        Text(text)
                            .padding(14)
                    }
                }
                .background(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.15))
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Text(text)
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.gradient)
                    )
            }
        }
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .transition(.move(edge: isBot ? .leading : .trailing).combined(with: .opacity))
        .contextMenu {
            Button(action: { copyToPasteboard(text) }) {
                Label("Kopieer", systemImage: "doc.on.doc")
            }
        }
    }

    private var avatar: some View {
        Group {
            if isBot {
                Text("🤖")
            } else {
                Image(systemName: "person.crop.circle")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.primary)
            }
        }
        .font(.system(size: 14))
        .frame(width: 28, height: 28)
        .background(Circle().fill(isBot ? Color.gray.opacity(0.2) : Color.accentColor))
        .foregroundStyle(isBot ? Color.primary : Color.white)
    }
}


private struct InputBar: View {
    @Binding var text: String
    var onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("Stel een vraag of geef een opdracht…", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
            )

            Button(action: {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
#if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
                onSend()
            }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .padding(12)
                    .background(Circle().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

fileprivate func copyToPasteboard(_ s: String) {
#if canImport(UIKit)
    UIPasteboard.general.string = s
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
}
// MARK: - Utility (kleine helper voor regex in extractDate)
private extension Int {
    func numberOfMatches(of pattern: String, in text: String) -> Int {
        (try? NSRegularExpression(pattern: pattern))?
            .numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
    }
}

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif


