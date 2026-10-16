import AppKit

extension NSWorkspace {
    // open(_:) waits on LaunchServices until the browser takes the URL, which can be seconds while it starts up,
    // and hangs the window if it's called from a click. This hands the URL over and returns straight away.
    func openWithoutWaiting(_ url: URL) {
        open(url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}
