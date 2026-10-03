import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

struct NoiseTrack: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var category: String
    var symbol: String
    var audioFile: String
    var coverFile: String?
    var duration: Double
    var builtIn: Bool
}

private struct LibraryState: Codable {
    var imported: [NoiseTrack] = []
    var hidden: [String] = []
    var selectedID: String?
}

private struct ImportResult: Sendable {
    var tracks: [NoiseTrack]
    var failures: [String]
}

@MainActor
final class RainPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var chosenSkin: RainSkin = .storm {
        didSet { UserDefaults.standard.set(chosenSkin.rawValue, forKey: "chosenSkin") }
    }
    @Published var followsSound = true {
        didSet { UserDefaults.standard.set(followsSound, forKey: "followsSound") }
    }
    var skin: RainSkin { followsSound ? (RainSkin.matching(currentTrack?.category ?? "") ?? chosenSkin) : chosenSkin }
    func chooseSkin(_ skin: RainSkin) { chosenSkin = skin; followsSound = false }
    @Published var tracks: [NoiseTrack] = []
    @Published var selectedID: String?
    @Published var isPlaying = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 0.5 {
        didSet { audio?.volume = Float(volume); UserDefaults.standard.set(volume, forKey: "volume") }
    }
    @Published var looping = true {
        didSet { audio?.numberOfLoops = looping ? -1 : 0; UserDefaults.standard.set(looping, forKey: "looping") }
    }
    @Published var sleepMinutes = 0
    @Published var sleepRemaining: Double = 0
    @Published var isImporting = false
    @Published var notice: String?
    @Published var error: String?
    private var builtInTracks: [NoiseTrack] = []
    private var state = LibraryState()
    private var audio: AVAudioPlayer?
    private var timer: Timer?
    private var sleepDeadline: Date?
    let dataDirectory: URL
    private var audioDirectory: URL { dataDirectory.appendingPathComponent("Audio", isDirectory: true) }
    private var stateURL: URL { dataDirectory.appendingPathComponent("library.json") }
    var currentTrack: NoiseTrack? { tracks.first { $0.id == selectedID } }
    var hasHiddenBuiltIns: Bool { !state.hidden.isEmpty }
    var defaultCount: Int { builtInTracks.count }

    override init() {
        if let path = ProcessInfo.processInfo.environment["RAINROOM_DATA_DIR"] {
            dataDirectory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            dataDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Rainroom", isDirectory: true)
        }
        super.init()
        let defaults = UserDefaults.standard
        chosenSkin = RainSkin(rawValue: defaults.string(forKey: "chosenSkin") ?? "") ?? .storm
        followsSound = defaults.object(forKey: "followsSound") == nil ? true : defaults.bool(forKey: "followsSound")
        volume = defaults.object(forKey: "volume") == nil ? 0.5 : defaults.double(forKey: "volume")
        looping = defaults.object(forKey: "looping") == nil ? true : defaults.bool(forKey: "looping")
        do {
            try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                state = try JSONDecoder().decode(LibraryState.self, from: Data(contentsOf: stateURL))
            }
            guard let manifest = Bundle.main.url(forResource: "Tracks", withExtension: "json") else {
                throw failure("找不到内置声音资料库，请重新安装 App。")
            }
            builtInTracks = try JSONDecoder().decode([NoiseTrack].self, from: Data(contentsOf: manifest))
            refreshTracks()
            if let first = tracks.first(where: { $0.id == state.selectedID }) ?? tracks.first {
                select(first, autoplay: false)
            }
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } catch { self.error = error.localizedDescription }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Rainroom", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func refreshTracks() {
        tracks = builtInTracks.filter { !state.hidden.contains($0.id) } + state.imported
    }
    private func persist(_ next: LibraryState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: stateURL, options: .atomic)
        state = next
    }
    func audioURL(for track: NoiseTrack) -> URL {
        if track.builtIn {
            return Bundle.main.resourceURL!.appendingPathComponent(track.audioFile)
        }
        return audioDirectory.appendingPathComponent(track.audioFile)
    }
    func coverURL(for track: NoiseTrack) -> URL? {
        guard let name = track.coverFile else { return nil }
        return Bundle.main.resourceURL?.appendingPathComponent(name)
    }
    func select(_ track: NoiseTrack, autoplay: Bool? = nil) {
        let resume = autoplay ?? isPlaying
        if track.id == selectedID, audio != nil {
            if autoplay == true { play() }
            return
        }
        do {
            let next = try AVAudioPlayer(contentsOf: audioURL(for: track))
            next.volume = Float(volume)
            next.numberOfLoops = looping ? -1 : 0
            next.delegate = self
            next.prepareToPlay()
            audio?.stop()
            audio = next
            selectedID = track.id
            duration = next.duration
            position = 0
            isPlaying = false
            var updated = state
            updated.selectedID = track.id
            try persist(updated)
            if resume { play() }
        } catch { self.error = "无法打开「\(track.title)」：\(error.localizedDescription)" }
    }
    func playTrack(_ track: NoiseTrack) {
        if track.id == selectedID { toggle() } else { select(track, autoplay: true) }
    }
    func stepTrack(_ direction: Int) {
        guard !tracks.isEmpty else { return }
        let index = tracks.firstIndex { $0.id == selectedID } ?? 0
        select(tracks[(index + direction + tracks.count) % tracks.count])
    }
    func chooseFiles() {
        guard !isImporting else { return }
        let panel = NSOpenPanel()
        panel.title = "导入音频"
        panel.message = "选择 MP3、M4A、WAV、AIFF 或 FLAC 文件。音频会复制到雨间的资料库。"
        panel.prompt = "导入"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { await self.importFiles(urls) }
        }
    }
    func importFiles(_ urls: [URL]) async {
        guard !isImporting, !urls.isEmpty else { return }
        isImporting = true
        notice = nil
        let destination = audioDirectory
        let result = await Task.detached(priority: .userInitiated) {
            var imported: [NoiseTrack] = []
            var failures: [String] = []
            for url in urls {
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let id = UUID().uuidString.lowercased()
                let ext = url.pathExtension.lowercased()
                let filename = id + (ext.isEmpty ? "" : "." + ext)
                let copy = destination.appendingPathComponent(filename)
                do {
                    let check = try AVAudioPlayer(contentsOf: url)
                    guard check.duration.isFinite && check.duration > 0 else {
                        throw NSError(domain: "Rainroom", code: 2, userInfo: [NSLocalizedDescriptionKey: "音频时长无效"])
                    }
                    try FileManager.default.copyItem(at: url, to: copy)
                    imported.append(NoiseTrack(id: id, title: url.deletingPathExtension().lastPathComponent,
                        subtitle: "你导入的声音", category: "本地音频", symbol: "waveform",
                        audioFile: filename, coverFile: nil, duration: check.duration, builtIn: false))
                } catch {
                    try? FileManager.default.removeItem(at: copy)
                    failures.append(url.lastPathComponent + "：" + error.localizedDescription)
                }
            }
            return ImportResult(tracks: imported, failures: failures)
        }.value
        defer { isImporting = false }
        if !result.tracks.isEmpty {
            do {
                var next = state
                next.imported.append(contentsOf: result.tracks)
                try persist(next)
                refreshTracks()
                if currentTrack == nil, let first = result.tracks.first { select(first, autoplay: false) }
                notice = "已导入 \(result.tracks.count) 个音频"
            } catch {
                for track in result.tracks { try? FileManager.default.removeItem(at: audioURL(for: track)) }
                self.error = "无法保存资料库：\(error.localizedDescription)"
            }
        }
        if !result.failures.isEmpty {
            error = "以下文件未能导入：\n" + result.failures.joined(separator: "\n")
        }
    }
    func remove(_ track: NoiseTrack) {
        guard !isImporting else { return }
        do {
            var next = state
            if track.builtIn {
                next.hidden.append(track.id)
            } else {
                next.imported.removeAll { $0.id == track.id }
            }
            if selectedID == track.id { next.selectedID = nil }
            // Persist before removing the managed copy; a failed Trash move rolls the library back.
            let previous = state
            try persist(next)
            if !track.builtIn {
                do {
                    let url = audioURL(for: track)
                    if FileManager.default.fileExists(atPath: url.path) {
                        guard url.standardizedFileURL.path.hasPrefix(audioDirectory.path + "/") else {
                            throw failure("音频文件位置无效。")
                        }
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    }
                } catch {
                    try persist(previous)
                    throw error
                }
            }
            let removedCurrent = selectedID == track.id
            if removedCurrent { audio?.stop(); audio = nil; isPlaying = false; selectedID = nil; position = 0; duration = 0 }
            refreshTracks()
            if removedCurrent, let first = tracks.first { select(first, autoplay: false) }
            notice = track.builtIn ? "已从资料库移除「\(track.title)」" : "已删除「\(track.title)」，原文件不受影响"
        } catch { self.error = "无法删除音频：\(error.localizedDescription)" }
    }
    func setTheme(_ theme: RainSkin, for track: NoiseTrack) {
        guard !track.builtIn else { return }
        do {
            var next = state
            guard let index = next.imported.firstIndex(where: { $0.id == track.id }) else { return }
            next.imported[index].category = theme.category
            next.imported[index].symbol = theme.symbol
            next.imported[index].subtitle = theme.category + " · 你导入的声音"
            try persist(next)
            refreshTracks()
            notice = "已设为" + theme.category + "主题"
        } catch { self.error = error.localizedDescription }
    }
    func restoreBuiltIns() {
        do {
            var next = state
            next.hidden = []
            try persist(next)
            refreshTracks()
            if currentTrack == nil, let first = tracks.first { select(first, autoplay: false) }
            notice = "已恢复内置声音"
        } catch { self.error = error.localizedDescription }
    }
    func toggle() { isPlaying ? pause() : play() }
    func play() {
        guard let audio else { return }
        if audio.currentTime >= duration - 0.1 { audio.currentTime = 0 }
        if audio.play() { isPlaying = true } else { error = "无法开始播放，请检查系统音频输出。" }
    }
    func pause() { audio?.pause(); isPlaying = false }
    func seek(_ value: Double) {
        let safe = min(max(value, 0), max(duration - 0.05, 0))
        audio?.currentTime = safe
        position = safe
    }
    func skip(_ seconds: Double) { seek((audio?.currentTime ?? 0) + seconds) }
    func setSleep(_ minutes: Int) {
        sleepMinutes = minutes
        sleepDeadline = minutes > 0 ? Date().addingTimeInterval(Double(minutes * 60)) : nil
        sleepRemaining = Double(minutes * 60)
    }
    func tick(now: Date = Date()) {
        position = audio?.currentTime ?? 0
        isPlaying = audio?.isPlaying ?? false
        if let deadline = sleepDeadline {
            sleepRemaining = max(0, deadline.timeIntervalSince(now))
            if sleepRemaining <= 0 { pause(); setSleep(0) }
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.audio === player else { return }
            self.isPlaying = false; self.position = self.duration
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "音频解码失败。"
        Task { @MainActor in
            guard self.audio === player else { return }
            self.pause(); self.error = message
        }
    }
    static func time(_ value: Double) -> String {
        let s = max(0, Int(value))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    func selfTest(reportPath: String, fixture: URL?) async {
        var results: [String: Any] = ["trackCount": tracks.count]
        let oldSkin = chosenSkin
        let oldFollow = followsSound
        let oldVolume = volume
        let oldLoop = looping
        volume = 0.04
        followsSound = true
        var perTrack: [[String: Any]] = []
        for track in tracks {
            select(track, autoplay: false)
            play()
            try? await Task.sleep(for: .milliseconds(400))
            tick()
            perTrack.append(["title": track.title, "duration": duration, "playing": isPlaying, "advances": position > 0.1])
            pause()
        }
        results["autoSkins"] = tracks.allSatisfy { track in
            select(track, autoplay: false)
            return skin == (RainSkin.matching(track.category) ?? chosenSkin)
        }
        chooseSkin(.fire)
        results["manualSkin"] = skin == .fire && !followsSound
        let skinReload = RainPlayer()
        results["skinPersists"] = skinReload.chosenSkin == .fire && !skinReload.followsSound
        followsSound = true
        results["allTracksPlay"] = !perTrack.isEmpty && perTrack.allSatisfy { $0["playing"] as? Bool == true && $0["advances"] as? Bool == true }
        results["tracks"] = perTrack
        seek(123)
        results["seek"] = abs((audio?.currentTime ?? 0) - 123) < 0.1
        let paused = audio?.currentTime ?? 0
        try? await Task.sleep(for: .milliseconds(300))
        results["pauseStops"] = !(audio?.isPlaying ?? true) && abs((audio?.currentTime ?? 0) - paused) < 0.1
        looping = true
        seek(duration - 0.5)
        play()
        try? await Task.sleep(for: .milliseconds(1000))
        tick()
        results["loopsAtEnd"] = isPlaying && position < 2
        setSleep(15)
        tick(now: Date().addingTimeInterval(901))
        results["sleepTimerPauses"] = !isPlaying && sleepMinutes == 0
        results["volume"] = abs((audio?.volume ?? 0) - 0.04) < 0.001
        if let fixture {
            let before = tracks.count
            await importFiles([fixture])
            let imported = tracks.last!
            results["import"] = tracks.count == before + 1 && !imported.builtIn
            results["managedCopy"] = FileManager.default.fileExists(atPath: audioURL(for: imported).path)
            let reloaded = RainPlayer()
            results["persistsAcrossLaunch"] = reloaded.tracks.contains { $0.id == imported.id }
            select(imported, autoplay: true)
            try? await Task.sleep(for: .milliseconds(250))
            results["importedPlays"] = isPlaying && duration > 0
            setTheme(.forest, for: imported)
            results["importTheme"] = currentTrack?.category == "森林" && skin == .forest
            let themedReload = RainPlayer()
            results["importThemePersists"] = themedReload.tracks.first { $0.id == imported.id }?.category == "森林"
            pause()
            remove(imported)
            results["delete"] = tracks.count == before && !tracks.contains { $0.id == imported.id }
            results["originalPreserved"] = FileManager.default.fileExists(atPath: fixture.path)
            let missing = fixture.deletingLastPathComponent().appendingPathComponent("not-present.mp3")
            await importFiles([missing])
            results["invalidFileRejected"] = tracks.count == before && error != nil
            error = nil
        }
        if let first = tracks.first {
            remove(first)
            let afterHidden = RainPlayer()
            results["removeBuiltInPersists"] = !afterHidden.tracks.contains { $0.id == first.id }
            restoreBuiltIns()
            results["restoreBuiltIns"] = tracks.contains { $0.id == first.id }
        }
        chosenSkin = oldSkin
        followsSound = oldFollow
        volume = oldVolume
        looping = oldLoop
        pause()
        if let first = tracks.first { select(first, autoplay: false) }
        seek(0)
        results["error"] = error ?? NSNull()
        let boolKeys = ["autoSkins", "manualSkin", "skinPersists", "allTracksPlay", "seek", "pauseStops", "loopsAtEnd", "sleepTimerPauses", "volume", "removeBuiltInPersists", "restoreBuiltIns"]
            + (fixture == nil ? [] : ["importTheme", "importThemePersists", "import", "managedCopy", "persistsAcrossLaunch", "importedPlays", "delete", "originalPreserved", "invalidFileRejected"])
        let passed = boolKeys.allSatisfy { results[$0] as? Bool == true } && error == nil
        results["passed"] = passed
        if let data = try? JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: reportPath))
        }
        exit(passed ? 0 : 1)
    }
}
