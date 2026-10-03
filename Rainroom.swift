import SwiftUI
import AppKit

@main
struct RainroomApp: App {
    @StateObject private var player: RainPlayer
    init() {
        let p = RainPlayer()
        _player = StateObject(wrappedValue: p)
        if let i = CommandLine.arguments.firstIndex(of: "--self-test"), CommandLine.arguments.count > i + 1 {
            let report = CommandLine.arguments[i + 1]
            let fixture = CommandLine.arguments.count > i + 2 ? URL(fileURLWithPath: CommandLine.arguments[i + 2]) : nil
            Task { await p.selfTest(reportPath: report, fixture: fixture) }
        }
        NSApplication.shared.setActivationPolicy(.regular)
    }
    var body: some Scene {
        Window("雨间", id: "main") {
            ContentView().environmentObject(player)
                .frame(minWidth: 880, minHeight: 660)
                .preferredColorScheme(player.skin.isDark ? .dark : .light)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1040, height: 740)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("导入音频…") { player.chooseFiles() }
                    .keyboardShortcut("o", modifiers: .command).disabled(player.isImporting)
            }
            CommandMenu("播放") {
                Button(player.isPlaying ? "暂停" : "播放") { player.toggle() }.keyboardShortcut(" ", modifiers: [])
                Button("上一首") { player.stepTrack(-1) }.keyboardShortcut(.upArrow, modifiers: .command)
                Button("下一首") { player.stepTrack(1) }.keyboardShortcut(.downArrow, modifiers: .command)
                Button("后退 15 秒") { player.skip(-15) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("前进 15 秒") { player.skip(15) }.keyboardShortcut(.rightArrow, modifiers: .command)
                Toggle("循环播放", isOn: $player.looping).keyboardShortcut("l", modifiers: .command)
            }
        }
    }
}

struct CoverView: View {
    var track: NoiseTrack?
    var url: URL?
    var size: CGFloat
    private var background: Color {
        switch track?.category {
        case "海浪": Color(red: 0.18, green: 0.43, blue: 0.53)
        case "森林": Color(red: 0.23, green: 0.39, blue: 0.29)
        case "壁炉": Color(red: 0.45, green: 0.25, blue: 0.19)
        case "溪流": Color(red: 0.22, green: 0.42, blue: 0.40)
        default: Color(red: 0.17, green: 0.21, blue: 0.26)
        }
    }
    var body: some View {
        Group {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                background.overlay(Image(systemName: track?.symbol ?? "music.note")
                    .font(.system(size: size / 3)).foregroundStyle(.white))
            }
        }
        .frame(width: size, height: size).clipped()
        .clipShape(RoundedRectangle(cornerRadius: size > 100 ? 8 : 4))
    }
}

