# MeowDisplay 2.0 品牌审计

范围：在 Swift、Kotlin、xcstrings、strings、Info.plists、project.yml、Android res、HTML/TSX 站点源码、脚本和文档中，不区分大小写搜索 opensidecar、opendisplay、oldsidecar、"open sidecar" 和 "open display"。

## 结果

已没有任何用户可见界面显示过时的产品名，因此无需修改源码。替换数：0（Mac 0、iOS 0、Android 0）。由于没有任何改动，本次审计未触发重新构建或测试。

已经正确的界面：
- 显示名称：BUNDLE_DISPLAY_NAME 为 MeowDisplay、MeowDisplay Dev、MeowDisplay Receiver、MeowDisplay Receiver Dev（project.yml）；iOS CFBundleDisplayName 为 MeowDisplay。
- 权限文案：NSLocalNetworkUsageDescription（Mac、Receiver、iOS）和 NSFaceIDUsageDescription 都写明 MeowDisplay（project.yml）。
- Android：app_name 为 MeowDisplay（res/values/strings.xml）；任何 strings.xml 中都没有旧名称。
- Mac/MacReceiver/iOS 的 .xcstrings：只有 "Open Displays…" 命中。它是一个普通短语（打开“显示器”设置页），不是产品名。保留。
- 公开网站（index.html、public/privacy.html、src/App.tsx）：MeowDisplay 品牌；提及 OpenDisplay 之处属于 GPL/上游署名（第 4 类）。

## 保留的旧引用

### (2) 内部符号 / 文件 / target 名称（未来可考虑清理）
- Xcode target、scheme、测试 target 和 Swift 类型：OpenSidecarMac、OpenSidecariOS、OpenSidecarMacReceiver、OpenSidecarMacTests、OpenSidecariOSUITests（project.yml、.github/workflows/tests.yml、run.sh）。
- 源文件：Mac/OpenSidecarMacApp.swift、iOS/OpenSidecarPhoneApp.swift、MacReceiver/OpenSidecarMacReceiverApp.swift、Mac/OpenSidecarMac-Bridging-Header.h、*.entitlements 文件名。
- 提及这些文件/类型的源码注释（Shared/StreamReceiver.swift、Shared/RemoteViewport.swift、Shared/ScrollMomentum.swift、Shared/PointerGestureEngine.swift、Shared/ReceiverAudioDecoder.swift、Mac/*.swift、MacReceiver/MacReceiver.swift、iOS/ReceiverControls.swift、Android ReceiverSurfaceInput.kt 与 RemoteViewport.kt 的注释）。
- 按这些路径读取源文件的 MacTests（OwnerAuthTests、PairingSessionTests、PlaintextMediaRemovalTests、UnifiedMacAppTests、SparkleConfigurationTests、PrivacyManifestTests）。
- Shared/MobileSettingsSearch.swift 中的搜索关键词 "sidecar" 指 Apple 的 Sidecar 功能，不是我们的旧名称。
- 重命名风险：改动量大；会破坏 CI 的 scheme 名称、按路径读取源码的测试以及发布工具。若要做，应作为一次专门的改动完成。

### (3) 持久化 / 协议 / 兼容性标识符（保留）
- Bonjour：_opensidecar._tcp、_opendisplay-pair._tcp、_opendisplay-mac-pair._tcp（Shared/StreamReceiver.swift、Mac/OpenSidecarMacApp.swift、MacReceiver/Info.plist、project.yml 的 NSBonjourServices ×3、Android discovery/Bonjour.kt 及其测试）。
- 钥匙串标签/服务：com.opendisplay.identity.v1、com.opendisplay.trust.v1；HKDF salt/info："OpenDisplay-TLS-Pairing-v1"、"OpenDisplay pairing v13"、"OpenDisplay-Pairing-Transcript-v13"（Shared/Protocol.swift、Shared/Pairing.swift、Android Pairing.kt、PinnedTls.kt）。修改这些会破坏配对与信任。
- 日志名称：Mac/Log.swift 的 baseName "opendisplay"；iOS/Log.swift 的 opensidecar-phone.log 和 "[opensidecar]" 日志标签（工具依赖它们）。
- 脚本/CI：.github/、scripts/reference/ 以及 reference/opendisplay 分支名。

### (4) 历史 / 署名（保留）
CHANGELOG.md、REFERENCE.md、PROTOCOL.md、BRANCHING.md、ARCHITECTURE.md、COMPATIBILITY.md、SETUP.md、README.md、CONTRIBUTING.md、TERMINOLOGY.md、UNIFIED_MAC_APP.md、RELEASE.md、SAME_MAC_SESSIONS.md、MULTI_DEVICE.md、CLOUD-HANDOFF-2.0.md、launch/*.md、AndroidReceiver/RECEIVER_CONTROLS.md；index.html、public/privacy.html、src/App.tsx 中的 GPL 署名；src/App.tsx 中的第三方兼容性链接。

## 旧 URL
- 上游仓库与 issue 链接（peetzweg/opendisplay、第三方 opendisplay-android/-linux 仓库）：署名/兼容性引用，保留。
- opendisplay.app 仅出现在记录其移除的注释中（index.html、public/privacy.html、public/robots.txt）、作为历史出现在 COMPATIBILITY.md 中，以及作为被阻止的上游主机出现在 SparkleConfigurationTests 中。没有用户可见的链接指向它。

## 未来可选的重命名
1. 把 target/scheme/类型/文件改为 MeowDisplay*：高风险，涉及 CI 和测试。
2. Bonjour 类型和钥匙串/HKDF 标签：会破坏跨版本与跨平台互操作；只能在提升协议版本并迁移后进行。
3. 日志文件名：风险低，但应先更新工具。


## 后续检查（主会话，2026-10-31）

- Mac App：`CFBundleName`（菜单栏、关于）已经是 "MeowDisplay Dev" / "MeowDisplay Receiver Dev"（来自 PRODUCT_NAME）；发布构建使用发布产品名。
- iOS/iPadOS：`CFBundleName` 原为 `$(PRODUCT_NAME)` = "OpenSidecariOS"，会显示在某些系统 UI 中（例如 iPad App 在 Mac 上运行时的菜单栏）。现在 iOS/Info.plist 中为 "MeowDisplay"。它不是身份键：bundle ID、可执行文件名（OpenSidecariOS）、钥匙串、设置和配对均未变；iOS 上没有代码读取它。
- 共享诊断文件已命名为 "MeowDisplay-<device>-<time>.txt"。iOS 实时日志（Documents/opensidecar-phone.log）在“文件”中不可见（未启用文件共享），保持原样。
