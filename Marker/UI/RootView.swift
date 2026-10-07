import SwiftUI

struct TaskRoute: Hashable {
    let key: TaskKey
    /// The list the task was opened from, used by the up and down buttons.
    var context: [TaskSummary] = []
    var fetchedAt: Date = .distantPast
    var openComments = false
    var tab: DetailTab?
}

struct StudentRoute: Hashable {
    let projectID: Int
}

enum AppTab: Hashable {
    case inbox, explorer, students, notifications, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                Palette.bg.ignoresSafeArea()
            case .signedOut:
                SignInView()
            case .signedIn:
                MainTabs()
            }
        }
        .animation(.default, value: model.phase)
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .inbox
    @State private var inboxPath = NavigationPath()
    @State private var explorerPath = NavigationPath()
    @State private var studentsPath = NavigationPath()
    @State private var notifPath = NavigationPath()
    private var links = DeepLinks.shared

    var body: some View {
        TabView(selection: $tab) {
            Tab("Inbox", systemImage: "tray", value: AppTab.inbox) {
                NavigationStack(path: $inboxPath) { InboxView().markerDestinations() }
            }
            .badge(model.badgeCount)

            Tab("Explorer", systemImage: "square.grid.2x2", value: AppTab.explorer) {
                NavigationStack(path: $explorerPath) { ExplorerView().markerDestinations() }
            }

            Tab("Students", systemImage: "person.2", value: AppTab.students) {
                NavigationStack(path: $studentsPath) { StudentsView().markerDestinations() }
            }

            Tab("Notifications", systemImage: "bell", value: AppTab.notifications) {
                NavigationStack(path: $notifPath) {
                    NotificationsView(path: $notifPath, openInbox: { tab = .inbox }).markerDestinations()
                }
            }
            .badge(model.unseenCount)

            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(toast: toast).padding(.bottom, 96).allowsHitTesting(false)
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
        .sensoryFeedback(.success, trigger: model.haptic)
        .onChange(of: links.pending) { _, link in
            guard let link else { return }
            links.pending = nil
            tab = .inbox
            inboxPath = NavigationPath()
            inboxPath.append(TaskRoute(key: link.key, openComments: link.comments))
        }
        .onAppear {
            openDemoScreen()
            if let link = links.pending {
                links.pending = nil
                inboxPath.append(TaskRoute(key: link.key, openComments: link.comments))
            }
        }
    }
}

extension MainTabs {
    /// Launch arguments like `-demoTab notifications` open a screen in demo mode.
    private func openDemoScreen() {
        guard model.isDemo else { return }
        let d = UserDefaults.standard
        switch d.string(forKey: "demoTab") {
        case "explorer": tab = .explorer
        case "students": tab = .students
        case "notifications": tab = .notifications
        case "settings": tab = .settings
        default: break
        }
        if let open = d.string(forKey: "demoOpen"), let t = DetailTab(rawValue: open.capitalized) {
            inboxPath.append(TaskRoute(key: TaskKey(projectID: 501, taskDefID: 5), openComments: t == .comments, tab: t))
        }
        if d.string(forKey: "demoStudent") != nil {
            tab = .students
            studentsPath.append(StudentRoute(projectID: 501))
        }
    }
}

extension View {
    func markerDestinations() -> some View {
        navigationDestination(for: TaskRoute.self) { TaskDetailView(route: $0) }
            .navigationDestination(for: StudentRoute.self) { StudentDetailView(projectID: $0.projectID) }
    }
}
