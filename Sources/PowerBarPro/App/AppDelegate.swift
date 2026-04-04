import Cocoa

/// Application lifecycle manager.
/// Configures the app as a menu-bar-only utility (no Dock icon)
/// and wires up the dependency graph through `DependencyContainer`.
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var container: DependencyContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        container = DependencyContainer()
        container?.menuBarManager.setup()
        container?.powerMonitor.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        container?.powerMonitor.stopMonitoring()
        container?.menuBarManager.tearDown()
    }
}
