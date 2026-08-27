#if os(iOS)
import SwiftUI

/// "Learn to see it" — a guided trainer for the users who never manage to see
/// the illusion, and the app's answer to a help sheet nobody reads.
struct LearnToSeeItView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("trainer.completedRound") private var completedRound = 0
    @State private var step: TrainerStep = .armsLength
    @State private var round = TrainerRound(index: 0)
    @State private var screen: CGSize = .zero
    @StateObject private var stereogramVM = StereogramViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            arc
            copy
            Spacer(minLength: DWSpace.l)
            buttons
        }
        .padding(.horizontal, DWSpace.xl)
        .padding(.top, DWSpace.l)
        .padding(.bottom, DWSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DWColor.ground)
        // Measured outside the safe area, because the main canvas the trainer
        // has to match runs to the edges of the screen.
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { screen = proxy.size }
                    .onChange(of: proxy.size) { _, size in screen = size }
            }
            .ignoresSafeArea()
        }
        .task(id: RenderKey(round: round.index, screen: screen)) { await render() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DWSpace.m) {
            Text("trainer.header").dwMicroLabel()
            Spacer(minLength: 0)
            Text("trainer.step \(step.rawValue) \(TrainerStep.count)")
                .font(DWFont.mono(11, .medium))
                .foregroundStyle(DWColor.textSecondary)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(DWCircleGlassButtonStyle(size: 30))
            .accessibilityLabel("general.done")
        }
    }

    // MARK: - Arc + canvas

    private var arc: some View {
        ZStack {
            DWCircularProgressArc(progress: step.progress)
                .frame(width: DWMetric.trainerArc, height: DWMetric.trainerArc)

            Group {
                if let image = stereogramVM.resultImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    DWColor.surface.overlay {
                        ProgressView().tint(DWColor.cyan)
                    }
                }
            }
            .frame(width: DWMetric.trainerCanvas, height: DWMetric.trainerCanvas)
            .clipShape(Circle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DWSpace.xxl)
        .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: step)
        .accessibilityLabel("trainer.progress_accessibility \(step.rawValue) \(TrainerStep.count)")
    }

    // MARK: - Copy

    private var copy: some View {
        VStack(spacing: DWSpace.m) {
            Text(step.title)
                .font(DWFont.heroTitle)
                .foregroundStyle(DWColor.text)
            Text(step.body)
                .font(DWFont.ui(14))
                .foregroundStyle(DWColor.textSecondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 300)
        .padding(.top, DWSpace.section)
        .id(step)
        .transition(.opacity)
    }

    // MARK: - Buttons

    private var buttons: some View {
        VStack(spacing: DWSpace.s) {
            Button(action: advance) {
                Text(step.primaryTitle)
            }
            .buttonStyle(DWPrimaryButtonStyle(height: 54))

            if let secondary = step.secondaryTitle {
                Button(action: retreat) {
                    Text(secondary)
                }
                .buttonStyle(DWGlassButtonStyle())
            }
        }
    }

    // MARK: - Flow

    private func advance() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            if let next = step.next {
                step = next
            } else {
                // Saw it — bank the round and start a harder one from step 1.
                completedRound = max(completedRound, round.index + 1)
                if round.isLast {
                    dismiss()
                } else {
                    round = round.next
                    step = .armsLength
                }
            }
        }
    }

    private func retreat() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) {
            switch step {
            case .armsLength:
                // "Skip the trainer"
                dismiss()
            case .sphere:
                // "Still nothing" — back to the part people actually get stuck
                // on rather than all the way to holding the phone.
                step = .lookThrough
            default:
                step = step.previous ?? .armsLength
            }
        }
    }

    private func render() async {
        guard screen != .zero else { return }
        let settings = round.settings(canvasSide: DWMetric.trainerCanvas, screen: screen)
        await stereogramVM.generate(depthMap: round.depthMap, settings: settings)
    }

    /// The render depends on the screen as well as the round: the band width is
    /// matched to the main canvas, which is the size of the device.
    private struct RenderKey: Equatable {
        let round: Int
        let screen: CGSize
    }
}
#endif
