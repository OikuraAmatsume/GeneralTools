# InputSwitcher

一个极简的 macOS F13 输入法切换工具。程序监听全局 F13 按键，并向系统发送 `Control–空格`，实现类似 Mac 地球仪键的输入法切换效果。

## 要求

- macOS
- Apple Silicon Mac
- Xcode Command Line Tools（用于从源码构建）
- “系统设置 → 键盘 → 键盘快捷键 → 输入法”中的 `Control–空格` 已启用

## 构建与运行

```bash
./build.sh
./InputSwitcher
```

首次运行时，请在“系统设置 → 隐私与安全性”中为 `InputSwitcher` 开启：

- 辅助功能
- 输入监控（如果系统要求）

授权后重新启动程序。终端显示以下信息即代表监听已启动：

```text
F13 输入法切换已启动。按 Control-C 停止。
```

按 `Control-C` 可以退出。

## 工作方式

```text
F13 → 拦截按键 → 发送 Control–空格 → macOS 切换输入法
```

本工具只模拟地球仪键的“切换输入法”效果，不提供其他 Fn/地球仪组合键功能。
