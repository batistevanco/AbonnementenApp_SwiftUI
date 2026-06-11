//
//  HomescreenView.swift
//  AbonnementenApp
//
//  Created by Batiste Vancoillie on 30/09/2025.
//

import SwiftUI
import UserNotifications

// MARK: - Notification helpers (local)
private func appDisplayName() -> String {
    if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
        return name
    }
    if let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
        return name
    }
    return "Abonnementen"
}

private func ensureNotificationPermission(_ completion: @escaping (Bool) -> Void) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            completion(true)
        case .denied:
            completion(false)
        case .notDetermined:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                completion(granted)
            }
        @unknown default:
            completion(false)
        }
    }
}

private func preferredTriggerDate(for dueDate: Date, leadDays: Int, hour: Int, minute: Int, calendar: Calendar = .current) -> Date? {
    guard let base = calendar.date(byAdding: .day, value: -leadDays, to: dueDate) else { return nil }
    var comps = calendar.dateComponents([.year, .month, .day], from: base)
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return calendar.date(from: comps)
}

private func cancelRemindersForName(_ name: String) {
    UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
        let ids = pending.map { $0.identifier }.filter { $0.hasPrefix("sub-\(name)-") }
        if !ids.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }
}

private func scheduleSubscriptionReminder(name: String, dueDate: Date, amountText: String? = nil) {
    ensureNotificationPermission { granted in
        guard granted else { return }

        let defaults = UserDefaults.standard
        let leadDays = defaults.object(forKey: "notifLeadDays") as? Int ?? 2
        let hour = defaults.object(forKey: "notifHour") as? Int ?? 9
        let minute = defaults.object(forKey: "notifMinute") as? Int ?? 0

        guard let triggerDate = preferredTriggerDate(for: dueDate, leadDays: leadDays, hour: hour, minute: minute) else { return }

        // Corrigeer als de berekende trigger al in het verleden ligt → plan op nu + 1 minuut
        var finalDate = triggerDate
        let now = Date()
        if finalDate <= now {
            if let adjusted = Calendar.current.date(byAdding: .minute, value: 1, to: now) {
                finalDate = adjusted
            }
        }

        let content = UNMutableNotificationContent()
        content.title = appDisplayName()
        content.subtitle = name
        if let amountText = amountText, !amountText.isEmpty {
            content.body = "Vervalt bijna. Te betalen: \(amountText)."
        } else {
            content.body = "Vervalt bijna."
        }
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: finalDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let identifier = "sub-\(name)-\(Int(dueDate.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // Optioneel: oude pending requests met zelfde naam opruimen
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let toRemove = pending.map{ $0.identifier }.filter{ $0.hasPrefix("sub-\(name)-") }
            if !toRemove.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: toRemove)
            }
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
}


struct HomescreenView: View {
    // MARK: - Types
    enum TimelineItem: Identifiable {
        case dateHeader(Date)
        case subscription(Abonnement)

        var id: String {
            switch self {
            case .dateHeader(let d): return "header-\(d.timeIntervalSince1970)"
            case .subscription(let a): return a.id.uuidString
            }
        }
    }

    enum Periode: String, CaseIterable, Identifiable {
        case maand
        case jaar
        var id: String { rawValue }
        var localized: String {
            switch self {
            case .maand:
                return NSLocalizedString("PERIOD_MONTH", comment: "Segment label for Month")
            case .jaar:
                return NSLocalizedString("PERIOD_YEAR", comment: "Segment label for Year")
            }
        }
    }

    // MARK: - State
    @AppStorage("periodeRaw") private var periodeRaw: String = Periode.maand.rawValue
    @State private var periode: Periode = .maand
    @State private var zoektekst: String = ""
    @State private var isSearchActive: Bool = false
    @AppStorage("abonnementenData") private var abonnementenData: Data = Data()
    @State private var abonnementen: [Abonnement] = []
    @AppStorage("currencyCode") private var currencyCode: String = Locale.current.currency?.identifier ?? "EUR"
    @AppStorage("appTheme") private var appTheme: String = "system"
    @AppStorage("dismissedSwipeHint") private var dismissedSwipeHint: Bool = false
    @AppStorage("dismissedInfoHint") private var dismissedInfoHint: Bool = false
    @AppStorage("upcomingWeeksWindow") private var upcomingWeeksWindow: Int = 1
    @AppStorage("autoMarkPaidOnDue") private var autoMarkPaidOnDue: Bool = false
    // Count abonnementen die aandacht nodig hebben (vervaldatum vandaag of in het verleden)
    private var needsPayCount: Int {
        abonnementen.filter { daysUntil($0.volgendeVervaldatum) <= 0 }.count
    }
    // Aantal items binnen "Binnenkort" met vervaldatum vandaag of eerder
    private var needsPayInUpcomingCount: Int {
        binnenkortAbos.filter { daysUntil($0.volgendeVervaldatum) <= 0 }.count
    }

