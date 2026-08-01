import Cocoa
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let updateWindowOpenRetryLimit = 20
    static let updateWindowOpenRetryDelay: TimeInterval = 0.15

    var controller: ReaderWindowController!
    var aboutWindow: NSWindow?
    var updateStatusWindow: NSWindow?
    var diagnosticsPanelController: DiagnosticsPanelController?
    var updaterController: SPUStandardUpdaterController?
    var manualUpdateProbeInProgress = false
    var manualUpdateProbeFoundUpdate = false
    var manualUpdateProbeHandledResult = false
    weak var manualUpdateSender: AnyObject?
    var pendingOpenFileURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchPerformanceTracker.shared.mark("didFinishLaunching")
        controller = ReaderWindowController()
        LaunchPerformanceTracker.shared.mark("windowController")
        installMainMenu()
        LaunchPerformanceTracker.shared.mark("menu")
        controller.window?.makeKeyAndOrderFront(nil)
        LaunchPerformanceTracker.shared.mark("windowVisible")
        NSApp.activate(ignoringOtherApps: true)
        loadPendingOpenFilesIfNeeded()
        LaunchPerformanceTracker.shared.finish()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ReaderPerformance.writeBaselineIfRequested(
            launch: LaunchPerformanceTracker.shared.snapshot()
        )
        SpeechPlaybackCoordinator.shared.shutdownForTermination()
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openFileURLWhenReady(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        for filename in filenames {
            openFileURLWhenReady(URL(fileURLWithPath: filename))
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func openFileURLWhenReady(_ url: URL) {
        guard let controller else {
            pendingOpenFileURLs.append(url)
            return
        }
        openFileURL(url, in: controller)
    }

    func loadPendingOpenFilesIfNeeded() {
        guard let url = pendingOpenFileURLs.last else { return }
        pendingOpenFileURLs.removeAll()
        openFileURL(url, in: controller)
    }

    func openFileURL(_ url: URL, in controller: ReaderWindowController) {
        controller.window?.makeKeyAndOrderFront(nil)
        controller.openDocument(url)
    }

    func startUpdaterAfterInitialWindowDisplay() {
        // Leaf Vocabulary is an isolated fork and must never consult Leaf
        // Reader's upstream appcast.
    }

    @discardableResult
    func startUpdaterIfNeeded() -> SPUStandardUpdaterController? {
        nil
    }

}
