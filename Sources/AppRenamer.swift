import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Model

struct AppInfo {
    let url: URL
    let name: String
    let bundleID: String
    let icon: NSImage
}

enum RenameError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}

func loadAppInfo(_ url: URL) -> AppInfo? {
    guard url.pathExtension == "app", let bundle = Bundle(url: url) else { return nil }
    let info = bundle.infoDictionary ?? [:]
    let name = (info["CFBundleDisplayName"] as? String)
        ?? (info["CFBundleName"] as? String)
        ?? url.deletingPathExtension().lastPathComponent
    return AppInfo(url: url, name: name,
                   bundleID: bundle.bundleIdentifier ?? "",
                   icon: NSWorkspace.shared.icon(forFile: url.path))
}

@discardableResult
func run(_ tool: String, _ args: [String]) throws -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    try p.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let out = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    if p.terminationStatus != 0 {
        let name = (tool as NSString).lastPathComponent, code = Int(p.terminationStatus)
        throw RenameError.message(String(localized: "\(name) exited with code \(code): \(out)"))
    }
    return out
}

/// Reads a plist (or .strings) file, lets `edit` mutate it, writes it back in the original format.
func editPlist(_ url: URL, _ edit: (inout [String: Any]) -> Bool) throws {
    let data = try Data(contentsOf: url)
    var format = PropertyListSerialization.PropertyListFormat.xml
    guard var dict = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any] else {
        throw RenameError.message(String(localized: "Can't read \(url.lastPathComponent)"))
    }
    guard edit(&dict) else { return }
    // OpenStep (.strings) can't be written back — save as XML, bundles accept it.
    let outFormat: PropertyListSerialization.PropertyListFormat = format == .openStep ? .xml : format
    let out = try PropertyListSerialization.data(fromPropertyList: dict, format: outFormat, options: 0)
    try out.write(to: url, options: .atomic)
}

/// Builds an .icns from any image (or copies it as is if it's already .icns).
func writeICNS(from source: URL, to dest: URL) throws {
    let fm = FileManager.default
    if source.pathExtension.lowercased() == "icns" {
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: source, to: dest)
        return
    }
    guard let image = NSImage(contentsOf: source) else {
        throw RenameError.message(String(localized: "Can't open image \(source.lastPathComponent)"))
    }
    let iconset = fm.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("iconset")
    try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: iconset) }

    let variants: [(Int, String)] = [
        (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
        (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
        (512, "512x512"), (1024, "512x512@2x"),
    ]
    for (px, name) in variants {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { continue }
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        ctx?.imageInterpolation = .high
        NSGraphicsContext.current = ctx
        // Aspect-fit into the square.
        let size = image.size
        let scale = min(CGFloat(px) / max(size.width, 1), CGFloat(px) / max(size.height, 1))
        let w = size.width * scale, h = size.height * scale
        image.draw(in: NSRect(x: (CGFloat(px) - w) / 2, y: (CGFloat(px) - h) / 2, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])?
            .write(to: iconset.appendingPathComponent("icon_\(name).png"))
    }
    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
    try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", dest.path])
}

struct Options {
    var newName: String
    var newBundleID: String
    var newIcon: URL?
    var makeCopy: Bool
    var resign: Bool
    var removeQuarantine: Bool
}

func process(_ app: AppInfo, _ o: Options, log: @escaping (String) -> Void) throws -> URL {
    let fm = FileManager.default
    let parent = app.url.deletingLastPathComponent()
    let target = parent.appendingPathComponent(o.newName).appendingPathExtension("app")
    let nameChanged = target.standardizedFileURL != app.url.standardizedFileURL

    var work = app.url
    if o.makeCopy {
        guard !fm.fileExists(atPath: target.path) else {
            throw RenameError.message(String(localized: "\(target.lastPathComponent) already exists in \(parent.path)"))
        }
        log(String(localized: "Copying to \(target.path)…"))
        try run("/usr/bin/ditto", [app.url.path, target.path])
        work = target
    } else if nameChanged && fm.fileExists(atPath: target.path) {
        throw RenameError.message(String(localized: "\(target.lastPathComponent) already exists"))
    }

    let contents = work.appendingPathComponent("Contents")
    let resources = contents.appendingPathComponent("Resources")
    let iconFileName = "AppRenamerIcon"
    if let icon = o.newIcon {
        log(String(localized: "Building icon from \(icon.lastPathComponent)…"))
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try writeICNS(from: icon, to: resources.appendingPathComponent(iconFileName).appendingPathExtension("icns"))
    }

    log(String(localized: "Updating Info.plist…"))
    try editPlist(contents.appendingPathComponent("Info.plist")) { d in
        d["CFBundleIdentifier"] = o.newBundleID
        d["CFBundleName"] = o.newName
        d["CFBundleDisplayName"] = o.newName
        if o.newIcon != nil {
            d["CFBundleIconFile"] = iconFileName
            // An icon from Assets.car (CFBundleIconName) wins over CFBundleIconFile.
            d.removeValue(forKey: "CFBundleIconName")
        }
        return true
    }

    // Localized names override Info.plist in Finder/Dock.
    if let items = try? fm.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil) {
        for lproj in items where lproj.pathExtension == "lproj" {
            let strings = lproj.appendingPathComponent("InfoPlist.strings")
            guard fm.fileExists(atPath: strings.path) else { continue }
            try? editPlist(strings) { d in
                var changed = false
                for key in ["CFBundleName", "CFBundleDisplayName"] where d[key] != nil {
                    d[key] = o.newName; changed = true
                }
                if changed { log(String(localized: "Updated \(lproj.lastPathComponent)/InfoPlist.strings")) }
                return changed
            }
        }
    }

    if !o.makeCopy && nameChanged {
        log(String(localized: "Renaming to \(target.lastPathComponent)…"))
        try fm.moveItem(at: work, to: target)
        work = target
    }

    if o.removeQuarantine {
        log(String(localized: "Removing quarantine…"))
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", work.path])
    }
    if o.resign {
        log(String(localized: "Re-signing ad-hoc…"))
        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", work.path])
    }

    let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    _ = try? run(lsregister, ["-f", work.path])
    _ = try? run("/usr/bin/touch", [work.path])
    return work
}

