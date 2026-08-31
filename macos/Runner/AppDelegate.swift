import Cocoa
import FlutterMacOS
import window_ext

@main
class AppDelegate: FlutterAppDelegate {
    
    override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        WindowExtPlugin.instance?.handleShouldTerminate()
        return .terminateCancel
    }

    override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
      return true
    }
    
    override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.setActivationPolicy(.regular)
        if let window = mainFlutterWindow {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.setIsVisible(true)
            window.makeKeyAndOrderFront(self)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}