    // Automatisch op betaaldag markeren (indien ingeschakeld)
    private func autoMarkDueAsPaidIfEnabled() {
        guard autoMarkPaidOnDue else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let dueIDs = abonnementen
            .filter { Calendar.current.startOfDay(for: $0.volgendeVervaldatum) <= today }
            .map { $0.id }
        guard !dueIDs.isEmpty else { return }
        for id in dueIDs {
            if let abo = abonnementen.first(where: { $0.id == id }) {
                markeerBetaald(abo)
            }
        }
    }

    // Add/Edit state
    @State private var isPresentingAddEdit = false
    @State private var editingID: UUID? = nil
    // Delete confirmation state
    @State private var pendingDelete: Abonnement? = nil
    @State private var showDeleteAlert: Bool = false
    @State private var showDuplicateAlert: Bool = false
    @State private var duplicateName: String = ""

    // Draft model used in the Add/Edit sheet
    private struct Draft {
        var naam: String = ""
        var prijs: Double = 0
        var frequentie: Frequentie = .maandelijks
        var volgendeVervaldatum: Date = Date()
        var categorie: String = "Other"
        var categorieIcon: String? = nil
        var opzegbaar: Bool = true
        var notitie: String? = nil
        var zonderVervaldag: Bool = false
        var accountWebsite: String? = nil
    }
    @State private var draft = Draft()
    // Tekstveld voor prijs met placeholder (voorkomt standaard "0")
    @State private var prijsText: String = ""

    // Wordt beheerd in Instellingen en geladen uit UserDefaults
    @AppStorage(CategoriesDefaults.key) private var categoriesRaw: Data = Data()
    @State private var categorieen: [String] = []

    private var isEditing: Bool { editingID != nil }
    
    private var preferredScheme: ColorScheme? {
        switch appTheme {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil // system
        }
    }

    // Binding for icon picker ("__auto__" sentinel = follow category)
    private var iconSelection: Binding<String> {
        Binding<String>(
            get: { draft.categorieIcon ?? "__auto__" },
            set: { draft.categorieIcon = ($0 == "__auto__") ? nil : $0 }
        )
    }

    // MARK: - Persistence helpers (AppStorage <-> in-memory)
    private func loadAbonnementen() {
        // Prefer iCloud data if it's newer than local
        if let cloudData = iCloudSyncManager.shared.newerCloudData(forKey: "abonnementenData"),
           let cloudArr = try? JSONDecoder().decode([Abonnement].self, from: cloudData), !cloudArr.isEmpty {
            abonnementen = cloudArr
            abonnementenData = cloudData
            return
        }
        if let arr = try? JSONDecoder().decode([Abonnement].self, from: abonnementenData), !arr.isEmpty {
            abonnementen = arr
        } else {
            abonnementen = []
        }
    }

    private func saveAbonnementen() {
        if let data = try? JSONEncoder().encode(abonnementen) {
            abonnementenData = data
            iCloudSyncManager.shared.save(data, forKey: "abonnementenData")
        }
    }
    
    private func loadCategorieen() {
        if let arr = try? JSONDecoder().decode([String].self, from: categoriesRaw), !arr.isEmpty {
            categorieen = arr
        } else {
            categorieen = CategoriesDefaults.fallback
        }
    }

