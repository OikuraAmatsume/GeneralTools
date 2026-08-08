# Amatsume init

`Amatsume init` 是一个无主窗口、无 Dock 图标的 macOS 菜单栏应用。它监听 F13，并向 macOS 发送 `Control–空格`，实现输入法切换。

## 菜单栏功能

启动后，屏幕右上角会出现地球仪图标。单击或右键图标可以查看：

- 当前监听状态
- `F13 → 切换输入法`
- 使用的系统快捷键
- 辅助功能权限入口
- 软件版本号
- 退出按键

如果辅助功能权限尚未开启，图标会变成警告标志，并在授权完成后自动启动键盘监听。

## 构建

需要 macOS 13 或更高版本，以及 Xcode Command Line Tools。

```bash
./build.sh
```

生成的应用位于：

```text
build/Amatsume init.app
```

双击应用即可运行。由于这是本地临时签名版本，首次运行时请在“系统设置 → 隐私与安全性 → 辅助功能”中允许 `Amatsume init`。

同时确认“系统设置 → 键盘 → 键盘快捷键 → 输入法”中的 `Control–空格` 已启用。

## 工作方式

```text
F13 → Amatsume init → Control–空格 → macOS 切换输入法
```

本应用只实现地球仪键的输入法切换效果，不模拟其他 Fn/地球仪组合键。