struct ContentView: View {
    @EnvironmentObject var player: RainPlayer
    @State private var library = false
    private var rose: Color { player.skin.accent }
    @State private var showSkin = false
    @State private var showSleep = false
    @State private var filter = "全部"
    @State private var trackToDelete: NoiseTrack?
    private var filteredTracks: [NoiseTrack] {
        player.tracks.filter { filter == "全部" || (filter == "内置声音" ? $0.builtIn : !$0.builtIn) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            if let notice = player.notice {
                                HStack {
                                    Label(notice, systemImage: "checkmark.circle")
                                        .font(.system(size: 12)).foregroundStyle(.secondary)
                                    Spacer()
                                    Button { player.notice = nil } label: { Image(systemName: "xmark") }
                                        .buttonStyle(.plain).help("关闭提示")
                                }
                            }
                            if library {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("你的声音收藏").font(.system(size: 28, weight: .bold))
                                    Text("\(player.tracks.count) 个声音 · 随时导入你喜欢的音频")
                                        .font(.system(size: 14)).foregroundStyle(.secondary)
                                    Picker("筛选", selection: $filter) {
                                        Text("全部").tag("全部")
                                        Text("内置声音").tag("内置声音")
                                        Text("已导入").tag("已导入")
                                    }.pickerStyle(.segmented).frame(width: 300).padding(.top, 4)
                                }
                            } else if let track = player.currentTrack {
                                hero(track)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("给房间添一点声音").font(.system(size: 28, weight: .bold))
                                    Text("导入本地音频，或恢复内置声音开始聆听。").foregroundStyle(.secondary)
                                }
                            }
                            trackList(library ? filteredTracks : player.tracks)
                            if player.hasHiddenBuiltIns {
                                Button("恢复内置声音") { player.restoreBuiltIns() }
                                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(rose)
                            }
                        }.padding(32)
                    }
                }.background(player.skin.canvas)
            }
            Divider()
            playbackBar
        }
        .tint(rose)
        .alert("播放出现问题", isPresented: Binding(get: { player.error != nil }, set: { if !$0 { player.error = nil } })) {
            Button("好") { player.error = nil }
        } message: { Text(player.error ?? "") }
        .alert("从资料库删除音频？", isPresented: Binding(get: { trackToDelete != nil }, set: { if !$0 { trackToDelete = nil } })) {
            Button("取消", role: .cancel) { trackToDelete = nil }
            Button("删除", role: .destructive) {
                if let track = trackToDelete { player.remove(track) }
                trackToDelete = nil
            }
        } message: {
            Text(trackToDelete?.builtIn == true
                ? "移除「\(trackToDelete?.title ?? "")」后，可以用「恢复内置声音」重新加入。"
                : "只删除雨间中的「\(trackToDelete?.title ?? "")」副本，你选择的原文件会保留。")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(library ? "资料库" : "现在聆听").font(.system(size: 16, weight: .semibold))
            Spacer()
            Button {
                library = true
                filter = "全部"
                player.chooseFiles()
            } label: {
                Label(player.isImporting ? "正在导入…" : "导入音频", systemImage: "plus")
                    .font(.system(size: 12))
            }.buttonStyle(.bordered).disabled(player.isImporting)
            Button { showSkin = true } label: {
                Label(player.skin.name, systemImage: "paintpalette")
                    .font(.system(size: 12))
            }.buttonStyle(.bordered).help("切换皮肤")
                .accessibilityLabel("换肤 " + player.skin.name)
                .popover(isPresented: $showSkin) { SkinPickerView().environmentObject(player) }
            Button { showSleep = true } label: {
                Label(player.sleepMinutes > 0 ? RainPlayer.time(player.sleepRemaining) : "睡眠定时", systemImage: "moon.zzz")
                    .font(.system(size: 12))
            }.buttonStyle(.bordered).popover(isPresented: $showSleep) { SleepView().environmentObject(player) }
        }.padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 22)
    }

    private func hero(_ track: NoiseTrack) -> some View {
        HStack(alignment: .center, spacing: 30) {
            CoverView(track: track, url: player.coverURL(for: track), size: 264)
            VStack(alignment: .leading, spacing: 12) {
                Text("雨间 · RAINROOM").font(.system(size: 11, weight: .bold)).tracking(2).foregroundStyle(rose)
                Text(track.title).font(.system(size: 30, weight: .bold)).minimumScaleFactor(0.65).lineLimit(2)
                Text(track.subtitle).font(.system(size: 17)).foregroundStyle(.secondary)
                Text("\(track.category) · \(RainPlayer.time(track.duration))")
                    .font(.system(size: 13)).foregroundStyle(rose)
                Text("让声音填满房间，\n给自己留一点安静的时间。")
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5).padding(.top, 6)
                HStack(spacing: 10) {
                    Button { player.toggle() } label: {
                        Label(player.isPlaying ? "暂停" : "播放", systemImage: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .semibold)).frame(width: 74)
                    }.buttonStyle(.borderedProminent).tint(rose).controlSize(.large)
                    Button { player.looping.toggle() } label: {
                        Image(systemName: "repeat").font(.system(size: 15)).frame(width: 22)
                    }.buttonStyle(.bordered).tint(player.looping ? rose : .gray).controlSize(.large)
                        .help(player.looping ? "关闭循环播放" : "开启循环播放")
                        .accessibilityLabel(player.looping ? "关闭循环播放" : "开启循环播放")
                }.padding(.top, 5)
            }
            Spacer(minLength: 0)
        }
    }

    private func trackList(_ tracks: [NoiseTrack]) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("曲目").frame(maxWidth: .infinity, alignment: .leading)
                Text("时长").frame(width: 68, alignment: .trailing).padding(.trailing, 72)
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            if tracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note.list").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(filter == "已导入" ? "还没有导入音频" : "这里还没有声音").font(.system(size: 14))
                    Button("导入音频…") { player.chooseFiles() }
                        .buttonStyle(.bordered).disabled(player.isImporting)
                }.frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                ForEach(tracks) { track in
                    trackRow(track)
                    Divider()
                }
            }
        }
    }

    private func trackRow(_ track: NoiseTrack) -> some View {
        let active = track.id == player.selectedID
        return HStack(spacing: 12) {
            Button {
                player.select(track)
            } label: {
                HStack(spacing: 13) {
                    CoverView(track: track, url: player.coverURL(for: track), size: 40)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(track.title).font(.system(size: 14, weight: active ? .semibold : .medium))
                            .lineLimit(1).foregroundStyle(active ? rose : .primary)
                        Text(track.builtIn ? track.subtitle : "已导入 · " + track.category)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("选择 \(track.title)")
            Text(RainPlayer.time(track.duration)).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
            Button { player.playTrack(track) } label: {
                Image(systemName: active && player.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
            }.buttonStyle(.plain).foregroundStyle(rose)
                .help(active && player.isPlaying ? "暂停" : "播放 \(track.title)")
                .accessibilityLabel(active && player.isPlaying ? "暂停 \(track.title)" : "播放 \(track.title)")
            Button { trackToDelete = track } label: {
                Image(systemName: "trash").frame(width: 20)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .help("从资料库删除 \(track.title)").accessibilityLabel("删除 \(track.title)").disabled(player.isImporting)
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .background(active ? rose.opacity(0.055) : .clear)
            .contextMenu {
                Button("播放") { player.select(track, autoplay: true) }
                if !track.builtIn {
                    Menu("声音主题") {
                        ForEach(RainSkin.allCases) { theme in
                            Button(theme.category) { player.setTheme(theme, for: track) }
                        }
                    }
                }
                Button("删除", role: .destructive) { trackToDelete = track }
            }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "cloud.rain.fill").foregroundStyle(rose).font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text("雨间").font(.system(size: 23, weight: .bold))
                    Text("RAINROOM").font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(.secondary)
                }
            }.padding(.top, 49).padding(.bottom, 34)
            Text("聆听").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.bottom, 10)
            nav("现在聆听", icon: "play.circle", selected: !library) { library = false }
            nav("资料库", icon: "square.stack", selected: library) { library = true }
            Text("你的声音").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 30).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(player.tracks) { track in
                        Button {
                            player.select(track)
                            library = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: track.symbol).foregroundStyle(rose).frame(width: 18)
                                Text(track.title).lineLimit(1)
                                Spacer(minLength: 0)
                                if track.id == player.selectedID && player.isPlaying {
                                    Image(systemName: "waveform").foregroundStyle(rose)
                                }
                            }.font(.system(size: 13)).padding(.vertical, 9).padding(.horizontal, 10)
                        }.buttonStyle(.plain).accessibilityLabel("聆听 \(track.title)")
                    }
                }
            }.frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 8) {
                Text(player.isPlaying ? "正在播放" : "准备好，慢下来")
                    .font(.system(size: 12, weight: .medium))
                Text(player.sleepMinutes > 0 ? "将在 \(RainPlayer.time(player.sleepRemaining)) 后暂停" : "本地播放 · 无需联网")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.vertical, 20)
            Divider()
            Button { NSApplication.shared.terminate(nil) } label: {
                Label("退出雨间", systemImage: "power").font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14)
            }.buttonStyle(.plain).help("退出 App（⌘Q）")
        }.padding(.horizontal, 20).frame(width: 190).background(player.skin.sidebar)
    }

    private func nav(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) { Image(systemName: icon).frame(width: 18); Text(title); Spacer() }
                .font(.system(size: 14, weight: selected ? .medium : .regular)).padding(.horizontal, 10).padding(.vertical, 10)
                .foregroundStyle(selected ? rose : Color.primary)
                .background(selected ? rose.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }

    private var playbackBar: some View {
        HStack(spacing: 24) {
            HStack(spacing: 12) {
                CoverView(track: player.currentTrack, url: player.currentTrack.flatMap { player.coverURL(for: $0) }, size: 54)
                VStack(alignment: .leading, spacing: 5) {
                    Text(player.currentTrack?.title ?? "尚未选择音频").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(player.currentTrack?.category ?? "导入音频开始聆听").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(width: 205, alignment: .leading)
            VStack(spacing: 8) {
                HStack(spacing: 19) {
                    Button { player.stepTrack(-1) } label: { Image(systemName: "backward.end.fill").font(.system(size: 14)) }.help("上一首")
                    Button { player.skip(-15) } label: { Image(systemName: "gobackward.15").font(.system(size: 19)) }.help("后退 15 秒")
                    Button { player.toggle() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 25)).frame(width: 32, height: 28)
                    }.help("播放 / 暂停（空格）").accessibilityLabel(player.isPlaying ? "暂停" : "播放")
                    Button { player.skip(15) } label: { Image(systemName: "goforward.15").font(.system(size: 19)) }.help("前进 15 秒")
                    Button { player.stepTrack(1) } label: { Image(systemName: "forward.end.fill").font(.system(size: 14)) }.help("下一首")
                    Button { player.looping.toggle() } label: {
                        Image(systemName: "repeat").font(.system(size: 15)).foregroundStyle(player.looping ? rose : .secondary)
                    }.help(player.looping ? "关闭循环播放" : "开启循环播放")
                }.buttonStyle(.plain).disabled(player.currentTrack == nil)
                HStack(spacing: 8) {
                    Text(RainPlayer.time(player.position)).frame(width: 49, alignment: .trailing)
                    Slider(value: Binding(get: { player.position }, set: { player.seek($0) }), in: 0...max(player.duration, 1))
                        .controlSize(.small).accessibilityLabel("播放进度").disabled(player.currentTrack == nil)
                    Text(RainPlayer.time(player.duration)).frame(width: 49, alignment: .leading)
                }.font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                Image(systemName: player.volume <= 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").foregroundStyle(.secondary)
                Slider(value: $player.volume, in: 0...1).controlSize(.small).accessibilityLabel("音量")
            }.frame(width: 133)
        }.padding(.horizontal, 24).padding(.vertical, 20).background(player.skin.footer)
    }
}

struct SleepView: View {
    @EnvironmentObject var player: RainPlayer
    private var rose: Color { player.skin.accent }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Label("睡眠定时", systemImage: "moon.zzz").font(.system(size: 16, weight: .semibold))
            Text("到时自动暂停播放").font(.system(size: 12)).foregroundStyle(.secondary)
            ForEach([0, 15, 30, 45, 60, 90, 120], id: \.self) { minutes in
                Button { player.setSleep(minutes) } label: {
                    HStack {
                        Text(minutes == 0 ? "关闭定时" : "\(minutes) 分钟")
                        Spacer()
                        if player.sleepMinutes == minutes { Image(systemName: "checkmark").foregroundStyle(rose) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if player.sleepMinutes > 0 {
                Divider()
                Text("剩余 \(RainPlayer.time(player.sleepRemaining))").font(.system(size: 12)).monospacedDigit().foregroundStyle(rose)
            }
        }.padding(22).frame(width: 200)
    }
}
