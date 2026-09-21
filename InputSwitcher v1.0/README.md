# Amatsume init

`Amatsume init` 是一个无主窗口、无 Dock 图标的 macOS 菜单栏应用。它可以：

- 监听 F13，并可选择“输入法切换”或直接切换到“简体中文”。
- 在 Finder 窗口空白处的右键菜单中加入“CMD here”。
- 通过 Finder 右键菜单中的“txt here”在当前目录新建空白 TXT 文件。
- 在 Finder 中按 `Command–V`，把剪贴板中的图片按当前时间戳保存到当前文件夹。
- 从菜单栏选择 Finder 默认打开的终端应用。

## 菜单栏功能

启动后，屏幕右上角会出现极简的“监听节点”图标。实心中心点表示监听正在运行，空心中心点表示尚未启动或需要权限。单击或右键图标可以查看：

- 当前监听状态
- `F13 功能`：输入法切换 / 简体中文
- Finder `Command–V` → 保存剪贴板图片
- Finder 扩展状态
- 默认终端选择
- Finder 扩展管理入口
- 辅助功能权限入口
- 软件版本号
- 退出按键

如果辅助功能权限尚未开启，图标会变成警告标志，并在授权完成后自动启动键盘监听。

在菜单栏图标 → “F13 功能”中选择：

- “输入法切换”：F13 会发送系统的 `Control–空格` 快捷键，在已启用的输入法之间切换。
- “简体中文”：F13 会直接选择系统的“简体拼音”输入源。

选择会自动保存，App 下次启动时继续使用上次的模式。“输入法切换”模式要求在“系统设置 → 键盘 → 键盘快捷键 → 输入法”中启用 `Control–空格`。

## Finder 功能

新版 App 内置 `AmatsumeFinderExtension`。启用后，在 Finder 当前文件夹的空白位置单击右键，选择“CMD here”，便会用设定的终端打开当前目录。该名称用于避开其他 Finder 扩展提供的同名“进入终端”菜单。

选择“txt here”会在当前文件夹创建空白的 `untitled.txt`。若文件已存在，则依次创建 `untitled 2.txt`、`untitled 3.txt`，不会覆盖已有文件。

当 Finder 位于前台且剪贴板包含图片时，按 `Command–V` 会把图片保存到当前 Finder 文件夹，文件名格式为 `yyyyMMdd_HHmmss_SSS.png`。如果剪贴板不是图片，Amatsume init 不会拦截快捷键，Finder 会继续执行原本的粘贴行为。

首次使用图片粘贴功能时，请允许 macOS 显示的“Amatsume init 控制 Finder”请求；该权限仅用于读取前台 Finder 窗口的当前目录。

菜单栏图标 → “默认终端”中会列出本机已安装的以下应用：

- Terminal
- iTerm2
- Warp
- Ghostty
- WezTerm

选择 iTerm2 时，App 会使用 iTerm2 的 AppleScript 接口新建窗口，并自动进入 Finder 当前目录。首次使用时，请允许 macOS 显示的“Amatsume init 控制 iTerm2”请求。

首次启动 1.1 版时，App 会打开 macOS 的 Finder 扩展管理界面。请启用“Amatsume init Finder 扩展”。也可以随时从菜单栏选择“管理 Finder 扩展…”重新打开该界面。

macOS 不允许应用静默启用 Finder 扩展，因此第一次必须由用户确认。启用后若菜单没有立即出现，请重新打开 Finder 窗口；必要时重新启动 Finder。

## 构建

需要 macOS 13 或更高版本，以及 Xcode Command Line Tools。

```bash
./build.sh
```

生成的应用位于：

```text
build/Amatsume init.app
```

双击应用即可运行。由于这是本地临时签名版本，首次运行时请：

1. 在“系统设置 → 隐私与安全性 → 辅助功能”中允许 `Amatsume init`。
2. 在 Finder 扩展管理界面中启用“Amatsume init Finder 扩展”。

重新构建会改变临时签名。如果 F13 权限失效，请先从辅助功能列表移除旧条目，再重新添加当前构建的 App。

使用“简体中文”模式时，请确认已在“系统设置 → 键盘 → 文本输入 → 编辑”中添加“简体拼音”。

## 工作方式

```text
F13 → Amatsume init → Control–空格 → 切换输入法
                    ↳ 系统输入源 API → 简体拼音

Finder 空白处右键 → Finder Sync 扩展 → Amatsume init → 默认终端 + 当前目录

Finder + Command–V + 图片剪贴板 → 当前目录/时间戳.png
```

本应用只实现 F13 的输入法切换功能，不模拟其他 Fn/地球仪组合键。
