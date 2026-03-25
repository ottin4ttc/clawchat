import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var systemColorScheme
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var selectedTab = 0

    private var effectiveColorScheme: ColorScheme {
        isDarkMode ? .dark : systemColorScheme
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("会话", systemImage: "message.fill", value: 0) {
                    NavigationStack {
                        HomeView()
                    }
                }

                Tab("AHA", systemImage: "square.grid.2x2.fill", value: 1) {
                    NavigationStack {
                        DashboardView()
                    }
                }

                Tab("Agents", systemImage: "person.2.fill", value: 2) {
                    NavigationStack {
                        AgentHubView()
                    }
                }
            }
            .tint(appState.currentVisualTheme.accent)
            .background {
                TabBarItemVerticalTuning(
                    targetIndex: 1,
                    imageVerticalOffset: 1,
                    titleVerticalOffset: 1
                )
                .frame(width: 0, height: 0)
            }

            if let moment = appState.selectedMoment {
                MomentDetailOverlay(moment: moment)
                    .zIndex(100)
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(isDarkMode ? .dark : nil)
        .onAppear {
            configureTabBarAppearance()
        }
        .onChange(of: effectiveColorScheme, initial: true) { _, newScheme in
            appState.colorScheme = newScheme
            configureTabBarAppearance()
        }
        .onChange(of: appState.selectedVisualThemeID) {
            configureTabBarAppearance()
        }
    }

    private func configureTabBarAppearance() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithDefaultBackground()
        tabAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        tabAppearance.backgroundColor = UIColor(appState.currentVisualTheme.tabBarFill)
        tabAppearance.shadowColor = UIColor.separator.withAlphaComponent(0.15)

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithDefaultBackground()
        navAppearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        navAppearance.backgroundColor = UIColor(appState.currentVisualTheme.tabBarFill)
        navAppearance.shadowColor = UIColor.separator.withAlphaComponent(0.15)

        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        if #available(iOS 15.0, *) {
            UINavigationBar.appearance().compactScrollEdgeAppearance = navAppearance
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}

private struct TabBarItemVerticalTuning: UIViewControllerRepresentable {
    let targetIndex: Int
    let imageVerticalOffset: CGFloat
    let titleVerticalOffset: CGFloat

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.targetIndex = targetIndex
        uiViewController.imageVerticalOffset = imageVerticalOffset
        uiViewController.titleVerticalOffset = titleVerticalOffset
        uiViewController.applyAdjustments()
    }

    final class Controller: UIViewController {
        var targetIndex = 0
        var imageVerticalOffset: CGFloat = 0
        var titleVerticalOffset: CGFloat = 0

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyAdjustments()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyAdjustments()
        }

        func applyAdjustments() {
            guard let tabBarController = resolvedTabBarController(),
                  let items = tabBarController.tabBar.items,
                  items.indices.contains(targetIndex) else {
                return
            }

            for (index, item) in items.enumerated() {
                if index == targetIndex {
                    item.imageInsets = UIEdgeInsets(
                        top: imageVerticalOffset,
                        left: 0,
                        bottom: -imageVerticalOffset,
                        right: 0
                    )
                    item.titlePositionAdjustment = UIOffset(
                        horizontal: 0,
                        vertical: titleVerticalOffset
                    )
                } else {
                    item.imageInsets = .zero
                    item.titlePositionAdjustment = .zero
                }
            }
        }

        private func resolvedTabBarController() -> UITabBarController? {
            if let tabBarController {
                return tabBarController
            }

            if let parent {
                return Self.findTabBarController(from: parent)
            }

            return Self.findTabBarController(from: view.window?.rootViewController)
        }

        private static func findTabBarController(from controller: UIViewController?) -> UITabBarController? {
            guard let controller else { return nil }
            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }

            for child in controller.children {
                if let tabBarController = findTabBarController(from: child) {
                    return tabBarController
                }
            }

            return findTabBarController(from: controller.presentedViewController)
        }
    }
}
