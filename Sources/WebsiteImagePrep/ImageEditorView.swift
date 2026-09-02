import SwiftUI
import UniformTypeIdentifiers

struct ImageEditorView: View {
    @ObservedObject var model: AppModel
    @Binding var item: PreparedImage
    @State private var dragStart = CGSize.zero
    @State private var zoomStart = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Position & Scale")
                    .font(.title3.weight(.semibold))
                Spacer()
                Label("Proportions locked", systemImage: "lock.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            GeometryReader { geometry in
                let available = CGSize(width: max(geometry.size.width - 40, 1), height: max(geometry.size.height - 38, 1))
                let canvas = fittedCanvas(in: available)
                let imageSize = fittedImage(in: canvas)

                ZStack {
                    CheckerboardView()
                        .frame(width: canvas.width + 24, height: canvas.height + 24)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    Color.white
                        .frame(width: canvas.width, height: canvas.height)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

                    Image(nsImage: item.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: imageSize.width * item.zoom, height: imageSize.height * item.zoom)
                        .overlay {
                            Rectangle()
                                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                .allowsHitTesting(false)
                        }
                        .offset(x: item.offsetX * canvas.width, y: item.offsetY * canvas.height)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    item.offsetX = dragStart.width + value.translation.width / canvas.width
                                    item.offsetY = dragStart.height + value.translation.height / canvas.height
                                }
                                .onEnded { _ in
                                    dragStart = CGSize(width: item.offsetX, height: item.offsetY)
                                }
                        )
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    item.zoom = min(max(zoomStart * value, 0.1), 6)
                                }
                                .onEnded { _ in zoomStart = item.zoom }
                        )

                    VStack {
                        HStack {
                            Label("Drag image to position", systemImage: "hand.draw")
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 7)
                                .background(.regularMaterial, in: Capsule())
                            Spacer()
                        }
                        Spacer()
                    }
                    .frame(width: canvas.width, height: canvas.height)
                    .padding(12)
                    .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    dragStart = CGSize(width: item.offsetX, height: item.offsetY)
                    zoomStart = item.zoom
                }
                .onChange(of: item.id) { _ in
                    dragStart = CGSize(width: item.offsetX, height: item.offsetY)
                    zoomStart = item.zoom
                }
            }

            Divider()
            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundStyle(.secondary)
                Slider(value: $item.zoom, in: 0.1...6)
                    .onChange(of: item.zoom) { value in zoomStart = value }
                Image(systemName: "plus.magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("\(Int((item.zoom * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 54, alignment: .trailing)
                Button("Fit") {
                    item.zoom = 1
                    item.offsetX = 0
                    item.offsetY = 0
                    syncGestureState()
                }
                Button("Center") {
                    item.offsetX = 0
                    item.offsetY = 0
                    syncGestureState()
                }
                Button("Reset") {
                    item.zoom = 1
                    item.offsetX = 0
                    item.offsetY = 0
                    syncGestureState()
                }
            }
            .buttonStyle(.bordered)
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func fittedCanvas(in available: CGSize) -> CGSize {
        let ratio = CGFloat(model.canvasWidth) / CGFloat(max(model.canvasHeight, 1))
        var width = available.width
        var height = width / ratio
        if height > available.height {
            height = available.height
            width = height * ratio
        }
        return CGSize(width: max(width, 1), height: max(height, 1))
    }

    private func fittedImage(in canvas: CGSize) -> CGSize {
        let source = item.pixelSize
        var scale = min(canvas.width / max(source.width, 1), canvas.height / max(source.height, 1))
        if model.doNotEnlargeSmallImages {
            let outputScale = min(CGFloat(model.canvasWidth) / max(source.width, 1), CGFloat(model.canvasHeight) / max(source.height, 1))
            if outputScale > 1 {
                scale /= outputScale
            }
        }
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    private func syncGestureState() {
        dragStart = CGSize(width: item.offsetX, height: item.offsetY)
        zoomStart = item.zoom
    }
}

private struct CheckerboardView: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            let columns = Int(ceil(size.width / tile))
            let rows = Int(ceil(size.height / tile))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
                        with: .color(Color(nsColor: .separatorColor).opacity(0.12))
                    )
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}
