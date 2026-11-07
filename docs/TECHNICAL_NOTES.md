# 技术说明

MeowDisplay 路线图背后的平台研究和架构约束。这不是营销页面——它是工作参考，说明了*为什么*某些路线图项目（无头支持、冷启动、远程唤醒）会以现在的方式设计，以及哪些外部先例影响了这种设计。

产品层面的概述见 [README.md](../README.md)。wire 协议见 [PROTOCOL.md](PROTOCOL.md)。

## macOS 采集与显示架构

MeowDisplay 的 Mac 发送端使用 **ScreenCaptureKit**（Apple 现代、公开且受支持的屏幕采集 API）进行采集，并用 **VideoToolbox** 将结果硬件编码为 H.264。两者都是公开 API，具有正常的 App Review / 分发状态——采集或编码路径没有任何私有内容。

真正*属于*私有的是首先创建虚拟显示；见下一节。

## 虚拟显示与 `CGVirtualDisplay`

要提供真正的**扩展**显示（而非镜像），Mac 发送端需要创建一个物理上不存在的显示器。Apple 目前没有公开、受支持的第三方 API 可以做到这一点。MeowDisplay 使用私有的 `CGVirtualDisplay` SPI 来实现——这与 BetterDisplay、DeskPad 等其他虚拟显示工具使用的技术相同。

这是有意且有意识的使用，而非意外：

