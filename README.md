<div align="center">

<img src="assets/readme/website/mark.png" alt="ExtendPad 标志" width="128">

# ExtendPad

**把 Android 设备或另一台 Mac 用作你的 Mac 的扩展显示屏。**

镜像或扩展桌面、排列各个 Mac 窗口，并用触摸、触控板、鼠标和键盘控制 Mac。
连接方式包括本地 Wi-Fi、经授权的 Android USB 隧道，或你掌控的私有网络。

[设置](docs/SETUP.md) · [架构](docs/ARCHITECTURE.md) ·
[安全](SECURITY.md) · [支持](SUPPORT.md)

</div>

<a id="platform-availability--november-2-2026"></a>

## 支持的平台

| 角色 | 平台 |
| --- | --- |
| 共享与接收 | macOS 14 或更高版本的 Mac |
| 仅接收 | macOS 12 或更高版本的 Mac |
| 接收端 | Android 10 或更高版本 |
| 共享（可选，非 CI 覆盖） | Linux X11，见 [`apps/linux/`](apps/linux/README.md) |

ExtendPad 不提供 Windows 发送端。macOS 发送端是主要实现；本分支另外附带
一个可选的 Linux（X11）发送端（`apps/linux/`，Go 实现，可打成 .deb），
用于把 Linux 桌面或服务器画面显示到平板，详见其 README。

## 功能

- **镜像：** 串流 Mac 现有的一块物理显示器。
- **扩展：** 创建一块独立的虚拟显示器，并在 macOS 中安排它的位置。
- **窗口：** 把选中的 Mac 窗口作为可独立排列的磁贴显示。
- **输入：** 直接触控、触控板式控制、键盘、鼠标和常见 Mac 手势，均受 Mac
  所有者的每会话权限限制。
- **控制：** Android 手机、平板和折叠屏上可自定义的控制托盘、快捷键、
  配置文件和自适应布局。
- **文件与剪贴板：** 经所有者批准的远程访达访问，以及 Android 上可选的
  统一剪贴板。
- **音频：** 串流 Mac 系统音频，并可调节音画同步。
- **连接：** 本地 Wi-Fi、经授权 ADB 隧道的 Android USB，以及通过
  Tailscale 等私有网络的远程访问。
- **安全：** 显式配对、固定对端身份和加密会话，无需托管中继。

平台差异和验证边界见 [PARITY.md](docs/PARITY.md)。

<a id="getting-started"></a>

## 从源码构建

### Mac

安装 `.xcode-version` 中指定的 Xcode 版本和 XcodeGen，然后运行：

```sh
./generate.sh
xcodebuild -project ExtendPad.xcodeproj \
  -scheme OpenSidecarMac \
  -configuration Debug \
  -derivedDataPath build/macos build
```

如需本地签名，请在生成工程前把 `DEVELOPMENT_TEAM` 写入 `.env`。打开
`ExtendPad.xcodeproj` 可运行主应用或 `OpenSidecarMacReceiver` scheme。
`project.yml` 是唯一事实来源；不要编辑生成的工程。

### Android

安装 JDK 17 和 Android SDK，然后运行：

```sh
cd apps/android
./gradlew :core:test :app:testDebugUnitTest :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

USB 设置、测试和发布选项见 [apps/android/README.md](apps/android/README.md)。

## 连接

1. 在 Mac 和 Android 设备或接收 Mac 上打开 ExtendPad。
2. 使用本地 Wi-Fi、Android USB，或已配置的私有网络路线。
3. 在两台设备上确认相同的配对码。
4. 选择镜像、扩展或窗口。
5. 在发送端 Mac 授予“屏幕录制”权限。如需远程控制，还要授予“辅助功能”、
   开启“允许输入”，并批准接收端的请求。

Android USB 需要 Android SDK platform-tools、USB 调试和已授权的连接。
ADB 只传输不透明的加密字节；它不替代配对，也不注入输入。

## 仓库结构

- `apps/android/` — Android 应用和 Kotlin core 模块
- `apps/macos/` — Mac 发送端和统一的 Mac 应用
- `apps/macos-receiver/` — 独立的 Mac 接收端
- `packages/shared/` — 共享的 Swift 协议和接收端逻辑
- `tests/macos/` — Mac 单元和集成测试
- `fixtures/` — 跨语言测试向量
- `assets/` — 品牌和文档资源
- `docs/` — 设置、架构、协议和发布文档
- `src/`、`public/`、`tools/` — 项目网站

<a id="roadmap"></a>

## 文档

- [设置与故障排除](docs/SETUP.md)
- [架构](docs/ARCHITECTURE.md)
- [协议](docs/PROTOCOL.md) 与 [兼容性](docs/COMPATIBILITY.md)
- [窗口模式](docs/WINDOW_MODE.md)
- [接收端控制](docs/RECEIVER_CONTROLS.md)
- [安全模型](SECURITY.md)
- [贡献指南](CONTRIBUTING.md)
- [发布流程](docs/RELEASE.md)

## 贡献与许可

欢迎贡献代码和设备兼容性报告。开发分支请基于 `dev`，并遵循
[CONTRIBUTING.md](CONTRIBUTING.md)。安全漏洞请通过 GitHub 的私密漏洞
报告流程提交。

ExtendPad 采用 [GPL-3.0](LICENSE) 许可。它包含 Philip Poloczek 的
OpenDisplay 工作，并保留其署名和许可义务。请仅在你拥有或获授权访问的
设备上使用。
