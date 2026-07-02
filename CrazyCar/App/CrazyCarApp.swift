import SwiftUI
import RealityKit

@main
struct CrazyCarApp: App {

    @State private var viewModel = GameViewModel()
    @State private var immersionStyle: ImmersionStyle = .full

    @MainActor init() {
        registerCrazyCarECS()
    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            MainMenuView()
                .environment(viewModel)
        }
        .defaultSize(width: 560, height: 480)

        ImmersiveSpace(id: "drive") {
            ImmersiveView()
                .environment(viewModel)
        }
        .immersionStyle(selection: $immersionStyle, in: .full)
    }
}