    // MARK: - Relative day formatting
    private func daysUntil(_ date: Date, calendar: Calendar = .current) -> Int {
        let startToday = calendar.startOfDay(for: Date())
        let startTarget = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: startToday, to: startTarget).day ?? 0
    }

    private func relativeDayLabel(_ date: Date) -> String {
        let d = daysUntil(date)
        switch d {
        case ..<0:
            if d == -1 {
                return NSLocalizedString("REL_YESTERDAY", comment: "Relative date: yesterday")
            } else {
                return String(format: NSLocalizedString("REL_N_DAYS_AGO", comment: "Relative date: N days ago"), abs(d))
            }
        case 0:
            return NSLocalizedString("REL_TODAY", comment: "Relative date: today")
        case 1:
            return NSLocalizedString("REL_TOMORROW", comment: "Relative date: tomorrow")
        default:
            return String(format: NSLocalizedString("REL_IN_N_DAYS_SHORT", comment: "Relative date: in N days (short)"), d)
        }
    }
    // Label voor "Binnenkort": Vandaag/Morgen/Overmorgen, anders bv. "7 okt"
    private func upcomingDateLabel(_ date: Date) -> String {
        let d = daysUntil(date)
        switch d {
        case ..<0:
            if d == -1 {
                return NSLocalizedString("REL_YESTERDAY", comment: "Relative date: yesterday")
            } else {
                return String(format: NSLocalizedString("REL_N_DAYS_AGO", comment: "Relative date: N days ago"), abs(d))
            }
        case 0:
            return NSLocalizedString("REL_TODAY", comment: "Relative date: today")
        case 1:
            return NSLocalizedString("REL_TOMORROW", comment: "Relative date: tomorrow")
        case 2:
            return NSLocalizedString("REL_DAY_AFTER_TOMORROW", comment: "Relative date: day after tomorrow")
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: Locale.preferredLanguages.first ?? "nl_BE")
            f.setLocalizedDateFormatFromTemplate("d MMM")
            return f.string(from: date)
        }
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            // App-wide tint on this screen
            List {
                if !dismissedSwipeHint { swipeHintSection }
                if !dismissedInfoHint { infoHintSection }
                if needsPayInUpcomingCount > 0 { payHintSection }
                heroSection
                if !binnenkortLeeg {
                    upcomingSection
                }
                volledigeLijstSection
            }
            .simultaneousGesture(TapGesture().onEnded { dismissKeyboard(); if isSearchActive { isSearchActive = false; zoektekst = "" } })
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("AbboBuddy")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { instellingenView() } label: { Image(systemName: "gearshape").foregroundStyle(Theme.primary) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openAdd() } label: {
                        Image(systemName: "plus")
                            .imageScale(.large)
                            .font(.headline)
                            .symbolRenderingMode(.monochrome)
                    }
                }
            }
            .searchable(text: $zoektekst, isPresented: $isSearchActive, placement: .navigationBarDrawer(displayMode: .always), prompt: Text(NSLocalizedString("SEARCH_SUBSCRIPTION_PROMPT", comment: "Search field placeholder")))
            .onAppear {
                periode = Periode(rawValue: periodeRaw) ?? .maand
                loadAbonnementen()
                loadCategorieen()
                autoMarkDueAsPaidIfEnabled()
            }
            .onReceive(NotificationCenter.default.publisher(for: .categoriesUpdated)) { _ in
                loadCategorieen()
            }
            .onReceive(NotificationCenter.default.publisher(for: .abboDataDidChange)) { _ in
                loadAbonnementen()
                autoMarkDueAsPaidIfEnabled()
            }
            .onReceive(NotificationCenter.default.publisher(for: .iCloudDataDidChange)) { _ in
                loadAbonnementen()
            }
#if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                autoMarkDueAsPaidIfEnabled()
            }