// MARK: - UI

@MainActor
final class ViewModel: ObservableObject {
    @Published var app: AppInfo?
    @Published var newName = ""
    @Published var newBundleID = ""
    @Published var newIcon: URL?
    @Published var newIconPreview: NSImage?
    @Published var makeCopy = true
    @Published var resign = true
    @Published var removeQuarantine = true
    @Published var log: [String] = []
    @Published var busy = false

    func load(_ url: URL) {
        guard let info = loadAppInfo(url) else {
            log = [String(localized: "Not an .app: \(url.path)")]; return
        }
        app = info
        newName = info.url.deletingPathExtension().lastPathComponent
        newBundleID = info.bundleID
        newIcon = nil
        newIconPreview = nil
        log = []
    }

    static let imageTypes: [UTType] = [.png, .jpeg, .tiff, .heic, .icns, .image]

    func setIcon(_ url: URL) {
        guard let img = NSImage(contentsOf: url) else {
            log = [String(localized: "Can't open image \(url.lastPathComponent)")]; return
        }
        newIcon = url
        newIconPreview = img
    }

    func chooseIcon() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.imageTypes
        panel.message = String(localized: "A square image, at least 512×512. Best: 1024×1024 PNG with transparency")
        if panel.runModal() == .OK, let url = panel.url { setIcon(url) }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.treatsFilePackagesAsDirectories = false
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    var validationError: String? {
        let name = newName.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return String(localized: "Name is empty") }
        if name.contains("/") || name.contains(":") { return String(localized: "Name must not contain / or :") }
        if newBundleID.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) == nil {
            return String(localized: "Bundle ID: Latin letters, digits, “-” and dots only (e.g. com.example.app)")
        }
        return nil
    }

    func apply() {
        guard let app else { return }
        let opts = Options(newName: newName.trimmingCharacters(in: .whitespaces),
                           newBundleID: newBundleID, newIcon: newIcon, makeCopy: makeCopy,
                           resign: resign, removeQuarantine: removeQuarantine)
        busy = true
        log = []
        let append: (String) -> Void = { msg in Task { @MainActor in self.log.append(msg) } }
        Task.detached {
            do {
                let result = try process(app, opts, log: append)
                await MainActor.run {
                    let logSoFar = self.log
                    self.busy = false
                    if let info = loadAppInfo(result) { self.load(info.url) }
                    self.log = logSoFar + [String(localized: "✅ Done: \(result.path)")]
                    NSWorkspace.shared.activateFileViewerSelecting([result])
                }
            } catch {
                await MainActor.run {
                    var msg = "❌ \(error.localizedDescription)"
                    if (error as NSError).code == NSFileWriteNoPermissionError || "\(error)".contains("ermission") {
                        msg += "\n" + String(localized: "Try “Make a copy” mode, or allow access in System Settings → Privacy & Security → App Management.")
                    }
                    self.log.append(msg)
                    self.busy = false
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject var vm = ViewModel()
    @State var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            dropZone
            if vm.app != nil { form }
            if !vm.log.isEmpty {
                ScrollView {
                    Text(vm.log.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            // `open -a AppRenamer --args /path/App.app [/path/icon.png]`
            let args = CommandLine.arguments.dropFirst().filter { FileManager.default.fileExists(atPath: $0) }
            if let app = args.first(where: { $0.hasSuffix(".app") }) { vm.load(URL(fileURLWithPath: app)) }
            if let icon = args.first(where: { !$0.hasSuffix(".app") }) { vm.setIcon(URL(fileURLWithPath: icon)) }
        }
    }

    var dropZone: some View {
        HStack(spacing: 14) {
            if let app = vm.app {
                Image(nsImage: app.icon).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.headline)
                    Text(app.bundleID).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(app.url.path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                }
            } else {
                Image(systemName: "app.dashed").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Drop an .app here or choose one").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose…") { vm.choose() }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 84)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 1.5, dash: vm.app == nil ? [6] : []))
        )
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in vm.load(url) } }
            }
            return true
        }
    }

    @State var iconDropTargeted = false

    var iconWell: some View {
        let img = vm.newIconPreview ?? vm.app?.icon ?? NSImage()
        return Image(nsImage: img)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 48, height: 48)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(iconDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [4]))
            )
            .onTapGesture { vm.chooseIcon() }
            .onDrop(of: [.fileURL], isTargeted: $iconDropTargeted) { providers in
                guard let p = providers.first else { return false }
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in vm.setIcon(url) } }
                }
                return true
            }
            .help("Click or drop an image")
    }

    var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("New name").gridColumnAlignment(.trailing)
                    TextField("", text: $vm.newName).textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Bundle ID")
                    TextField("", text: $vm.newBundleID).textFieldStyle(.roundedBorder)
                }
                GridRow(alignment: .center) {
                    Text("Icon")
                    HStack(spacing: 10) {
                        iconWell
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Button("Choose image…") { vm.chooseIcon() }
                                if vm.newIcon != nil {
                                    Button("Keep current") { vm.newIcon = nil; vm.newIconPreview = nil }
                                }
                            }
                            Group {
                                if let icon = vm.newIcon { Text(icon.lastPathComponent) }
                                else { Text("PNG, JPEG, HEIC or ICNS. You can drop it on the square.") }
                            }
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
            }
            Toggle("Make a copy (keep the original untouched)", isOn: $vm.makeCopy)
            Toggle("Re-sign ad-hoc (otherwise the app may not launch)", isOn: $vm.resign)
            Toggle("Remove quarantine", isOn: $vm.removeQuarantine)
            HStack {
                if let err = vm.validationError {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                if vm.busy { ProgressView().controlSize(.small) }
                Button("Apply") { vm.apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.busy || vm.validationError != nil)
            }
        }
    }
}

@main
struct AppRenamerApp: App {
    var body: some Scene {
        WindowGroup("App Renamer") { ContentView() }
            .windowResizability(.contentSize)
    }
}
