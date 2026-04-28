import SwiftUI

struct StereogramResultView: View {
    let image: UIImage

    @State private var showHowToView = false
    @State private var savedToPhotos = false
    @State private var zoom: CGFloat = 1.0
    @State private var lastZoom: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var barVisible = true
    @State private var hideBarTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(zoom)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            zoom = max(1.0, lastZoom * value.magnification)
                        }
                        .onEnded { value in
                            lastZoom = zoom
                            if zoom <= 1.0 {
                                withAnimation(.smooth(duration: 0.3)) {
                                    zoom = 1.0
                                    lastZoom = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                }
                            }
                        }
                        .simultaneously(with:
                            DragGesture()
                                .onChanged { value in
                                    guard zoom > 1.0 else { return }
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                }
                        )
                )
                .onTapGesture(count: 2) {
                    withAnimation(.smooth(duration: 0.3)) {
                        if zoom > 1.0 {
                            zoom = 1.0
                            lastZoom = 1.0
                            offset = .zero
                            lastOffset = .zero
                        } else {
                            zoom = 3.0
                            lastZoom = 3.0
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.smooth(duration: 0.25)) {
                        barVisible.toggle()
                    }
                    if barVisible {
                        scheduleAutoHide()
                    } else {
                        hideBarTask?.cancel()
                    }
                }
                .accessibilityLabel("result.accessibility_label")
        }
        .clipShape(Rectangle())
        .statusBarHidden(!barVisible)
        .toolbar(barVisible ? .visible : .hidden, for: .navigationBar)
        .navigationTitle("result.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { scheduleAutoHide() }
        .onDisappear { hideBarTask?.cancel() }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showHowToView = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("help.how_to_view_button")

                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview(String(localized: "result.title"), image: Image(uiImage: image))
                ) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("result.share")

                Button {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    withAnimation(.snappy) {
                        savedToPhotos = true
                    }
                } label: {
                    Image(systemName: savedToPhotos ? "checkmark.circle.fill" : "arrow.down.circle")
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(savedToPhotos ? "result.saved_to_photos" : "result.save_to_photos")
            }
        }
        .sheet(isPresented: $showHowToView) {
            HowToViewSheet()
        }
    }

    private func scheduleAutoHide() {
        hideBarTask?.cancel()
        hideBarTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.25)) {
                barVisible = false
            }
        }
    }
}

struct HowToViewSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("help.how_to_see_3d")
                        .font(.title2)
                        .fontWeight(.bold)

                    instructionStep(
                        number: 1,
                        text: "help.view_step_hold"
                    )
                    instructionStep(
                        number: 2,
                        text: "help.view_step_relax"
                    )
                    instructionStep(
                        number: 3,
                        text: "help.view_step_overlap_alt"
                    )
                    instructionStep(
                        number: 4,
                        text: "help.view_step_adjust"
                    )

                    Text("help.tip_device_close")
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

    private func instructionStep(number: Int, text: LocalizedStringKey) -> some View {
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
