import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                imageSidebar
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 330)
                Divider()
                editor
                    .frame(minWidth: 540, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                settingsSidebar
                    .frame(width: 330)
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 1120, minHeight: 700)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(model.alertTitle, isPresented: $model.showingAlert) {
            if model.alertTitle == "Export complete" {
                Button("Show in Finder") { model.revealOutputFolder() }
                Button("Done", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(model.alertMessage)
        }
        .sheet(isPresented: $model.showingRenameReview) {
            RenameReviewView(model: model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .addImagesRequested)) { _ in
            model.chooseImages()
        }
        .onReceive(NotificationCenter.default.publisher(for: .importNamesRequested)) { _ in
            model.chooseRenameFile()
        }
        .onOpenURL { url in
            model.handleIncomingURLs([url])
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Picker("Preset", selection: Binding(
                get: { model.preset },
                set: { model.applyPreset($0) }
            )) {
                ForEach(CanvasPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .labelsHidden()
            .frame(width: 220)

            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(Color.accentColor)
            Text("Website Image Prep")
                .font(.title2.weight(.semibold))
            Spacer()
            Text("Private • Works offline")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button {
                model.chooseImages()
            } label: {
                Label("Add Images", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
    }

    private var imageSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Images")
                    .font(.title3.weight(.semibold))
                Text("\(model.images.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                Spacer()
                if !model.images.isEmpty {
                    Button("Clear") { model.clearAll() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)

            Button(action: model.chooseImages) {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop images or folder")
                        .fontWeight(.medium)
                    Text("PNG, JPG, HEIC, TIFF and more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(isDropTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if model.images.isEmpty {
                Spacer()
                Text("Your images will appear here")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.images) { item in
                            imageRow(item)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Button(action: model.chooseRenameFile) {
                    Label("Import CSV / Excel", systemImage: "tablecells")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: model.pasteNamingScreenshot) {
                    Label("Paste Naming Screenshot", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(model.isReadingNames)

                if let status = model.csvStatus {
                    Label(status, systemImage: model.matchedRenameCount == model.images.count ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(model.matchedRenameCount == model.images.count ? .green : .orange)
                } else {
                    Text(model.isReadingNames ? "Reading names…" : "CSV, Excel .xlsx, or screenshot")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func imageRow(_ item: PreparedImage) -> some View {
        let selected = model.selectedID == item.id
        HStack(spacing: 10) {
            ZStack {
                Color.white
                Image(nsImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(4)
            }
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.secondary.opacity(0.2)))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.originalFilename)
                    .lineLimit(1)
                    .fontWeight(.medium)
                Text("\(Int(item.pixelSize.width)) × \(Int(item.pixelSize.height))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let csvFilename = model.displayCSVFilename(for: item) {
                    Text("→ \(csvFilename)")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button {
                model.remove(item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(selected ? Color.accentColor.opacity(0.13) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedID = item.id }
    }

    @ViewBuilder
    private var editor: some View {
        if let binding = model.selectedImageBinding {
            ImageEditorView(model: model, item: binding)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundStyle(.tertiary)
                Text("Add an image to begin")
                    .font(.title2.weight(.semibold))
                Text("Then drag to position it and use the slider to zoom.")
                    .foregroundStyle(.secondary)
                Button("Choose Images", action: model.chooseImages)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Export Settings")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding(16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    settingsSection("Canvas Size") {
                        HStack {
                            labeledNumberField("Width", value: Binding(
                                get: { model.canvasWidth },
                                set: { model.setCanvasWidth($0) }
                            ))
                            Button {
                                model.dimensionsLinked.toggle()
                            } label: {
                                Image(systemName: model.dimensionsLinked ? "link" : "link.badge.plus")
                                    .frame(width: 22, height: 22)
                            }
                            .buttonStyle(.borderless)
                            .help(model.dimensionsLinked ? "Width and height are linked" : "Width and height are independent")
                            labeledNumberField("Height", value: Binding(
                                get: { model.canvasHeight },
                                set: { model.setCanvasHeight($0) }
                            ))
                        }

                        Picker("Preset", selection: Binding(
                            get: { model.preset },
                            set: { model.applyPreset($0) }
                        )) {
                            ForEach(CanvasPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                    }

                    settingsSection("Export Formats") {
                        HStack(spacing: 14) {
                            ForEach(OutputFormat.allCases) { format in
                                Toggle(format.rawValue, isOn: Binding(
                                    get: { model.outputFormats.contains(format) },
                                    set: { model.setOutputFormat(format, enabled: $0) }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                        Text("Choose one format or export several at once. PSD files are flattened for easy client delivery.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    settingsSection("Background") {
                        HStack {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white)
                                .frame(width: 34, height: 24)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.35)))
                            Text("White")
                            Spacer()
                            Text("All formats")
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    }

                    if model.outputFormats.contains(.jpeg) {
                        settingsSection("Maximum JPEG Size") {
                            HStack {
                                TextField("Maximum", value: $model.maximumMB, format: .number.precision(.fractionLength(0...2)))
                                    .textFieldStyle(.roundedBorder)
                                Text("MB")
                                    .foregroundStyle(.secondary)
                            }
                            Label("Starts at 100% quality and reduces only if required", systemImage: "checkmark.seal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("PNG and PSD preserve full-quality pixels. The MB limit applies only to JPEG files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    settingsSection("Naming") {
                        Picker("Method", selection: $model.namingStrategy) {
                            ForEach(NamingStrategy.allCases) { strategy in
                                Text(strategy.rawValue).tag(strategy)
                            }
                        }
                        .labelsHidden()

                        if model.namingStrategy == .sequential {
                            TextField("Filename prefix", text: $model.sequentialPrefix)
                                .textFieldStyle(.roundedBorder)
                            Text("Example: \(model.sequentialPrefix)-001.jpg")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if model.namingStrategy == .csv {
                            HStack {
                                Button("CSV / Excel", action: model.chooseRenameFile)
                                    .buttonStyle(.bordered)
                                Button("Paste Screenshot", action: model.pasteNamingScreenshot)
                                    .buttonStyle(.bordered)
                            }
                            .disabled(model.isReadingNames)

                            VStack(spacing: 5) {
                                Image(systemName: "text.viewfinder")
                                    .foregroundStyle(Color.accentColor)
                                Text(model.isReadingNames ? "Reading names…" : "Drop naming file or screenshot")
                                    .font(.caption.weight(.medium))
                                Text("You can review names before applying")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5]))
                            }
                            .onDrop(
                                of: [UTType.fileURL, UTType.image],
                                isTargeted: nil,
                                perform: handleNamingDrop
                            )
                        }
                    }

                    settingsSection("Image Scaling") {
                        Toggle("Do not enlarge small images", isOn: $model.doNotEnlargeSmallImages)
                        Text("When off, Fit can enlarge a small image. Proportions always stay locked.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Picker("Clarity", selection: $model.clarityLevel) {
                            ForEach(ClarityLevel.allCases) { level in
                                Text(level.rawValue).tag(level)
                            }
                        }

                        if let message = model.selectedClarityMessage {
                            Label(
                                message,
                                systemImage: message.contains("warning") ? "exclamationmark.triangle.fill" : "checkmark.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(message.contains("warning") || message.contains("note") ? .orange : .green)
                        }
                    }

                    settingsSection("Output Folder") {
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(Color.accentColor)
                            Text(model.outputFolder?.lastPathComponent ?? "Choose a folder")
                                .lineLimit(1)
                            Spacer()
                            Button("Choose…", action: model.chooseOutputFolder)
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }

            Divider()
            VStack(spacing: 10) {
                if model.isExporting {
                    ProgressView(value: model.exportProgress)
                    Text("Exporting \(Int(model.exportProgress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action: model.exportImages) {
                    Label(
                        model.isExporting ? "Exporting…" : "Export \(model.exportFileCount) File\(model.exportFileCount == 1 ? "" : "s")",
                        systemImage: "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.images.isEmpty || model.isExporting)
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusBar: some View {
        HStack {
            Label(model.outputFormatSummary, systemImage: "photo")
            Text("•")
            Text("sRGB")
            Text("•")
            Text("\(model.canvasWidth) × \(model.canvasHeight) px")
            if model.outputFormats.contains(.jpeg) {
                Text("•")
                Text("JPEG under \(model.maximumMB, specifier: "%.2g") MB")
            }
            Spacer()
            if let selected = model.selectedImage {
                Text(selected.originalFilename)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 32)
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(.bottom, 4)
    }

    private func labeledNumberField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(label, value: value, format: .number)
                    .textFieldStyle(.roundedBorder)
                Text("px")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                if let url {
                    DispatchQueue.main.async { model.handleIncomingURLs([url]) }
                }
            }
        }
        return accepted
    }

    private func handleNamingDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = item as? URL
                    }
                    if let url {
                        DispatchQueue.main.async { model.importRenameSource(url) }
                    }
                }
                return true
            }

            if provider.canLoadObject(ofClass: NSImage.self) {
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    if let image = object as? NSImage {
                        DispatchQueue.main.async {
                            model.recognizeNames(in: image, source: "dropped screenshot")
                        }
                    }
                }
                return true
            }
        }
        return false
    }
}
