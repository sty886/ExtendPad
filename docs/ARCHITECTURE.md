# 架构

ExtendPad 把发送端 Mac 连接到 Android 和 Mac 接收端。Mac 始终采集并发送
视频/音频；接收端可以请求权限，通过已认证的会话回传输入。

```text
Mac sender                                  Android or Mac receiver
ScreenCaptureKit                            TLS listener
Virtual display / existing display          Pairing and session admission
Video/audio encoders       encrypted media  Decoders and presenters
Input injection           ◀───────────────  Approved input events
```

## 目标与模块

在 `project.yml` 中定义；`.xcodeproj` 由 XcodeGen 生成。

| 目标/模块 | 源文件 | 角色 |
| --- | --- | --- |
| `OpenSidecarMac` | `apps/macos/`、`packages/shared/`、部分 `apps/macos-receiver/` | Mac 共享，以及统一的接收端角色 |
| `OpenSidecarMacReceiver` | `apps/macos-receiver/`、`packages/shared/`、部分 Mac 工具 | 独立的 macOS 12+ 接收端 |
| `OpenSidecarMacTests` | `tests/macos/` 和部分生产源文件 | 无宿主 Mac 测试 |
| Android `core` | `apps/android/core/` | Kotlin/JVM 协议和接收端逻辑 |
| Android `app` | `apps/android/app/` | Android 集成和 Compose UI |

## Mac 发送端

- 会话与设备生命周期：`apps/macos/OpenSidecarMacApp.swift`
- 采集、编码、传输和输入：`apps/macos/MacSender.swift`
- 采集生命周期：`apps/macos/CaptureLifecycle.swift`
- 虚拟显示器隔离：`apps/macos/VirtualDisplay.swift`
- 显示器分配：`apps/macos/DisplayModeAssignment.swift`
- 输入授权与注入：`apps/macos/InputControlConsent.swift`、
  `apps/macos/InputInjector.swift`、`apps/macos/InputRouting.swift`
- Android USB：`apps/macos/AndroidUSB.swift` 和
  `apps/macos/USBTLSBridge.swift`（经授权的 ADB 隧道；Android 侧还承载
  AOA 配件通道，供能够完成配件切换的设备/固件使用——见
  TECHNICAL_NOTES.md）
- 网络传输：`apps/macos/MacSenderTransportController.swift`

Android USB 在正式发布路径上使用经授权的 ADB 隧道，作为不透明字节传输；
Android 还为能够完成配件切换的设备声明了一条 AOA 配件控制通道。AOA/ADB
绝不授予信任：常规的配对、固定身份和加密会话仍然适用。

## 共享 Swift 代码

`packages/shared/` 包含接收端核心和平台无关逻辑：

- `StreamReceiver.swift`：监听器、会话和控制分发
- `ReceiverPipelineActor.swift`：接收流水线的所有权
- `ReceiverVideoDecoder.swift` 和 `ReceiverAudioDecoder.swift`：解码
- `Protocol.swift`：线路消息和能力
- `Pairing.swift`、`PairingNetwork.swift`、`TrustStore.swift` 和
  `TLSConfigurator.swift`：配对与信任
- `SessionInvitation.swift`：准入与批准
- `PointerGestureEngine.swift`、`RemoteViewport.swift` 和控制模型：
  输入解释和接收端本地呈现

纯逻辑保持平台无关，因此 `tests/macos/` 无需应用宿主即可测试。

## Android

`apps/android/core/` 用 Kotlin 实现协议，并回放 `fixtures/` 中的共享
测试向量。`apps/android/app/` 集成 Android Keystore、DNS-SD、MediaCodec、
Compose、输入、USB 和设备自适应 UI。

## Mac 接收端

`apps/macos-receiver/` 提供 AppKit 外壳、视频窗口、设置、配对 UI 以及
键盘/触控板转发。主 Mac 目标复用其中的大部分内容，同时排除独立入口点和
bundle 资源。

## 安全与生命周期不变量

- 没有明文媒体回退，也没有基于路线的身份替换。
- 连接批准绝不意味着输入批准。
- 每个连接都要重新获得准入和输入权限。
- 采集生命周期与传输恢复保持分离。
- 只有目标会话拥有采集和输入注入状态。
- 协议变更遵循 [COMPATIBILITY.md](COMPATIBILITY.md) 和
  [PROTOCOL.md](PROTOCOL.md)。
- `project.yml` 是构建的唯一事实来源。

## 开发入口

| 变更 | 从这里开始 |
| --- | --- |
| Mac 会话/设备 | `apps/macos/OpenSidecarMacApp.swift` |
| 采集与串流 | `apps/macos/MacSender.swift` |
| 线路消息 | `packages/shared/Protocol.swift` |
| 接收端核心 | `packages/shared/StreamReceiver.swift` |
| Android 协议 | `apps/android/core/src/main/kotlin/` |
| Android UI | `apps/android/app/src/main/kotlin/` |
| Mac 输入转发 | `apps/macos-receiver/ReceiverInputForwarding.swift` |
| 测试 | `tests/macos/` 和每个 Android 模块的 `src/test/` |
| 构建目标 | `project.yml` |

参见 [SETUP.md](SETUP.md)、[PARITY.md](PARITY.md)、
[RECEIVER_CONTROLS.md](RECEIVER_CONTROLS.md) 和 [SECURITY.md](../SECURITY.md)。
