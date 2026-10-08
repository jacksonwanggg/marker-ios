import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var askSignOut = false
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                LabeledContent(model.credentials?.username ?? "Not signed in", value: model.currentRole?.role ?? "Tutor")
                LabeledContent("Signed in until") {
                    Text(model.credentials.map { Fmt.long($0.refreshExpiry) } ?? "Unknown").monospacedDigit()
                }
            } header: {
                Text("Account")
            } footer: {
                Text(model.prefs.notifyExpiry
                     ? "UNSW sign-in lasts seven days. Marker reminds you \(Self.hours(model.prefs.expiryWarnHours)) before it expires."
                     : "UNSW sign-in lasts seven days.")
            }

            Section("Unit") {
                Picker("Unit", selection: Binding(get: { model.unitID ?? -1 },
                                                  set: { id in Task { await model.selectUnit(id) } })) {
                    ForEach(model.unitRoles) { r in Text(model.unitLabel(r.unit)).tag(r.unit.id) }
                }
            }

            Section {
                if notifStatus == .denied {
                    Button("Turn on notifications in iOS Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } else if notifStatus == .notDetermined {
                    Button("Allow notifications") { Task { await Notifier.requestAuthorization(); await checkNotifs() } }
                }
                Toggle("New work to mark", isOn: $model.prefs.notifyWork)
                Toggle("Student comments", isOn: $model.prefs.notifyComments)
                Toggle("Extension requests", isOn: $model.prefs.notifyExtensions)
                Toggle("Sign-in expiry", isOn: $model.prefs.notifyExpiry.animation())
                if model.prefs.notifyExpiry {
                    Picker("Warn me", selection: $model.prefs.expiryWarnHours) {
                        ForEach(Prefs.expiryChoices, id: \.self) { Text("\(Self.hours($0)) before").tag($0) }
                    }
                }
                Toggle(isOn: $model.prefs.dailySummary.animation()) {
                    Text("Daily summary")
                    Text("What's waiting in your inbox")
                }
                if model.prefs.dailySummary {
                    DatePicker("Time", selection: clock($model.prefs.summaryAt), displayedComponents: .hourAndMinute)
                    WeekdayPicker(days: $model.prefs.summaryDays)
                }
                Toggle(isOn: $model.prefs.quietHours.animation()) {
                    Text("Quiet hours")
                    Text("Alerts arrive silently and reminders wait until they end")
                }
                if model.prefs.quietHours {
                    DatePicker("From", selection: clock($model.prefs.quietFrom), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: clock($model.prefs.quietUntil), displayedComponents: .hourAndMinute)
                }
                LabeledContent("Notify me about", value: "My students")
            } header: {
                Text("Notifications")
            } footer: {
                Text("""
                    Formatif doesn't send push notifications, so Marker checks your inbox in the background \
                    when iOS lets it. Alerts can be minutes or hours late. Checks only load the inbox and \
                    never open submissions or comments.
                    """)
            }

            Section {
                ForEach(WaitTier.reminders, id: \.self) { tier in
                    Toggle(tier.settingLabel, isOn: Binding(get: { model.prefs.bumpOn(tier) },
                                                            set: { on in withAnimation { model.prefs.setBump(tier, on) } }))
                    if model.prefs.bumpOn(tier) {
                        Stepper(value: Binding(get: { model.prefs.days(tier) }, set: { model.prefs.setDays(tier, $0) }),
                                in: 1...Prefs.maxBumpDays) {
                            Text("After \(Fmt.days(model.prefs.days(tier)))").monospacedDigit()
                        }
                        .padding(.leading, 12)
                    }
                }
                Picker("Remind me", selection: Binding(get: { model.prefs.bumpAt != nil }, set: { fixed in
                    withAnimation { model.prefs.bumpAt = fixed ? (model.prefs.bumpAt ?? 9 * 60) : nil }
                })) {
                    Text("At the submission time").tag(false)
                    Text("At a set time").tag(true)
                }
                if let at = Binding($model.prefs.bumpAt) {
                    DatePicker("Time", selection: clock(at), displayedComponents: .hourAndMinute)
                }
                Button("Reset to 2, 3, 4 days and a week") {
                    withAnimation { model.prefs.bumpAfter = Prefs.defaultBumpAfter }
                }
                .disabled(model.prefs.bumpAfter == Prefs.defaultBumpAfter)
            } header: {
                Text("Feedback reminders")
            } footer: {
                Text(reminderFooter)
            }

            Section {
                Toggle("Capitalise the first letter", isOn: $model.prefs.capitaliseComments)
            } header: {
                Text("Comments")
            } footer: {
                Text("Turn this off to keep lowercase feedback lowercase.")
            }

            Section("Default filters") {
                Toggle("Hide complete tasks", isOn: $model.prefs.hideComplete)
                Toggle("Hide (M) Moodle tasks", isOn: $model.prefs.hideMoodle)
                Toggle("Oldest submissions first", isOn: $model.prefs.oldestFirst)
            }

            Section("Data") {
                NavigationLink("CSV exports") { CSVExportsView() }
            }

            Section("Appearance") {
                Picker("Theme", selection: $model.prefs.theme) {
                    ForEach(ThemeChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            #if DEBUG
            if !model.isDemo {
                Section("Debug") {
                    LabeledContent("Refresh token", value: model.credentials?.refreshToken == nil ? "missing" : "present")
                    LabeledContent("User id", value: model.myUserID.map(String.init) ?? "unknown")
                    let tutorials = model.myTutorialIDs.compactMap { model.tutorial($0)?.abbreviation }
                    LabeledContent("My tutorials", value: tutorials.joined(separator: ", "))
                    Button("Test token refresh") { Task { await model.testRefresh() } }
                }
            }
            #endif

            Section {
                NavigationLink("About and privacy") { AboutView() }
                Button(model.isDemo ? "Exit demo" : "Sign out", role: .destructive) { askSignOut = true }
            } footer: {
                Text("Marker is an unofficial Formatif client. Your data only goes between this iPhone and Formatif.")
            }
        }
        .navigationTitle("Settings")
        .task { await checkNotifs() }
        .confirmationDialog(model.isDemo ? "Leave the demo?" : "Sign out?", isPresented: $askSignOut, titleVisibility: .visible) {
            Button(model.isDemo ? "Exit demo" : "Sign out", role: .destructive) { Task { await model.signOut() } }
        } message: {
            if !model.isDemo {
                Text("This ends your Formatif session and clears your sign-in and cached data from this iPhone.")
            }
        }
    }

    private var reminderFooter: String {
        let p = model.prefs
        let on = WaitTier.reminders.filter(p.bumpOn).map { Fmt.days(p.days($0)) }
        guard !on.isEmpty else { return "Reminders are off." }
        let at = p.bumpAt.map { ", at the next \(Prefs.clock($0))" } ?? ""
        return "Marker reminds you when a submission has waited \(ListFormatter.localizedString(byJoining: on)) without feedback\(at). "
            + "They're scheduled on this iPhone and stop once you set a status. Inbox tags and the waiting filter use the same days."
    }

    // prefs keep minutes after midnight, DatePicker wants a Date
    private func clock(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: {
            let m = minutes.wrappedValue
            return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
    }

    private static func hours(_ h: Int) -> String {
        if h % 24 == 0 { return h == 24 ? "1 day" : "\(h / 24) days" }
        return h == 1 ? "1 hour" : "\(h) hours"
    }

    private func checkNotifs() async {
        notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

struct CSVExportsView: View {
    @Environment(AppModel.self) private var model
    @State private var busy: CSVReport?
    @State private var share: ShareItem?

    var body: some View {
        List(CSVReport.allCases) { r in
            Button {
                Task { await download(r) }
            } label: {
                HStack {
                    Text(r.label).foregroundStyle(Palette.fg)
                    Spacer()
                    if busy == r { ProgressView() } else { Text("CSV").font(.footnote).foregroundStyle(Palette.fg2) }
                }
                .frame(minHeight: 44)
            }
            .disabled(busy != nil)
        }
        .navigationTitle("CSV exports")
        .sheet(item: $share) { ShareSheet(items: [$0.url]).presentationDetents([.medium, .large]) }
    }

    private func download(_ r: CSVReport) async {
        guard let unitID = model.unitID else { return }
        busy = r
        defer { busy = nil }
        do {
            let file = try await model.backend.csv(unitID: unitID, report: r)
            let code = (model.unit?.code ?? "unit").replacingOccurrences(of: "/", with: "-")
            let name = file.filename.hasSuffix(".csv") ? file.filename : "\(code)-\(r.rawValue).csv"
            if let url = TempFiles.write(file.data, name: name) { share = ShareItem(url: url) }
        } catch {
            model.show(model.message(error), error: true)
        }
    }
}

struct AboutView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                MarkerLogo(size: 56)
                Text("Marker").font(.title.bold())
                Text("Version \(version)").font(.subheadline).foregroundStyle(Palette.fg2)
                Text("Marker is an unofficial tutor client for Formatif, UNSW CSE's fork of Doubtfire. It isn't made or endorsed by UNSW.")
                Text("Privacy").font(.headline)
                Text("""
                    You sign in on Microsoft's own page, so Marker never sees your password. Apart from that page, \
                    Marker only talks to formatif.cse.unsw.edu.au. Your session token stays in the iOS Keychain, and \
                    your inbox and student list are cached on this iPhone so the app opens straight away, even offline. \
                    Signing out deletes all of it. There's no Marker server and no analytics or tracking.
                    """)
                Text("Side effects in Formatif").font(.headline)
                Text("""
                    Opening a comment thread marks it as read. Opening a submission shows up as “submission opened” \
                    in Formatif's marking analytics. Status changes and comments go to Formatif as soon as you tap them.
                    """)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("About and privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WeekdayPicker: View {
    @Binding var days: [Int]

    var body: some View {
        let cal = Calendar.current
        let order = [2, 3, 4, 5, 6, 7, 1] // monday first
        VStack(alignment: .leading, spacing: 8) {
            Text("Days")
            HStack(spacing: 6) {
                ForEach(order, id: \.self) { d in
                    let on = days.contains(d)
                    Button {
                        if on { days.removeAll { $0 == d } } else { days.append(d); days.sort() }
                    } label: {
                        Text(cal.veryShortWeekdaySymbols[d - 1])
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .foregroundStyle(on ? Palette.accOn : Palette.fg)
                            .background(on ? Palette.acc : Palette.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cal.weekdaySymbols[d - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            if days.isEmpty {
                Text("Pick at least one day to get a summary.").font(.footnote).foregroundStyle(Palette.fg2)
            }
        }
        .padding(.vertical, 4)
    }
}
