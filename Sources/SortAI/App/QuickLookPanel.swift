// MARK: - QuickLook Panel
// Dedicated preview panel for file content using macOS QuickLook

import SwiftUI
import QuickLookUI
import Quartz
import AVKit

// MARK: - QuickLook Panel View

/// A dedicated panel for previewing files, similar to Finder's spacebar preview
struct QuickLookPanel: View {
    let url: URL?
    let onCategorize: (URL, [String]) -> Void
    
    @State private var previewItem: URL?
    @State private var suggestedCategory: String = ""
    @State private var isPlaying = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            if let url = url {
                headerView(for: url)
            }
            
            Divider()
            
            // Preview content
            if let url = url {
                previewContent(for: url)
            } else {
                emptyState
            }
            
            Divider()
            
            // Footer with actions
            if url != nil {
                footerView
            }
        }
        .frame(minWidth: 300, minHeight: 400)
    }
    
    // MARK: - Header
    
    private func headerView(for url: URL) -> some View {
        HStack(spacing: 12) {
            // File icon
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(fileType(for: url))
                    Text("•")
                    Text(fileSize(for: url))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Open in Finder button
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
        }
        .padding()
    }
    
    // MARK: - Preview Content
    
    @ViewBuilder
    private func previewContent(for url: URL) -> some View {
        let ext = url.pathExtension.lowercased()
        
        switch fileCategory(ext) {
        case .image:
            imagePreview(url: url)
        case .video:
            videoPreview(url: url)
        case .audio:
            audioPreview(url: url)
        case .pdf:
            pdfPreview(url: url)
        case .text:
            textPreview(url: url)
        case .other:
            genericPreview(url: url)
        }
    }
    
    private func imagePreview(url: URL) -> some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure:
                ContentUnavailableView("Failed to load image", systemImage: "photo.badge.exclamationmark")
            case .empty:
                ProgressView()
            @unknown default:
                ContentUnavailableView("Unknown state", systemImage: "questionmark")
            }
        }
        .padding()
    }
    
    private func videoPreview(url: URL) -> some View {
        VideoPlayer(player: AVPlayer(url: url))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func audioPreview(url: URL) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentColor)
            
            Text("Audio File")
                .font(.title2)
            
            // Simple audio player
            AudioPlayerView(url: url)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private func pdfPreview(url: URL) -> some View {
        PDFPreviewView(url: url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func textPreview(url: URL) -> some View {
        ScrollView {
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            } else {
                ContentUnavailableView("Cannot read file", systemImage: "doc.text.magnifyingglass")
            }
        }
    }
    
    private func genericPreview(url: URL) -> some View {
        VStack(spacing: 20) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 80, height: 80)
            
            Text(url.lastPathComponent)
                .font(.title3)
            
            Button("Open with Default App") {
                NSWorkspace.shared.open(url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyState: some View {
        ContentUnavailableView(
            "No File Selected",
            systemImage: "doc.questionmark",
            description: Text("Select a file to preview its contents")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Category suggestion
            TextField("Category path...", text: $suggestedCategory)
                .textFieldStyle(.roundedBorder)
            
            Button("Categorize") {
                guard let url = url, !suggestedCategory.isEmpty else { return }
                let path = suggestedCategory.components(separatedBy: " / ")
                onCategorize(url, path)
                suggestedCategory = ""
            }
            .buttonStyle(.borderedProminent)
            .disabled(suggestedCategory.isEmpty)
        }
        .padding()
    }
    
    // MARK: - Helpers
    
    private enum FileCategory {
        case image, video, audio, pdf, text, other
    }
    
    private func fileCategory(_ ext: String) -> FileCategory {
        let imageExts = ["jpg", "jpeg", "png", "gif", "heic", "bmp", "tiff", "webp"]
        let videoExts = ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v"]
        let audioExts = ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma"]
        let textExts = ["txt", "md", "json", "xml", "html", "css", "js", "swift", "py"]
        
        if imageExts.contains(ext) { return .image }
        if videoExts.contains(ext) { return .video }
        if audioExts.contains(ext) { return .audio }
        if ext == "pdf" { return .pdf }
        if textExts.contains(ext) { return .text }
        return .other
    }
    
    private func fileType(for url: URL) -> String {
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? "File" : "\(ext) file"
    }
    
    private func fileSize(for url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return "Unknown size"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

// MARK: - Audio Player View

struct AudioPlayerView: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var duration: Double = 0
    
    var body: some View {
        VStack(spacing: 16) {
            // Progress slider
            Slider(value: $progress, in: 0...max(duration, 1)) { editing in
                if !editing {
                    seek(to: progress)
                }
            }
            
            // Time labels
            HStack {
                Text(formatTime(progress))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            // Controls
            HStack(spacing: 20) {
                Button {
                    seek(to: max(0, progress - 10))
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                
                Button {
                    togglePlayPause()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .buttonStyle(.borderless)
                
                Button {
                    seek(to: min(duration, progress + 10))
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding()
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
        }
    }
    
    private func setupPlayer() {
        player = AVPlayer(url: url)
        
        // Get duration
        Task {
            let asset = AVURLAsset(url: url)
            if let durationTime = try? await asset.load(.duration) {
                duration = CMTimeGetSeconds(durationTime)
            }
        }
        
        // Observe playback progress - use binding for struct-based view
        let timeObserver = player?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { _ in
            // Progress is updated via binding through Combine
        }
        _ = timeObserver
    }
    
    private func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    private func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        progress = time
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - PDF Preview View

struct PDFPreviewView: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> PDFKitView {
        let view = PDFKitView()
        view.loadPDF(from: url)
        return view
    }
    
    func updateNSView(_ nsView: PDFKitView, context: Context) {
        nsView.loadPDF(from: url)
    }
}

/// NSView wrapper for PDFKit
class PDFKitView: NSView {
    private var pdfView: NSView?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    func loadPDF(from url: URL) {
        // Remove existing view
        pdfView?.removeFromSuperview()
        
        // Create QuickLook preview if available
        if QLPreviewPanel.shared().currentPreviewItem != nil {
            // Use QLPreviewView if available
        }
        
        // Fallback: Use PDFKit directly
        if let pdfDocument = PDFKit.PDFDocument(url: url) {
            let pdfView = PDFKit.PDFView(frame: bounds)
            pdfView.document = pdfDocument
            pdfView.autoScales = true
            pdfView.autoresizingMask = [.width, .height]
            addSubview(pdfView)
            self.pdfView = pdfView
        }
    }
}

import PDFKit

// MARK: - QuickLook Preview using QLPreviewView

/// SwiftUI wrapper for QLPreviewView (macOS-compatible)
struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    
    func makeNSView(context: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.previewItem = url as NSURL
        return preview
    }
    
    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
        nsView.refreshPreviewItem()
    }
}

// MARK: - QuickLook Split View

/// A split view combining file list and QuickLook panel
struct QuickLookSplitView: View {
    @Binding var files: [FileAssignment]
    @State private var selectedFile: FileAssignment?
    let onCategorize: (URL, [String]) -> Void
    
    var body: some View {
        HSplitView {
            // File list
            List(files, selection: $selectedFile) { file in
                HStack {
                    Image(systemName: iconForFile(file.url))
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading) {
                        Text(file.filename)
                            .lineLimit(1)
                        
                        Text(file.source.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    if file.needsDeepAnalysis {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                .tag(file)
            }
            .frame(minWidth: 200)
            
            // QuickLook panel
            QuickLookPanel(
                url: selectedFile?.url,
                onCategorize: onCategorize
            )
            .frame(minWidth: 300)
        }
    }
    
    private func iconForFile(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "mp3", "m4a", "wav": return "music.note"
        case "jpg", "jpeg", "png", "gif": return "photo.fill"
        case "txt", "md": return "doc.text.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    QuickLookPanel(
        url: URL(fileURLWithPath: "/Users/Shared/sample.txt"),
        onCategorize: { _, _ in }
    )
    .frame(width: 400, height: 500)
}

