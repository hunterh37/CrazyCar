import SwiftUI

// MARK: - MainMenuView
//
// Launch window: start/stop the immersive drive, pedals, and live stats.

struct MainMenuView: View {

    @Environment(GameViewModel.self) private var viewModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    @State private var hudTick = 0

    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Text("CRAZY CAR")
                .font(.system(size: 44, weight: .black))
            Text("Sit in the driver's seat. Grab the wheel. Smash everything.")
                .font(.headline)
                .foregroundStyle(.secondary)

            if viewModel.isDriving {
                drivingControls
            } else {
                Button {
                    Task {
                        await openImmersiveSpace(id: "drive")
                        viewModel.isDriving = true
                    }
                } label: {
                    Label("Start Driving", systemImage: "car.fill")
                        .font(.title2.bold())
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(40)
        .onReceive(timer) { _ in hudTick += 1 }
    }

    private var drivingControls: some View {
        VStack(spacing: 20) {
            HStack(spacing: 40) {
                VStack {
                    Text("\(Int(abs(viewModel.speed) * 3.6))")
                        .font(.system(size: 52, weight: .black, design: .monospaced))
                        .contentTransition(.numericText())
                    Text("KM/H").font(.caption.bold()).foregroundStyle(.secondary)
                }
                VStack {
                    Text("\(viewModel.smashCount)")
                        .font(.system(size: 52, weight: .black, design: .monospaced))
                        .foregroundStyle(.orange)
                    Text("SMASHED").font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            .id(hudTick)

            HStack(spacing: 16) {
                pedal("REVERSE", color: .blue, value: -0.6)
                pedal("BRAKE", color: .gray, value: 0)
                pedal("GAS", color: .green, value: 1)
            }

            Button("End Drive", role: .destructive) {
                Task {
                    await dismissImmersiveSpace()
                    viewModel.isDriving = false
                    viewModel.reset()
                }
            }
        }
    }

    private func pedal(_ label: String, color: Color, value: Float) -> some View {
        Button {
            viewModel.throttle = value
        } label: {
            Text(label)
                .font(.title3.bold())
                .frame(width: 110, height: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.throttle == value ? color : color.opacity(0.4))
    }
}
