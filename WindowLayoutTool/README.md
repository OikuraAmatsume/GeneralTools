# 窗口布局工具（macOS）

这是一个纯原生、完全本地运行的 macOS 菜单栏窗口布局工具。它没有普通主窗口，不显示 Dock 图标，也不出现在 Command-Tab 中；唯一常驻入口是屏幕右上角菜单栏图标。拖动其他应用的可调整窗口时，布局选择条会在当前显示器可见区域自下而上约 1/3 高度处居中出现，将指针移入任一缩略分区并松开即可调整窗口。

## 系统与技术

- macOS 13 或更高版本
- Swift、AppKit、Core Graphics、macOS Accessibility API
- `LSUIElement = true`
- `NSStatusItem` 菜单栏入口
- `AXUIElementCopyElementAtPosition` 解析窗口
- `AXUIElementSetAttributeValue` 设置位置与大小
- `SMAppService.mainApp` 管理开机启动
- 无第三方依赖、无 WebView、无 JavaScript 运行时、无 helper/XPC/服务器
- App Sandbox 关闭；Hardened Runtime 开启

关闭 App Sandbox 是有意设计：辅助功能类应用需要通过公开的 Accessibility API 读取和控制其他进程窗口，而 App Sandbox 会限制这类跨进程控制。应用不注入进程、不使用私有 API，也不拦截、修改或重发鼠标事件。

## 使用

1. 将应用放入 `/Applications` 后启动。
2. 在菜单栏点击矩形分栏图标。
3. 授予“辅助功能”权限：系统设置 → 隐私与安全性 → 辅助功能。
4. 拖动普通应用窗口的标题栏、可调整边框或角落。
5. 窗口实际移动或缩放超过 7 pt 后，布局条才会出现。普通点击不会触发。
6. 将鼠标移到一个布局分区；蓝色表示当前选择。松开后当前窗口进入该分区。
7. 指针未选中分区时松开，或按 Escape，会取消本次布局操作。

菜单包含：启用/暂停、开机启动、布局功能、辅助功能权限状态、申请权限、打开系统权限设置、关于和退出。“开机启动”在开发构建或应用未放入 `/Applications` 时可能要求用户到“登录项”页面批准。

应用使用 `NSEvent.addGlobalMonitorForEvents` 被动监听鼠标，不使用默认 `CGEventTap`，也不吞掉或重放输入。全局 Escape 键监听依赖本应用本来就需要的辅助功能授权；正常情况下不需要单独授予输入监控权限。

## 内置布局

- 主窗口 + 右侧上下分区：65% 左侧、35% 右上、35% 右下
- 左右均分：50% / 50%
- 最大化：使用当前显示器 `visibleFrame`，不会进入原生全屏
- Large Left：65% / 35%

每个缩略图分区都可独立选择；工具只移动当前拖动的窗口，不会自动重新排列其他窗口。布局使用 0～1 归一化坐标，后续可直接添加三等分、四象限、上下分屏或间距策略。

## 实现要点

拖拽状态机为：

`Idle → PotentialDrag → ActiveDrag → HoveringLayout → Commit/Cancel → Idle`

- mouseDown 时只解析一次鼠标下最前面的 AX 窗口并缓存引用和初始 frame。
- 仅接受 `AXWindow/AXStandardWindow`，并排除本应用、Dock、菜单栏、通知中心、最小化、原生全屏、Sheet/Popover/弹窗、固定尺寸或 AX 属性不可写的窗口。
- 指针移动至少 7 pt 且 AX 位置或大小实际改变后才进入 ActiveDrag。
- ActiveDrag 期间悬停计算限制为最多 30 Hz；没有空闲高频 Timer、DisplayLink 或持续窗口枚举。
- 仅 ActiveDrag 使用 0.5 秒、容差 0.15 秒的低频看门狗，检查左键是否仍按下并设置 60 秒上限，处理 mouseUp 丢失。
- Space 切换、睡眠/唤醒、显示器配置变化、权限撤销、AX 失效或窗口关闭都会取消并隐藏浮层。
- 提交前再次检查权限、窗口有效性、position/size 可写性和 mouseUp 的命中区域。
- 设置 frame 后只做一次延迟读取验证，不重试；应用自身的最小尺寸或最终尺寸会被接受。
- 启动时只创建一个 `NSPanel`，后续反复使用。Panel 为 nonactivating、忽略鼠标、不抢焦点，可加入所有 Space，并支持全屏辅助层。
- 使用 `NSScreen.visibleFrame` 避开 Dock 和菜单栏；浮层跟随鼠标所在显示器。
- AppKit/AX 坐标通过主显示器顶部基线转换，支持左侧、右侧和上方的负坐标显示器，不假设屏幕原点为正数。
- 遵循“减少动态效果”和“减少透明度”系统设置。

