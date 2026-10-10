import SwiftUI

@main
struct VolumeBootApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup("VolumeBoot") {
            DashboardView().environmentObject(model)
                .frame(minWidth: 900, minHeight: 580)
        }
    }
}
