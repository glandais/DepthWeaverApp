#if os(iOS)
import SwiftUI

struct HowToUseSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("help.how_to_use_title")
                        .font(.title2)
                        .fontWeight(.bold)

                    step(1, icon: "cube.transparent",
                         text: "help.step_acquire_full")

                    step(2, icon: "slider.horizontal.below.square.and.square.filled",
                         text: "help.step_adjust_depth")

                    step(3, icon: "square.grid.3x3",
                         text: "help.step_choose_pattern")

                    step(4, icon: "slider.horizontal.3",
                         text: "help.step_adjust_settings")

                    step(5, icon: "square.and.arrow.up",
                         text: "help.step_share")

                    Divider()

                    Text("help.viewing_3d")
                        .font(.title3)
                        .fontWeight(.semibold)

                    step(1, icon: "hand.raised",
                         text: "help.view_step_hold")

                    step(2, icon: "eye.slash",
                         text: "help.view_step_relax")

                    step(3, icon: "cube.transparent",
                         text: "help.view_step_overlap")

                    Text("help.tip_device_close_alt")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("general.done") { dismiss() }
                }
            }
        }
    }

    private func step(_ number: Int, icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.blue, in: Circle())

            Text(text)
                .font(.body)
        }
    }
}
#endif