主要源文件在 [`WindowLayoutTool/`](WindowLayoutTool/) 中，按 AppDelegate、菜单、权限、全局监听、状态机、AX 解析、窗口操作、坐标、布局和浮层职责拆分。

## 构建与测试

### 直接使用独立应用

无需安装或打开 Xcode。已生成的通用架构应用位于：

- `dist/WindowLayoutTool.app`：可直接双击运行，支持 Apple Silicon 与 Intel。
- `dist/WindowLayoutTool.dmg`：打开后把应用拖入 Applications 即可。

这是标准 macOS `APPL` 可执行应用，不是 Xcode 插件。因为 `LSUIElement = true`，启动后不会出现 Dock 图标或普通窗口，只会在菜单栏出现布局图标。当前 dist 副本使用 Hardened Runtime 的本地临时签名；在另一台 Mac 分发时，仍需按文末说明进行 Developer ID 签名和 Apple 公证。

### 从源码构建

在 Xcode 中打开：

```bash
open WindowLayoutTool.xcodeproj
```

命令行 Debug：

```bash
xcodebuild \
  -project WindowLayoutTool.xcodeproj \
  -scheme WindowLayoutTool \
  -configuration Debug \
  -derivedDataPath /tmp/WindowLayoutToolDebugDerived \
  build
```

命令行 Release：

```bash
xcodebuild \
  -project WindowLayoutTool.xcodeproj \
  -scheme WindowLayoutTool \
  -configuration Release \
  -derivedDataPath /tmp/WindowLayoutToolReleaseDerived \
  build
```

无签名身份时可加 `CODE_SIGNING_ALLOWED=NO` 只完成编译，或加 `CODE_SIGN_IDENTITY=-` 创建“Sign to Run Locally”的临时签名版本。测试：

```bash
xcodebuild \
  -project WindowLayoutTool.xcodeproj \
  -scheme WindowLayoutTool \
  -configuration Debug \
  -derivedDataPath /tmp/WindowLayoutToolDerived \
  CODE_SIGNING_ALLOWED=NO \
  test
```

首次换构建路径或签名后，macOS 可能把它视为新的辅助功能客户端；请重新授权。开发时最好固定 Derived Data 路径，发布时固定 bundle identifier 与 Developer ID 签名。

## 完全离线与隐私

- 不使用 URLSession、Network.framework、WebSocket 或任何网络客户端。
- 不包含统计、遥测、广告、远程配置、在线崩溃报告或自动更新。
- 不上传窗口标题、内容、应用名称或用户行为。
- 不截图、不 OCR，也不需要屏幕录制权限。
- 不申请摄像头、麦克风、文件目录或网络权限。
- AX 窗口引用与 frame 只在一次拖拽期间保留于内存，结束后释放。
- 仅“启用/暂停”和“布局功能”设置写入本机 UserDefaults。
- 源码没有 `NSLog`、`Logger` 或自定义诊断日志；默认不写运行日志。
- `PrivacyInfo.xcprivacy` 声明不跟踪、不收集数据，并说明 UserDefaults 的必要原因。

## 2026-08-10 实际验证结果

环境：Apple Silicon（M4）、macOS 26.5、Xcode 26.6、Swift 6.3.3；部署目标仍为 macOS 13.0。

自动验证：

- Debug build：通过。
- Release build：通过。
- Xcode Analyze：通过。
- XCTest：18 项通过、0 失败。覆盖布局归一化映射、底部/左侧/右侧 Dock 的 `visibleFrame`、浮层 1/3 高度定位与放大尺寸、负坐标与上方显示器、AppKit/AX 双向坐标、全部分区 hit testing、成功/取消/Escape/异常恢复及非法状态转换。
- `plutil`：Info.plist、entitlements、Privacy manifest 全部通过。
- 本地临时签名：`codesign --verify --deep --strict` 通过；CodeDirectory flags 包含 `adhoc,runtime`。未进行 Developer ID 签名或公证。
- 静态离线检查：Swift 源码中未发现 URLSession、Network.framework、WebSocket、Sparkle、Sentry、Firebase、telemetry 或 analytics 使用；唯一 `http://` 是 Apple plist DTD 声明，不会产生请求。
- 实际启动：Release 应用成功保持运行，7 秒检查期间运行日志文件为 0 字节。
- DMG 脚本：实际生成 143,751 字节的 UDZO/zlib 只读测试镜像，`hdiutil imageinfo` 成功识别。
- 空闲 CPU：5 次、每秒一次的 `ps` 采样均为 0.0%。
- 内存：`ps` RSS 为 52.6～52.7 MB（包含共享映射）；系统 `footprint` 报告 `phys_footprint` 与峰值均为 14 MB。
- 网络：运行期间 `lsof -nP -a -p <pid> -i` 没有返回网络套接字。

