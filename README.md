# MacTV Native 0.9.5

支持 Apple Silicon（M4 等）和 Intel 的原生 macOS 大屏媒体中心，最低 macOS 14。

## 下载

从 [GitHub Releases](https://github.com/machauncy1/mactv-native/releases/latest) 下载 Universal ZIP，同时适用于 Apple Silicon 与 Intel。解压后将 `MacTV Native.app` 放入“应用程序”。Release 附带 `SHA256SUMS.txt` 供校验。

这是采用临时签名、尚未公证的实验版本，最低 macOS 14。Netflix 内嵌正片和 Intel 真机兼容性仍需实测。

## 首页

两排六张应用卡片：YouTube、Netflix、哔哩哔哩、本地影院、最近播放、控制中心。方向键选择，确定进入，返回后恢复应用焦点。左右不跨行，上下保持列；鼠标也可直接打开。

首页使用静态背景，没有海报预览、推荐片单、后台网页读取或封面下载。焦点通过卡片放大、边框和阴影显示；动画遵循系统减少动态效果设置。

## UP 主合集切换

下方“最新视频／各合集”是切换栏，左右停留即更新上方片单，不需要先按确定进入子页面。上键或确定进入视频行，确定播放，返回关闭面板。

提前读取相邻最多两组合集的首屏片单和封面；片单最多缓存 12 个路由，封面缓存最多 24 张／32 MB。不预播视频。快速左右连按取消过时读取，面板关闭停止预加载。缓存命中可直接展示；首次读取及未完成预热时仍取决于平台与网络。官方显示 0 个视频的合集直接显示“暂无视频”，不继续预加载。读取失败或超时结束加载并允许重试。

## 播放

- YouTube 使用官方电视页面；Netflix 使用官方网页内嵌入口。登录、广告、会员和地区限制由平台处理。Netflix 受保护正片播放尚未验证。
- 哔哩哔哩保留原生片单、搜索、扫码登录、清晰度、选集、UP 主作品及合集、自动下一集与返回取消倒计时。滚动接近片单末尾自动加载，刷新仅让变化的卡片淡入淡出。
- B 站播放中：确定或 M 暂停／继续，左右跳转 10 秒，下键打开选集，上键或菜单键打开底部控制栏。返回先收起控件，再回片单；主页键直接回 App 首页。
- 本地影片使用 AVFoundation 播放，优先使用 H.264/AAC MP4、MOV；支持进度、暂停和音量，不含第三方解码器、NAS 浏览或外挂字幕。
- 默认关闭可切换字幕和 B 站弹幕；画面本身压制的文字保留。

## 遥控器与控制中心

支持原 USB 接收器（VID 0x0406 / PID 0x0602），仅在 App 前台读取。首次使用在 macOS“隐私与安全性 → 输入监控”允许 MacTV Native，并重新打开 App。旧独占转发程序应保持停用，实体接收器待重新接入后验证。

键盘方向键与回车对应选择／确定，Esc 返回，Home 回首页，M 暂停／继续，F 切换全屏。控制中心只保留 Wi-Fi 入口，由系统设置承担网络连接。遵照要求，本轮未打开 Wi-Fi 设置或切换网络。

## 构建与验证

需要 macOS，以及包含 macOS 26 或更新 SDK 的 Xcode／命令行工具（用于编译原生玻璃材质 API）。v0.9.5 使用 macOS 27.2 SDK、Swift 6.4.2，以 Swift 5 语言模式构建；部署目标仍为 macOS 14。


```sh
bash scripts/build.sh
.build/MacTVNative-arm64 --self-test
arch -x86_64 .build/MacTVNative-x86_64 --self-test
node scripts/test-bilibili-adapter.cjs
node scripts/test-creator-adapter.cjs
```

产物 `dist/MacTV Native.app` 同时包含 arm64 和 x86_64。实验包采用临时签名，未公证；不需要关闭 Gatekeeper 或 SIP。Intel 仅完成 Rosetta 验证，实际 MBP、HDMI 音频与长期播放仍待真机测试。

品牌素材来源见 [Resources/Brand/sources.json](Resources/Brand/sources.json)，第三方品牌素材权利归各自权利人。
