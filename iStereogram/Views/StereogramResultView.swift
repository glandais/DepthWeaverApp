import SwiftUI

struct StereogramResultView: View {
    let image: UIImage

    @State private var showHowToView = false
    @State private var savedToPhotos = false

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .accessibilityLabel("Generated autostereogram image")
        }
        .navigationTitle("Stereogram")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showHowToView = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("How to view")

                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("Stereogram", image: Image(uiImage: image))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share stereogram")

                Button {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    savedToPhotos = true
                } label: {
                    Image(systemName: savedToPhotos ? "checkmark.circle.fill" : "arrow.down.circle")
                }
                .accessibilityLabel(savedToPhotos ? "Saved to photos" : "Save to photos")
            }
        }
        .sheet(isPresented: $showHowToView) {
            HowToViewSheet()
        }
    }
}

struct HowToViewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("How to See the 3D Image")
                        .font(.title2)
                        .fontWeight(.bold)

                    instructionStep(
                        number: 1,
                        text: "Hold your device at arm's length"
                    )
                    instructionStep(
                        number: 2,
                        text: "Relax your eyes and look \"through\" the screen, as if focusing on something far behind it"
                    )
                    instructionStep(
                        number: 3,
                        text: "The repeating pattern will start to overlap. Keep your gaze relaxed until a 3D shape emerges"
                    )
                    instructionStep(
                        number: 4,
                        text: "Once you see the 3D image, you can slowly adjust your distance to sharpen it"
                    )

                    Text("Tip: It helps to start with the device close to your face, then slowly move it away while keeping your eyes relaxed.")
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
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func instructionStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.blue, in: Circle())

            Text(text)
                .font(.body)
        }
    }
}
