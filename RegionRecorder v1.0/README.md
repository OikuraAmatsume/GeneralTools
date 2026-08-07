# 本地区域录屏（macOS）

[日本語版 README](README_JA.md)

一个完全本地、无主窗口的原生 macOS 区域录屏工具。应用只在菜单栏显示图标，所有录制命令都由**右键点击菜单栏图标**触发。

## 构建与运行

- macOS 14 或更高版本
- Xcode 15 或更高版本（项目已用 Xcode 26.6 验证）
- 打开 `RegionRecorder.xcodeproj`，选择 `RegionRecorder` scheme 后运行
- 第一次录制时，在系统提示中授予“屏幕与系统音频录制”权限；应用不申请麦克风权限

### macOS 26 开发签名与屏幕录制权限

屏幕录制授权会绑定到应用的代码签名身份。首次运行前，请在 Xcode 中选择 `RegionRecorder` target → **Signing & Capabilities** → **Team**，选中你的 Personal Team 或开发团队，让 Debug 构建使用稳定的 **Apple Development** 证书。没有 Team 时 Xcode 会使用 ad-hoc（`-`）签名；macOS 26 会在重建后把它视为另一个应用，权限可能不显示或无法保留。

如果权限页没有显示本应用：

1. 先按上面步骤选择 Team，再重新 Build & Run。
2. 右键菜单栏图标并再次“开始录制”，让 ScreenCaptureKit 触发系统登记。
3. 仍未出现时，在权限页点左下角 `+`；应用提示中选择“在访达中显示应用”，再把该 `.app` 加入列表。
4. 开启开关后完全退出并重新打开应用。

也可在终端运行：

```sh
xcodebuild -project RegionRecorder.xcodeproj \
  -scheme RegionRecorder \
  -configuration Debug \
  -derivedDataPath /tmp/RegionRecorderDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## 使用方式

1. 右键菜单栏录制图标，选择“创建录制区域”。
2. 拖动蓝色边框细线可移动选区；拖动细线两侧的窄抓取带或四角可缩放。
3. 在菜单中选择 MP4/GIF、帧率和缩放比例。
4. 右键选择“録画を開始”。输出会自动保存到桌面的 `RegionRecorder` 文件夹。
5. 右键选择“録画を終了”。GIF 会在停止后本地转换，菜单会短暂显示“書き出し中…”。

导出完成后，应用会自动打开访达并选中刚生成的文件。文件名格式为 `RegionRecorder-yyyyMMdd-HHmmss.mp4` 或 `.gif`；同一秒内重名时会自动追加 `-2`、`-3`。

选区中心没有事件窗口，鼠标点击、双击、拖动、滚动及键盘焦点都会直接落到下方应用。录制期间选区几何会锁定，以保证 ScreenCaptureKit 的捕获矩形稳定；中心仍完全穿透。

## 实现要点

- `NSStatusItem` 只监听右键事件；没有传统主窗口或悬浮控制栏。
- 透明 `NSPanel` 绘制 2 pt 轮廓并忽略鼠标，8 个窄的透明边缘面板只负责移动/缩放；不会使用覆盖中心的事件遮罩。
- ScreenCaptureKit 使用显示器局部的点坐标作为 `sourceRect`，输出尺寸再按 Retina backing scale 与用户缩放比例转换为偶数像素。
- 捕获过滤器排除本应用的所有窗口，因此边框、菜单和提示不会进入结果。
- AVFoundation 仅创建 H.264 视频轨，不创建音频输入或音轨。
- GIF 先录制为无声的本地临时 MP4，再由 AVAssetReader + ImageIO 逐帧生成无限循环 GIF。
- 临时目录在导出成功或失败时清理；应用没有网络代码或网络 entitlement，隐私清单声明不跟踪、不收集数据。为无提示写入固定的桌面目录，应用不启用 App Sandbox。
- 支持在任意连接的显示器上创建选区。为保证不同显示器缩放比例下像素严格对齐，单次选区会被约束在一个显示器的可见区域内；拖到另一显示器后会自动切换显示器与 backing scale。

## 测试

`RegionRecorderTests` 覆盖：

- AppKit 左下原点到 ScreenCaptureKit 显示器局部左上原点的转换
- Retina 与输出缩放后的偶数像素尺寸
- 多显示器负坐标情况下的矩形计算
- 选区始终位于显示器可见区域（不覆盖菜单栏）
- 透明轮廓内部不命中、边缘命中
- 合成帧生成的 MP4 没有音轨，并可经正式导出管线转换为可解析、无限循环的 GIF

屏幕录制权限、真实鼠标穿透、MP4/GIF 播放以及物理 Retina/多显示器对齐属于系统集成测试，需要在本机运行应用完成。详见 `TESTING.md`。
