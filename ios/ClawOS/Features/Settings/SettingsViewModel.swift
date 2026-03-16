import SwiftUI

@Observable
final class SettingsViewModel {
    var isDarkMode = false
    var skillsWatchEnabled = true
    var selectedModel = "MiniMax-M2.5"
}
