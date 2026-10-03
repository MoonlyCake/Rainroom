import SwiftUI

enum RainSkin: String, CaseIterable, Identifiable, Codable, Sendable {
    case storm, ocean, forest, fire, stream
    var id: String { rawValue }
    var name: String {
        switch self {
        case .storm: "雷雨夜"
        case .ocean: "海岸"
        case .forest: "林间"
        case .fire: "炉边"
        case .stream: "山溪"
        }
    }
    var category: String {
        switch self {
        case .storm: "雷雨"
        case .ocean: "海浪"
        case .forest: "森林"
        case .fire: "壁炉"
        case .stream: "溪流"
        }
    }
    var detail: String {
        switch self {
        case .storm: "深蓝灰 · 雷雨"
        case .ocean: "雾白蓝 · 海浪"
        case .forest: "浅白绿 · 森林鸟鸣"
        case .fire: "暖米白 · 壁炉"
        case .stream: "清白青 · 溪流"
        }
    }
    var symbol: String {
        switch self {
        case .storm: "cloud.bolt.rain.fill"
        case .ocean: "water.waves"
        case .forest: "leaf.fill"
        case .fire: "flame.fill"
        case .stream: "drop.fill"
        }
    }
    var isDark: Bool { self == .storm }
    var accent: Color {
        switch self {
        case .storm: Color(hex: 0xA5C3DF)
        case .ocean: Color(hex: 0x246A84)
        case .forest: Color(hex: 0x486B3E)
        case .fire: Color(hex: 0xA5572C)
        case .stream: Color(hex: 0x257866)
        }
    }
    var canvas: Color {
        switch self {
        case .storm: Color(hex: 0x17202C)
        case .ocean: Color(hex: 0xFCFDFE)
        case .forest: Color(hex: 0xFCFDFB)
        case .fire: Color(hex: 0xFFFCF7)
        case .stream: Color(hex: 0xFCFEFD)
        }
    }
    var sidebar: Color {
        switch self {
        case .storm: Color(hex: 0x121A24)
        case .ocean: Color(hex: 0xECF3F7)
        case .forest: Color(hex: 0xEEF3EA)
        case .fire: Color(hex: 0xF7EDE1)
        case .stream: Color(hex: 0xEAF4F0)
        }
    }
    var footer: Color {
        switch self {
        case .storm: Color(hex: 0x1C2938)
        case .ocean: Color(hex: 0xF1F7FA)
        case .forest: Color(hex: 0xF4F8F0)
        case .fire: Color(hex: 0xFBF2E8)
        case .stream: Color(hex: 0xF0F8F4)
        }
    }
    static func matching(_ category: String) -> RainSkin? { allCases.first { $0.category == category } }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

struct SkinPickerView: View {
    @EnvironmentObject var player: RainPlayer
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("声音与皮肤").font(.system(size: 17, weight: .semibold))
            Toggle("跟随当前声音", isOn: $player.followsSound).toggleStyle(.switch)
                .font(.system(size: 13)).tint(player.skin.accent)
            Text(player.followsSound ? "切换声音时，自动换到对应皮肤。" : "已固定皮肤，切换声音时保持当前外观。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Divider()
            ForEach(RainSkin.allCases) { skin in
                Button {
                    player.chooseSkin(skin)
                } label: {
                    HStack(spacing: 13) {
                        skinPreview(skin)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(skin.name).font(.system(size: 13, weight: .semibold))
                            Text(skin.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if player.skin == skin { Image(systemName: "checkmark").foregroundStyle(player.skin.accent) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("皮肤 \(skin.name)")
            }
        }.padding(22).frame(width: 290)
            .preferredColorScheme(player.skin.isDark ? .dark : .light)
    }
    private func skinPreview(_ skin: RainSkin) -> some View {
        HStack(spacing: 0) {
            skin.sidebar.frame(width: 16)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(skin.accent).frame(width: 24, height: 13)
                skin.footer.frame(height: 7)
            }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity).background(skin.canvas)
        }.frame(width: 68, height: 45).clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.2), lineWidth: 0.5))
    }
}
