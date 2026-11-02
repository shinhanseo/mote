import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor final class InstallerUpdater {
#if canImport(Sparkle)
    private var controller:SPUStandardUpdaterController?
#endif
    func checkAndInstall(){
#if canImport(Sparkle)
        if controller==nil {
            controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:nil,userDriverDelegate:nil)
            controller?.startUpdater()
        }
        controller?.checkForUpdates(nil)
#endif
    }
}
