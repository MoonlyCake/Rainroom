# 雨间 Rainroom

原生 macOS 白噪音播放器，界面参考 Apple Music 的侧栏与底部播放器。

- 导入本地音频，管理副本并保存资料库。
- 雷雨夜、海岸、林间、炉边、山溪五套皮肤，可跟随声音主题或固定选择。
- 播放定位、单曲循环、音量、睡眠定时和退出按钮。

## 构建

要求 Apple Silicon、macOS 14+ 和 Xcode Command Line Tools。

    chmod +x build.sh
    ./build.sh
    open build/雨间.app

公开仓库不包含第三方音频或视频封面。构建后点击“导入音频”添加自己的文件；右键音轨可设置声音主题。

已有完整本地应用的用户也可复用其资源：

    ./build.sh "/Applications/雨间.app/Contents/Resources"

导入副本和资料库保存在 ~/Library/Application Support/Rainroom；删除副本会移入废纸篓，原文件保留。

SwiftUI + AppKit + AVFoundation，无额外运行时依赖。当前版本：1.2.0。