#endif
            .onChange(of: categoriesRaw, initial: false) { _, _ in loadCategorieen() }
            .onChange(of: periode, initial: false) { oldValue, newValue in periodeRaw = newValue.rawValue }
            .preferredColorScheme(preferredScheme)
            .tint(Theme.primary)
            .sheet(isPresented: $isPresentingAddEdit) {
                NavigationStack {
                    Form {
                        Section {
                            TextField("Naam", text: $draft.naam, prompt: Text("Naam van abonnement (bv. Netflix)"))

                            Picker("Categorie", selection: $draft.categorie) {
                                ForEach(categorieen, id: \.self) { cat in
                                    Text(cat).tag(cat)
                                }
                            }
                            .pickerStyle(.navigationLink)
                            
                            Picker("Icoon", selection: iconSelection) {
                                HStack { Image(systemName: CategoryIcon.symbol(for: draft.categorie)); Text("Volg categorie (automatisch)") }
                                    .tag("__auto__")
                                ForEach(CategoryIconOptions.options, id: \.symbol) { opt in
                                    HStack { Image(systemName: opt.symbol); Text(opt.name) }
                                        .tag(opt.symbol)
                                }
                            }
                            .pickerStyle(.navigationLink)

                            TextField("Prijs", text: $prijsText, prompt: Text("Prijs (bv. 12,99)"))
                                .keyboardType(.decimalPad)

                            Picker("Frequentie", selection: $draft.frequentie) {
                                Text("Wekelijks").tag(Frequentie.wekelijks)
                                Text("Maandelijks").tag(Frequentie.maandelijks)
                                Text("Driemaandelijks").tag(Frequentie.driemaandelijks)
                                Text("Jaarlijks").tag(Frequentie.jaarlijks)
                            }

                            DatePicker("Volgende vervaldatum", selection: $draft.volgendeVervaldatum, displayedComponents: .date)
                                .onChange(of: draft.volgendeVervaldatum) { _, newValue in
                                    if draft.zonderVervaldag {
                                        draft.volgendeVervaldatum = firstDayOfMonth(for: newValue)
                                    }
                                }

                            Toggle("Zonder vervaldag", isOn: $draft.zonderVervaldag)
                                .onChange(of: draft.zonderVervaldag) { _, enabled in
                                    if enabled {
                                        draft.volgendeVervaldatum = firstDayOfMonth(for: draft.volgendeVervaldatum)
                                    }
                                }
                            Toggle("Opzegbaar", isOn: $draft.opzegbaar)
                            TextField("Notitie (optioneel)", text: $draft.notitie.orEmpty(), prompt: Text("Extra info (bv. plan, kortingscode)…"))
                            TextField("Website / opzeglink", text: $draft.accountWebsite.orEmpty(), prompt: Text("https://..."))
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        } header: {
                            Text("Details").foregroundStyle(Theme.primary)
                        } footer: {
                            Text("Categorie is een lijst die je later in Instellingen kunt beheren. Zet **Zonder vervaldag** aan als je geen specifieke dag wil gebruiken; de app gebruikt dan achterliggend de **1ste dag van de maand**.")
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .navigationTitle(isEditing ? "Bewerk" : "Toevoegen")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annuleer") { isPresentingAddEdit = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Bewaar") { saveDraft() }
                                .disabled(draft.naam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (parseLocalizedDouble(prijsText) ?? -1) < 0)
                        }
                    }
                }
            }
            .alert("Abonnement verwijderen?", isPresented: $showDeleteAlert, presenting: pendingDelete) { abo in
                Button("Verwijder", role: .destructive) {
                    verwijder(abo)
                }
                Button("Annuleer", role: .cancel) { }
            } message: { abo in
                Text("\(abo.naam) wordt verwijderd en kan niet ongedaan gemaakt worden.")
            }
            .alert("Naam bestaat al", isPresented: $showDuplicateAlert) {
                Button("OK", role: .cancel) { duplicateName = "" }
            } message: {
                Text("Er bestaat al een abonnement met de naam \"\(duplicateName)\". Kies een andere naam.")
            }
        }
    }

    // MARK: - Sections
    private var swipeHintSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.point.left.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tip")
                        .font(.headline)
                        .foregroundStyle(Theme.primary)
                    Text("Veeg een abonnement naar links om **Verwijder** of **Bewerk/Betaald** te tonen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("OK") { withAnimation { dismissedSwipeHint = true } }
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }

    private var infoHintSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Wist je dit?")
                        .font(.headline)
                        .foregroundStyle(Theme.primary)
                    Text("Uitleg over hoe de app werkt vind je in **Instellingen → Info** (tandwiel linksboven).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("OK") { withAnimation { dismissedInfoHint = true } }
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
    }
    private var payHintSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .bold))
            Text(needsPayInUpcomingCount == 1 ? "1 abonnement te betalen vandaag of eerder" : "\(needsPayInUpcomingCount) abonnementen te betalen vandaag of eerder")
                .font(.system(size: 11, weight: .bold))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(.white)
        .background(Color.red.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func gradientForSubscription(_ abo: Abonnement) -> LinearGradient {
        let name = abo.naam.lowercased()
        
        let brandColors: [Color]? = {
            if name.contains("netflix") {
                return [Color(red: 0.74, green: 0.05, blue: 0.04), Color(red: 0.09, green: 0.09, blue: 0.09)]
            } else if name.contains("spotify") {
                return [Color(red: 0.12, green: 0.84, blue: 0.38), Color(red: 0.08, green: 0.10, blue: 0.09)]
            } else if name.contains("apple") || name.contains("icloud") || name.contains("arcade") || name.contains("tv+") {
                return [Color(red: 0.55, green: 0.25, blue: 0.85), Color(red: 0.25, green: 0.45, blue: 0.95)]
            } else if name.contains("youtube") || name.contains("google") || name.contains("drive") {
                return [Color(red: 0.90, green: 0.13, blue: 0.13), Color(red: 0.96, green: 0.40, blue: 0.20)]
            } else if name.contains("disney") {
                return [Color(red: 0.05, green: 0.12, blue: 0.31), Color(red: 0.12, green: 0.35, blue: 0.75)]
            } else if name.contains("prime") || name.contains("amazon") {
                return [Color(red: 0.00, green: 0.64, blue: 0.88), Color(red: 0.08, green: 0.15, blue: 0.28)]
            } else if name.contains("chatgpt") || name.contains("openai") {
                return [Color(red: 0.06, green: 0.48, blue: 0.40), Color(red: 0.09, green: 0.10, blue: 0.15)]
            } else if name.contains("github") {
                return [Color(red: 0.15, green: 0.15, blue: 0.18), Color(red: 0.05, green: 0.05, blue: 0.06)]
            } else if name.contains("adobe") || name.contains("creative cloud") {
                return [Color(red: 0.98, green: 0.00, blue: 0.00), Color(red: 0.50, green: 0.00, blue: 0.60)]
            } else if name.contains("microsoft") || name.contains("office") || name.contains("xbox") {
                return [Color(red: 0.00, green: 0.48, blue: 0.85), Color(red: 0.24, green: 0.70, blue: 0.18)]
            } else if name.contains("playstation") || name.contains("psn") || name.contains("plus") {
                return [Color(red: 0.00, green: 0.18, blue: 0.65), Color(red: 0.02, green: 0.45, blue: 0.85)]
            }
            return nil
        }()
        
        if let brandColors = brandColors {
            return LinearGradient(colors: brandColors, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        
        let gradients: [[Color]] = [
            [Color(red: 0.08, green: 0.18, blue: 0.36), Color(red: 0.12, green: 0.45, blue: 0.53)], // Midnight Blue
            [Color(red: 0.31, green: 0.18, blue: 0.54), Color(red: 0.58, green: 0.40, blue: 0.85)], // Purple
            [Color(red: 0.08, green: 0.34, blue: 0.22), Color(red: 0.24, green: 0.65, blue: 0.47)], // Green
            [Color(red: 0.65, green: 0.08, blue: 0.18), Color(red: 0.88, green: 0.29, blue: 0.42)], // Crimson
            [Color(red: 0.95, green: 0.36, blue: 0.46), Color(red: 0.97, green: 0.62, blue: 0.40)], // Coral
            [Color(red: 0.15, green: 0.17, blue: 0.22), Color(red: 0.38, green: 0.42, blue: 0.48)], // Charcoal
            [Color(red: 0.85, green: 0.11, blue: 0.50), Color(red: 0.28, green: 0.12, blue: 0.73)], // Neon Pink
            [Color(red: 0.07, green: 0.45, blue: 0.51), Color(red: 0.18, green: 0.75, blue: 0.56)], // Ocean Teal
            [Color(red: 0.46, green: 0.32, blue: 0.08), Color(red: 0.78, green: 0.64, blue: 0.35)]  // Gold
        ]
        let hash = abs(abo.naam.hashValue)
        let colors = gradients[hash % gradients.count]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                // Left Side: Total Amount details
                VStack(alignment: .leading, spacing: 4) {
                    Text("TOTAAL OVERZICHT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Text(totaalGeformatteerd)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text("\(abonnementen.count) actief")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                        
                        if needsPayCount > 0 {
                            Text("•")
                                .foregroundStyle(.white.opacity(0.5))
                            Text("\(needsPayCount) actie")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Color.red)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.white, in: Capsule())
                        }
                    }
                }
                
                Spacer()
                
                // Right Side: Period Selector & Icon
                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 2) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                periode = .maand
                            }
                        } label: {
                            Text("Maand")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(periode == .maand ? Theme.primary : .white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(periode == .maand ? Color.white : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                periode = .jaar
                            }
                        } label: {
                            Text("Jaar")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(periode == .jaar ? Theme.primary : .white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(periode == .jaar ? Color.white : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(Color.black.opacity(0.15), in: Capsule())
                    
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Theme.primary, Theme.primary.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.primary.opacity(0.25), radius: 6, x: 0, y: 3)
            .padding(.horizontal, 16)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .padding(.vertical, 4)
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Binnenkort te betalen")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(binnenkortAbos.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(binnenkortAbos) { abo in
                        upcomingCard(abo)
                            .contentShape(Rectangle())
                            .onTapGesture { openEdit(abo) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var volledigeLijstSection: some View {
        Section {
            if abonnementen.isEmpty && zoektekst.isEmpty {
                emptyStateView
            } else if gefilterdeAbos.isEmpty {
                HStack {
                    Spacer()
                    Text("Geen resultaten voor '\(zoektekst)'")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            } else {
                ForEach(gefilterdeAbos) { abo in
                    aboCard(abo)
                        .contentShape(Rectangle())
                        .onTapGesture { openEdit(abo) }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = abo
                                showDeleteAlert = true
                            } label: { Label("Verwijder", systemImage: "trash") }
                            Button { openEdit(abo) } label: { Label("Bewerk", systemImage: "pencil") }
                        }
                }
            }
        } header: {
            Text("Alle abonnementen")
        } footer: {
            if !abonnementen.isEmpty {
                Text("Tip: veeg naar links op een kaart om opties te tonen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "creditcard.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.primary.opacity(0.25))
            VStack(spacing: 8) {
                Text("Nog geen abonnementen")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Voeg je eerste abonnement toe\nen krijg inzicht in je kosten.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button { openAdd() } label: {
                Label("Voeg toe", systemImage: "plus")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // MARK: - Rows & Tiles
    private func aboCard(_ abo: Abonnement) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.2))
                            .frame(width: 38, height: 38)
                        Image(systemName: abo.iconSymbol)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(abo.naam)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text(abo.categorie.capitalized)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 6) {
                    Text(frequentieTekst(abo.frequentie))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.18), in: Capsule())
                        
                    if abo.opzegbaar {
                        Text("Opzegbaar")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.3), in: Capsule())
                    }
                }
            }
            
            Spacer(minLength: 8)
            
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VOLGENDE BETALING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(vervaldatumTekst(abo.volgendeVervaldatum))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(bedragTekst(abo))
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    if abo.frequentie != .jaarlijks {
                        Text(currency(abo.jaarBedrag) + "/jr")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(18)
        .background(gradientForSubscription(abo))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
    }
    
    private func upcomingCard(_ abo: Abonnement) -> some View {
        let days = daysUntil(abo.volgendeVervaldatum)
        
        return VStack(alignment: .leading, spacing: 0) {
            // Top Row: Icon and Days badge
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 32, height: 32)
                    Image(systemName: abo.iconSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                Text(days == 0 ? "Vandaag" : (days == 1 ? "Morgen" : "In \(days) dg"))
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(days == 0 ? Color.red.opacity(0.85) : .white.opacity(0.2), in: Capsule())
            }
            
            Spacer(minLength: 12)
            
            // Middle: Name
            Text(abo.naam)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                
            // Subtitle: relative date details or frequency
            Text(frequentieTekst(abo.frequentie).lowercased())
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            
            Spacer(minLength: 16)
            
            // Bottom: Price and Checkmark action
            HStack(alignment: .bottom) {
                Text(bedragTekst(abo))
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                
                Spacer()
                
                Button {
                    markeerBetaald(abo)
                } label: {
                    ZStack {
                        Circle()
                            .fill(.white)
                            .frame(width: 28, height: 28)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(days == 0 ? Color.red : Theme.primary)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 155, height: 145)
        .background(gradientForSubscription(abo))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, x: 0, y: 3)
    }
    
    private func kpiTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            LinearGradient(colors: [Theme.primary.opacity(0.12), Theme.primary.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.primary.opacity(0.15))
        )
    }


    // MARK: - Helpers
    private var gefilterdeAbos: [Abonnement] {
        guard !zoektekst.isEmpty else { return abonnementen.sorted { $0.naam.localizedCaseInsensitiveCompare($1.naam) == .orderedAscending } }
        return abonnementen.filter { $0.naam.localizedCaseInsensitiveContains(zoektekst) || $0.categorie.localizedCaseInsensitiveContains(zoektekst) }
            .sorted { $0.naam.localizedCaseInsensitiveCompare($1.naam) == .orderedAscending }
    }

    private var binnenkortAbos: [Abonnement] {
        let maxDays = upcomingWeeksWindow * 7
        return gefilterdeAbos
            .filter { let d = daysUntil($0.volgendeVervaldatum); return d >= 0 && d <= maxDays }
            .sorted { $0.volgendeVervaldatum < $1.volgendeVervaldatum }
    }

    private var binnenkortLeeg: Bool { binnenkortAbos.isEmpty }

    private var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = []
        var lastDay: Date? = nil
        for abo in binnenkortAbos {
            let day = Calendar.current.startOfDay(for: abo.volgendeVervaldatum)
            if lastDay != day {
                items.append(.dateHeader(day))
                lastDay = day
            }
            items.append(.subscription(abo))
        }
        return items
    }

    private var totaal: Double {
        switch periode {
        case .maand: return gefilterdeAbos.map { $0.maandBedrag }.reduce(0, +)
        case .jaar: return gefilterdeAbos.map { $0.jaarBedrag }.reduce(0, +)
        }
    }

    private var totaalGeformatteerd: String { currency(totaal) }

    // Toon in de rijen altijd het originele bedrag van het abonnement (zoals ingegeven),
    // onafhankelijk van de geselecteerde weergaveperiode. Alleen het KPI "Totaal"
    // gebruikt de periode (maand/jaar) om te herberekenen.
    private func bedragTekst(_ abo: Abonnement) -> String {
        return currency(abo.prijs)
    }

    private func frequentieTekst(_ f: Frequentie) -> String {
        switch f {
        case .wekelijks:
            return NSLocalizedString("FREQ_WEEKLY", comment: "Frequency label: Weekly")
        case .maandelijks:
            return NSLocalizedString("FREQ_MONTHLY", comment: "Frequency label: Monthly")
        case .driemaandelijks:
            return NSLocalizedString("FREQ_QUARTERLY", comment: "Frequency label: Quarterly (every three months)")
        case .jaarlijks:
            return NSLocalizedString("FREQ_YEARLY", comment: "Frequency label: Yearly")
        }
    }


    private func vervaldatumTekst(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Locale.preferredLanguages.first ?? "nl_BE")
        f.dateStyle = .medium
        return f.string(from: date)
    }

    private func firstDayOfMonth(for date: Date) -> Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }

    private func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currencyCode
        f.locale = Locale.current
        if let s = f.string(from: NSNumber(value: value)) {
            // Zorg dat het valutateken en bedrag altijd op één regel blijven
            return s.replacingOccurrences(of: " ", with: "\u{00A0}")
        }
        // Fallback met vaste niet-afbrekende spatie tussen code en bedrag
        return "\(currencyCode)\u{00A0}" + String(format: "%.2f", value)
    }
    
    private func dismissKeyboard() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
    
    // MARK: - Actions (mock)
    private func openAdd() {
        editingID = nil
        draft = Draft()
        prijsText = ""
        isPresentingAddEdit = true
    }

    private func openEdit(_ abo: Abonnement) {
        editingID = abo.id
        draft = Draft(
            naam: abo.naam,
            prijs: abo.prijs,
            frequentie: abo.frequentie,
            volgendeVervaldatum: abo.volgendeVervaldatum,
            categorie: abo.categorie,
            categorieIcon: abo.categorieIcon,
            opzegbaar: abo.opzegbaar,
            notitie: abo.notitie,
            zonderVervaldag: Calendar.current.component(.day, from: abo.volgendeVervaldatum) == 1,
            accountWebsite: abo.accountWebsite
        )
        prijsText = plainNumberString(abo.prijs)
        isPresentingAddEdit = true
    }

    private func saveDraft() {
        if draft.zonderVervaldag {
            draft.volgendeVervaldatum = firstDayOfMonth(for: draft.volgendeVervaldatum)
        }
        let parsedPrijs = parseLocalizedDouble(prijsText) ?? 0
        let newOrUpdated = Abonnement(
            naam: draft.naam.trimmingCharacters(in: .whitespacesAndNewlines),
            prijs: parsedPrijs,
            frequentie: draft.frequentie,
            volgendeVervaldatum: draft.volgendeVervaldatum,
            categorie: draft.categorie.trimmingCharacters(in: .whitespacesAndNewlines),
            categorieIcon: draft.categorieIcon,
            opzegbaar: draft.opzegbaar,
            notitie: draft.notitie,
            accountWebsite: draft.accountWebsite
        )
        // Als de opgegeven vervaldatum in het verleden ligt, schuif door naar de eerstvolgende periode
        let todayStart = Calendar.current.startOfDay(for: Date())
        var adjusted = newOrUpdated
        while Calendar.current.startOfDay(for: adjusted.volgendeVervaldatum) < todayStart {
            adjusted.volgendeVervaldatum = adjusted.volgendeVervaldatumNaHuidige()
        }
        
        // Unieke naam afdwingen (case-insensitive, trim)
        let newNameKey = adjusted.naam.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let conflict = abonnementen.contains {
            $0.naam.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == newNameKey
            && $0.id != editingID // laat zelfde naam toe bij bewerken van hetzelfde item
        }
        if conflict {
            duplicateName = adjusted.naam
            showDuplicateAlert = true
            return
        }

        if let id = editingID, let idx = abonnementen.firstIndex(where: { $0.id == id }) {
            // Cancel old reminders for the original name before overwriting
            cancelRemindersForName(abonnementen[idx].naam)
            // Preserve the original ID when editing
            var updated = adjusted
            // overwrite generated id with original
            let originalID = abonnementen[idx].id
            // rebuild with same id
            updated = Abonnement(
                id: originalID,
                naam: updated.naam,
                prijs: updated.prijs,
                frequentie: updated.frequentie,
                volgendeVervaldatum: updated.volgendeVervaldatum,
                categorie: updated.categorie,
                categorieIcon: updated.categorieIcon,
                opzegbaar: updated.opzegbaar,
                notitie: updated.notitie,
                accountWebsite: updated.accountWebsite
            )
            // replace in place while keeping array order
            abonnementen.remove(at: idx)
            abonnementen.insert(updated, at: idx)
            // NOTE: The synthesized id will change; if you want to preserve UUID, promote `id` to var.
        } else {
            abonnementen.append(adjusted)
            // Defensive: clean up any old reminders for this name
            cancelRemindersForName(adjusted.naam)
        }
        saveAbonnementen()
        // Plan notificatie voor dit abonnement op het ingestelde tijdstip
        let bedragText = currency(parsedPrijs)
        scheduleSubscriptionReminder(name: adjusted.naam, dueDate: adjusted.volgendeVervaldatum, amountText: bedragText)
        isPresentingAddEdit = false
    }

    private func parseLocalizedDouble(_ text: String) -> Double? {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        // Sta zowel komma als punt toe
        let cleaned = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: formatter.decimalSeparator ?? ",").replacingOccurrences(of: ".", with: formatter.decimalSeparator ?? ",")
        return formatter.number(from: cleaned)?.doubleValue
    }

    private func plainNumberString(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale.current
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func verwijder(_ abo: Abonnement) {
        // Remove pending notifications for this subscription name before deleting
        cancelRemindersForName(abo.naam)
        withAnimation { abonnementen.removeAll { $0.id == abo.id } }
        saveAbonnementen()
    }

    private func markeerBetaald(_ abo: Abonnement) {
        // Voor nu simuleren we: schuif de vervaldatum door naar de volgende periode.
        if let idx = abonnementen.firstIndex(where: { $0.id == abo.id }) {
            withAnimation {
                abonnementen[idx].volgendeVervaldatum = abonnementen[idx].volgendeVervaldatumNaHuidige()
                saveAbonnementen()
                // Na doorschuiven van de vervaldatum: nieuwe reminder plannen
                let bedragText = currency(abonnementen[idx].prijs)
                scheduleSubscriptionReminder(name: abonnementen[idx].naam, dueDate: abonnementen[idx].volgendeVervaldatum, amountText: bedragText)
            }
        }
    }
}



private extension Binding where Value == String? {
    /// Provides a non-optional Binding<String> for use in TextField, while writing back nil when empty.
    func orEmpty(_ defaultValue: String = "") -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? defaultValue },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                self.wrappedValue = trimmed.isEmpty ? nil : newValue
            }
        )
    }
}



#Preview {
    HomescreenView()
}