- 私有 API 表面**隔离在代码库中的一个位置**（`Mac/VirtualDisplay.swift`），而不是散布在整个应用中，因此可以在不进行大范围重写的情况下替换。
- 私有 API 带有真实的兼容性和分发风险：Apple 可以不事先通知就更改或移除它们，其使用也是 Mac App Store 审查的一个因素（尽管在公证的直接分发中不是——那是 MeowDisplay 实际的近期目标——见 [README.md](../README.md#getting-started)）。
- 如果 Apple 有一天提供受支持的公开等效方案，MeowDisplay 应该并且会切换到它。

**背景说明，而非绕过它的方法：** Apple 自己的[屏幕共享功能](https://support.apple.com/en-in/guide/mac-help/-mh14066/mac)允许一台 Mac 通过网络查看并控制另一台 Mac 的屏幕，包括高性能模式。这是 Apple 能够在内部进行主机端虚拟显示工作的真实证据——这**不是**存在或即将出现用于等效主机虚拟显示创建的公开第三方 API 的证据。不要把前者理解为暗示后者。

## 睡眠/锁定与冷启动

这一区别很重要，而且容易被混淆，因此值得明确说明。

**当前/近期模型：** MeowDisplay 面向具有现有、**已登录 Aqua 用户会话**并进入睡眠或锁定的 Mac。唤醒、重新连接、采集恢复和远程输入都围绕*那个*生命周期构建和验证——一个已经存在并正在恢复的会话，而不是从无到有创建的会话。

**未来的不同问题：冷启动 / 完全登出访问。** 访问一台完全关机，或停在 LoginWindow 且无人登录的 Mac，在架构上是不同的——屏幕采集和输入注入都需要在 GUI 会话中运行，而处于该状态的机器还没有 GUI 会话。这**不是** MeowDisplay 首个公开 beta 所必需的。

一个 [Apple Developer Forums 帖子](https://developer.apple.com/forums/thread/814152)（一位开发者询问如何为远程支持工具采集 LoginWindow 屏幕，由 Apple DTS 工程师直接回答）在这里是有用的先例。根据该回答，所记录的形态是：

- **机器级 LaunchDaemon** 在全局系统会话中处理网络/编排——守护进程无法进行屏幕采集之类的 GUI 工作。
- **GUI 会话 LaunchAgent**（可通过 `LimitLoadToSessionType` 配置为在 `Aqua` 和/或 `LoginWindow` 会话中加载）执行实际的 ScreenCaptureKit 采集和输入注入，因为这必须发生在 GUI 会话内，而不是后台守护进程中。
- 两者通过 **XPC** 通信。
- 根据同一帖子，**LoginWindow** 会话中的 ScreenCaptureKit 采集从 **macOS 14.4** 开始才成为可能（更早版本在那里需要使用 `CGDisplayStream` 等旧 API）。

这被记录为未来冷启动架构的可能形态，而不是承诺按任何特定时间表构建它。

## 持久远程采集 / Apple 自身的能力

Apple 有一项受限的、需审批的 entitlement——[`com.apple.developer.persistent-content-capture`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.persistent-content-capture)——适用于需要持续采集内容（例如屏幕内容）的应用，包括普通屏幕录制权限授予无法覆盖的场景。开发者可以在 Apple 自己的[请求表单](https://developer.apple.com/contact/request/persistent-content-capture/)（需要登录，正如 Apple 的开发者请求表单通常那样）上申请它。

**MeowDisplay 目前不持有、也不声称持有该 entitlement 的批准。** 之所以记录在这里，是因为它与任何未来的持久/无人值守远程桌面工作直接相关——是一条值得了解的路径，而非今天正在使用的东西。

## 远程桌面隐私模型

另一个 [Apple Developer Forums 帖子](https://developer.apple.com/forums/thread/841530)涵盖了一个相关但更窄的问题：应用能否在不触发系统同意提示的情况下静默*检查* macOS 的“Remote Desktop”TCC（隐私）权限状态。根据该帖子中 Apple DTS 工程师的回复（截至该帖发布时）：目前没有公开 API 暴露该检查——`CGPreflightScreenCaptureAccess()` 只反映单独的“Screen & System Audio Recording”权限，而调用 ScreenCaptureKit 来查明会触发你正试图避免的那个同意弹窗。工程师的建议是提交一个增强请求（反馈编号 `FB24263354` 附在该特定帖子中）。

请将此视为某个论坛帖子在某一时间点的观察，而不是有文档记录的、有保证的平台行为——如果这将来需要被实际依赖，Apple 自己的文档才是权威。

## 远程 Wake-on-LAN

Wake-on-LAN 本质上是**本地链路层**行为：在 LAN 网段上广播的魔法包，由仍在监听的网络接口接收，即使机器其余部分已睡眠。*睡眠* Mac 上的 Tailscale（或类似叠加网络）链路本身并不是 LAN 硬件 WoL 那种常开监听器——Mac 必须先处于唤醒状态，其 Tailscale 节点才能被访问。因此“通过 Tailscale 向睡眠 Mac 发送 WoL 包”没有直接了当的实现：目标上没有已唤醒的进程来接收并处理叠加网络数据包。

如今远程唤醒在可行的场景中的实际形态，通常需要在**目标自己的 LAN 上有一个已唤醒的中继**：该网络上的其他东西——路由器功能或另一台常开设备——发送实际的链路层 WoL 广播，Mac 唤醒，*然后*其叠加网络链路恢复，MeowDisplay 才能连接。[AnyDesk 记录了同样的形态](https://support.anydesk.com/)用于其自己的 Wake-on-LAN 功能：它可以使用目标 LAN 上已有的另一个在线 AnyDesk 客户端/设备作为中继来发送唤醒包。（AnyDesk 具体的 Wake-on-LAN 帮助中心 URL 在撰写时无法解析为稳定页面——这里描述的是有文档记录的通用机制，仅作概念性参考，并非引用特定页面。）

面向 MeowDisplay 的集成式远程 WoL 中继/路由解决方案是**未来**工作，近期没有计划——见 [README.md](../README.md#roadmap)。

## 参考实现 / 相关研究

这些是为获取背景而查阅的架构参考——不是依赖项，也不表示 MeowDisplay 复制了它们的代码，或它们为 MeowDisplay 背书。

### RustDesk

[RustDesk](https://github.com/rustdesk) 是一个开源远程桌面项目，拥有真实世界的 macOS 无人值守访问部署经验。有用的参考：

- 一个 [GitHub 讨论](https://github.com/rustdesk/rustdesk/discussions/7762)，关于配置 macOS 客户端在启动时自动启动（包括在登录屏幕），以实现无人值守访问——LaunchDaemon/LaunchAgent 配置和权限要求。
- [macOS 平台源代码](https://github.com/rustdesk/rustdesk/blob/251e1a3487518f763e0bb2b7eafb505fbd75b56d/src/platform/macos.rs)（光标处理、屏幕录制权限检查、服务安装/卸载、显示分辨率控制、权限提升）。
- 一个 [wiki 页面](https://github.com/rustdesk/rustdesk/wiki/macOS-Auto%E2%80%90Start-Service-Setup-%28for-Remote---MDM-Deployment%29)，介绍基于脚本的方式，用于在无需用户交互的情况下为远程/MDM 部署注册服务。

有助于思考锁定会话/守护进程与 GUI 代理的差异；MeowDisplay 自身的架构和代码独立于它。

### AnyDesk

[AnyDesk](https://anydesk.com) 是一款商业远程桌面产品。上文引用了其通过 LAN 中继实现 Wake-on-LAN 的方法——这是一个有用的存在性证明，说明“同一 LAN 上的另一台在线设备中继唤醒包”是一种可行且已发布的模式，与 MeowDisplay 自身未来的实现无关。

<a id="usb-transport-aoa-versus-the-adb-tunnel-2026-11-07"></a>
## USB 传输：AOA 与 ADB 隧道（2026-11-07）

USB 只是一种**路由**：配对、固定双向 TLS 1.3 和 SPKI 信任与 LAN/Remote 相同。已发布的 Mac 传输使用授权的 ADB 隧道作为不透明字节（`apps/macos/AndroidUSB.swift`、`USBTLSBridge.swift`）。AOA（Android Open Accessory）传输消除了对 platform-tools/开发者选项的依赖，并已在 Android 侧实现（`USBAccess`、`USBAccessoryWire`、配件过滤器/manifest 条目），但 Mac 的 AOA 主机栈尚未发布。

在华为 MRX-W39（HarmonyOS 平板）上使用正确的主机端实现（`IOUSBHost` 和经典 `IOUSBLib` 都试过）测得：

- `GET_PROTOCOL` 返回 **2**（声明支持 AOA 2.0）。
- `SEND_STRING` 返回成功。
- `ACCESSORY_START` 返回成功，但设备从未重新枚举为 `18d1:2d00/2d01`；它保持在 `12d1:107e`。
- 尝试了仅充电、MTP 和 PTP USB 模式，有无 adb server，重新插拔之后，以及通过 IOUSBHost 和 IOUSBLib 两种方式。都没有配件枚举。

结论：固件接受 AOA 控制请求，但不执行配件切换。在有一台真正完成切换的设备可用于端到端验证之前，AOA 不能作为唯一的 USB 路径。Android 的 AOA 代码保留在配件连接之后；ADB 隧道仍然是此设备上的回退路径和发布路径。两条路径中的信任保持不变。