人工矩阵：本机存在 Finder、Safari、Chrome、Xcode 和 Electron/Cursor；Microsoft Office 未安装。由于辅助功能授权是安全敏感的系统设置，本次自动执行没有替用户点击授权，因此未把 Finder/Safari/Chrome/Electron/Xcode 的真实窗口拖放、多显示器、不同 Space、缩放比例或物理断网环境标记为已通过。`computer-use` 对无普通窗口的 LSUIElement 进程无法读取状态（超时）；测试清单保留在下方，必须在授权后人工完成，不能用上述自动测试代替。

人工发布前清单：

- Finder、Safari、Chrome、Electron 应用、Xcode 的标题栏拖动与边框/角落缩放。
- 如果安装了 Microsoft Office，验证 Word/Excel/PowerPoint。
- 单显示器和双显示器；显示器位于主屏左/右/上方；不同缩放比例。
- Dock 左/右/下、自动隐藏 Dock、刘海屏、不同 Space、原生全屏辅助层。
- 拖动中拔出显示器、切换 Space、睡眠/唤醒、撤销权限、关闭目标窗口、按 Escape 和故意丢失 mouseUp。
- 完全断网启动与拖动，并用 Activity Monitor/Network 或 `lsof` 再确认无连接。

## 已知限制

- 某些应用不公开可写的 AXPosition/AXSize、限制最小尺寸、使用非标准窗口角色或自行修改最终 frame；工具会安全取消或接受应用最终结果，不使用私有 API 绕过。
- 原生全屏窗口、最小化窗口、Sheet、Popover、系统弹窗和固定尺寸窗口不处理。
- macOS 的辅助功能授权与应用的路径/签名相关；频繁更换未签名开发构建可能需要重新授权。
- 全局 Escape 依赖辅助功能授权。如果企业安全策略禁止全局键盘监视，Escape 可能不可用，但 mouseUp、Space/睡眠/屏幕通知和 ActiveDrag 看门狗仍会清理浮层。
- 当前布局没有窗口间距和自定义布局编辑器。
- 开机启动使用 SMAppService；开发路径、临时签名或未放入 `/Applications` 的应用可能需要系统登录项页面人工批准。
- `LSUIElement` 菜单栏进程没有普通窗口，一些 UI 自动化工具无法直接枚举它。

## Developer ID、Apple 公证与 DMG

1. 在 Xcode 的 Signing & Capabilities 中选择 Developer ID Application 团队，保持 Hardened Runtime 开启、App Sandbox 关闭。
2. 创建归档：

```bash
xcodebuild archive \
  -project WindowLayoutTool.xcodeproj \
  -scheme WindowLayoutTool \
  -configuration Release \
  -archivePath build/WindowLayoutTool.xcarchive
```

3. 使用 Xcode Organizer 导出 “Developer ID” 应用，或使用包含 `method = developer-id` 的 ExportOptions.plist 执行 `xcodebuild -exportArchive`。
4. 验证签名：

```bash
codesign --verify --deep --strict --verbose=2 dist/WindowLayoutTool.app
codesign -dvvv dist/WindowLayoutTool.app
```

5. 创建 DMG（脚本只使用系统 `ditto`、`ln` 和 `hdiutil`）：

```bash
chmod +x Scripts/create_dmg.sh
Scripts/create_dmg.sh dist/WindowLayoutTool.app dist/WindowLayoutTool.dmg
```

6. 给 DMG 签名并提交公证：

```bash
codesign --force --timestamp \
  --sign "Developer ID Application: YOUR NAME (TEAMID)" \
  dist/WindowLayoutTool.dmg

xcrun notarytool submit dist/WindowLayoutTool.dmg \
  --keychain-profile "notary-profile" \
  --wait

xcrun stapler staple dist/WindowLayoutTool.dmg
xcrun stapler validate dist/WindowLayoutTool.dmg
spctl --assess --type open --context context:primary-signature -v dist/WindowLayoutTool.dmg
```

使用 `xcrun notarytool store-credentials` 预先把公证凭据存入钥匙串，不要把 Apple ID 密码、app-specific password 或 API 私钥提交到仓库。发布前还应在一台未授权的干净 macOS 13+ 机器上验证 Gatekeeper、辅助功能授权、开机启动和首次运行流程。
