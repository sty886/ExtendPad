# MeowDisplay 2.0 — 云端交接

写于 2026-10-31，本地开发的收尾阶段。本地工作到此为止；剩余工作通过仓库现有的发布流程在云端执行（不另建第二条流水线）。

## 仓库与版本

- 仓库：`raiseCatError/meowdisplay`（OpenDisplay 的 fork；GPL；保留署名与 fork 关系——见 README、REFERENCE.md 及 `reference/opendisplay` 分支）。
- 分支：`feature/v2-hotspot-parity`（已为云端推送）。SHA 即本文件推送时的提交；最终报告会给出。`release/2.0.0` **没有**从本地推送。
- GitHub 上的默认分支：仍为 `dev/opendisplay-next`。分支模型与发布规则：BRANCHING.md、RELEASE.md、RELEASE_ASSETS.md、REFERENCE.md。

## 架构（先读）

ARCHITECTURE.md（整体）、PROTOCOL.md（线上协议；§6.10 附录涵盖窗口模式、台前调度、Add to Stage、调度中心）、WINDOW_MODE.md、MULTI_DEVICE.md、RECEIVER_INPUT.md、RECEIVER_CONTROLS.md、PARITY.md（Apple ↔ Android）、COMPATIBILITY.md、SECURITY.md。

| 部分 | 文件夹 | 目标 / 模块 |
|---|---|---|
| Mac 发送端（同时承载 Mac 接收端角色） | `Mac/` | `OpenSidecarMac`（macOS 14+） |
| Mac 接收端 | `MacReceiver/` | `OpenSidecarMacReceiver` |
| iPhone 与 iPad 接收端（同一个 App） | `iOS/`、`Shared/` | `OpenSidecariOS`（iOS 16.4+） |
| Android 接收端 | `AndroidReceiver/`（`core`、`app`） | minSdk 29、targetSdk 36 |
| 测试 | `MacTests/`、`iOSUITests/`、`AndroidReceiver/*/src/test` | `OpenSidecarMacTests`、`OpenSidecariOSUITests` |
| 原型（未发布） | `Prototypes/CrashSafeShield` | 独立隔离；见下文隐私护盾 |

Xcode 项目是生成的：编辑 `project.yml`，然后运行 `./generate.sh`。Mac 测试目标逐个列出它要编译的 `Mac/` 和 `Shared/` 文件。

## 工具链

Xcode 27.1（27A9269）、Swift 6 语言模式、macOS 27 SDK。Android：AGP 9.4.1、Kotlin 2.4.21、JDK 17。Sparkle（Mac 更新）、swift-certificates、swift-crypto 通过 SwiftPM。

## 构建与测试

```sh
# Mac unit tests (covers Shared/ logic used by iOS too)
xcodebuild test -project MeowDisplay.xcodeproj -scheme OpenSidecarMac -destination 'platform=macOS' -only-testing:OpenSidecarMacTests
# iOS build (device)
xcodebuild build -project MeowDisplay.xcodeproj -scheme OpenSidecariOS -destination 'generic/platform=iOS'
# Android
cd AndroidReceiver && ./gradlew :core:test :app:testDebugUnitTest :app:assembleDebug
```

CI：`.github/workflows/tests.yml`；发布工作流 `release-*.yml`；参考同步 `reference-*.yml`；`repository-guard.yml`、`pr-title.yml`。

交接时的结果（2026-10-31）：完整 Mac 单元测试套件在 63c3c46 上运行 2461 项，0 失败，2 跳过；在 70d3507（仅 App 栏）上 StagePeekDockLayoutTests 5/5，Android 998/998（2 跳过）；iOS 真机构建与 Mac 发送端/接收端构建均成功。

为最终物理检查安装的版本（原地安装，保留数据和配对）：Mac Dev cdeda71（此后 Mac 代码未变）、iPhone 与 iPad iOS 2000061（9b8ba92）、Moto debug 70d3507（此后 Android 代码未变）。实时 UI 测试（`iOSUITests/LiveStabilizationTests`）需要一台已配对的 Mac 和一台设备，不在 CI 中运行。

## 2.0 中的功能及其状态

完成矩阵是事实来源，其中“已实现 / 已自动化 / 已物理检查 / 可发布”四类状态分开记录：`handoff-2.0/COMPLETION-MATRIX.md`（脱敏副本；原件和证据文件夹位于所有者的本地集成文件夹中）。自上次云端评审以来的重点：

- iPhone、iPad 和 Android 上的窗口模式（窗格、标签页、自由旋转、每窗格触控板光标、台前调度处理、作为“展开布局”设置的空间总览 / 画廊）。
- 仅查看：选择窗格、平移和缩放都在本地完成；原本发给 Mac 的触摸不会离开设备，并在所选窗格内显示“请求控制”（沿用现有请求流程，不重放该触摸）。
- 调度中心：窗格暂停且不重启；设备显示“Mac 上已打开调度中心。视频已暂停。”，其中一个窗格提供“退出调度中心”（仅限控制；Mac 在按下 Escape 前会重新检查）。检测细节：PROTOCOL.md §6.10 附录。
- 采集代理（`Mac/CoalescingFetch.swift`、`Mac/ShareableContentBroker.swift`）：每个时刻只有一个共享、有界、可取消的 ScreenCaptureKit 内容请求，并带启动跟踪。
- 仅对已配对设备可见的 Mac 用户名和短 Mac ID，用于区分同名 Mac。
- 远程文件：“存储到设备”把照片和视频放入“照片”（iOS 仅添加权限）或相册（Android，图片/影片 ▸ MeowDisplay），其余文件放入“文件” ▸“在我的 iPhone/iPad 上” ▸ MeowDisplay ▸ 下载（Android：下载 ▸ MeowDisplay），并提示存放位置。“共享”会打开系统共享面板。
- 台前预览 App 栏（iPhone/iPad）：滚动时变宽；下拉（或点按把手）先展开四行带名称的 App，再展开整个屏幕（停在“展开”和“关闭”按钮上方，此时这些按钮会把它缩小；无需从屏幕底边滑动）；在把手上向上滑动可收起；选择某个 App 后关闭。搜索会过滤 App 栏（Android 的 App 行也一样）。在展开视图中点按空白处可关闭。
- 未构建：摄像头模式 / 麦克风模式（所有者暂缓）。剪贴板不在本版本清单内。可增宽的 App 栏尚未在 Android 上提供。

## 已完成的物理 QA（所有者的设备，2026-10-29 … 31）

Mac（macOS 27）搭配 iPhone 14 Pro Max、iPad（第 9 代）和 Moto G5S Plus（LineageOS，无 Google Play 服务）：连接与视频；镜像、扩展和窗口启动；混合模式下同时连接两个接收端；隐私护盾的遮盖/移除与 Touch ID 移除；窗格选择与内联“请求控制”；在连接一个和两个接收端时用键盘打开/关闭调度中心。

iPad（第 9 代，iPadOS 27.0.1），所有者于 2026-10-31 在最终构建上手动验证：窗口模式、窗格选择、缩放、平移、每标签页旋转、空间总览与旋转、仅查看胶囊 → 批准 → 输入、调度中心暂停/恢复及带控制权退出调度中心、iPad + Moto 同时连接、镜像与扩展、滚动、台前预览拖拽、“共享”与“存储到设备”。该轮发现的七个失败均已修复并复检（handoff-2.0/COMPLETION-MATRIX.md，“iPad QA 2026-10-31”），包括 iOS 上的“存储”崩溃和 Android 上的会话结束崩溃。

未手动完成：TalkBack（Moto 上没有）、VoiceOver 走查及 VoiceOver/Voice Control 声明、更大字体、调度中心期间的隐私护盾遮盖。

## 已知限制

- **台前调度**：其侧边条中的窗口会被 macOS 暂停。窗格会提示这一点，并提供“在 Mac 上显示”/“关闭台前调度”（所有者制作的快捷指令）。添加到当前舞台已实现但从不提供：macOS 27 会确认该辅助功能操作，却不移动窗口。
- **调度中心**：打开期间 macOS 会暂停窗口采集；没有公开 API 报告这一状态，因此检测依赖公开窗口列表加辅助功能确认。
- **扩展启动时间 / AltTab**：AltTab 10.x 在 macOS 26/27 上会冲击 macOS 采集服务（replayd）（alt-tab-macos#5861），导致扩展启动耗时 19–61 秒。没有它时：镜像约 0.15 秒，扩展 0.7–2.4 秒，窗口 1–4 秒。代理把 MeowDisplay 的未完成请求限制在最多两个。调查结果：`handoff-2.0/EXTEND-START-ALTTAB-FINDINGS.md`。

## 隐私护盾

威胁模型：设备连接期间，身处 Mac 前的人不得看到或使用它；所有者用登录密码或 Touch ID 移除护盾。护盾通过代理的内容列表把自己排除在采集之外。遮盖期间退出会先锁定 Mac。
崩溃安全设计（用一个进程外守护者，确保崩溃时 Mac 不会裸露）**仅为原型**（`Prototypes/CrashSafeShield`，9 项测试；未安装常驻助手）：`handoff-2.0/PRIVACY-SHIELD-CRASH-SAFE-DESIGN.md`。安装助手需要所有者批准。

## 品牌

在所有人能看到名称的地方，App 都显示 MeowDisplay（MeowDisplay、MeowDisplay Dev、MeowDisplay Receiver）。旧的 OpenSidecar/OpenDisplay 名称只保留在内部使用或作为兼容性契约之处：Xcode target 与 scheme（`OpenSidecarMac`、`OpenSidecariOS`、`OpenSidecarMacReceiver`）、Swift 类型与文件名、Bonjour 服务类型（`_opensidecar._tcp`、`_opendisplay-pair._tcp`、`_opendisplay-mac-pair._tcp`）、钥匙串标签、HKDF salt、日志文件名，以及对 OpenDisplay 的 GPL 署名。详情与原因：`handoff-2.0/BRANDING-AUDIT.md`。

## 签名、公证与商店

签名与发布机制由现有流水线负责：RELEASE.md、RELEASE_ASSETS.md、`.github/release-config.json`、`scripts/release/`、`fastlane/`（Appfile、Fastfile、Matchfile、APP_STORE_LISTING.md、APP_REVIEW.md、PLAY_STORE_LISTING.md）。辅助功能声明：`handoff-2.0/STORE-ACCESSIBILITY.md`（只声明已经验证的内容）。关于 GitHub 上实际配置（环境、规则集、密钥名称、缺口）的只读审计总结见下一节。

## 发布流水线现状（只读审计，2026-10-31）

BRANCHING.md / RELEASE.md 中的分支模型已在文档中定义，但**尚未在 GitHub 上应用**：

- 默认分支仍是 `dev/opendisplay-next`。尚无远程 `dev`、`reference/opendisplay` 或 `release-state`。唯一的发布分支是 `release/app-store-rc`（未受保护）。
- `main` 仍保留上游项目的目录树及其继承的 `release.yml`（release-please）和 `pages.yml`。存在 `release-please--branches--main` 分支。默认分支还有一个遗留的 `app-store-candidate.yml`。应停用这些，不要扩展它们。
- 已应用的规则集：只有两个旧的（"Protect Main Branch"、"Protect development branch"）。`.github/rulesets/` 中的规则集未应用。
- 环境：无。发布工作流期望 release-build、ios-upload、android-upload、release-stores、release-publish、release-pr 和 website-update。
- 仓库中已有的密钥：DEVELOPMENT_TEAM、MATCH_DEPLOY_KEY、MATCH_GIT_URL、SPARKLE_PRIVATE_KEY。缺失：
  - MATCH_PASSWORD
  - APP_STORE_CONNECT_* 系列密钥
  - ANDROID_UPLOAD_* 系列密钥
  - PLAY_SERVICE_ACCOUNT_JSON
  - RELEASE_APP_PRIVATE_KEY
  - WEBSITE_APP_PRIVATE_KEY

  未设置任何仓库变量。
- `release-*`、`reference-*` 和 guard 工作流尚未出现在默认分支上，因此无法手动触发。
- `.github/release-config.json` 中 `publishMode` 为 "manual-final-approval"（第 2 行），`crossPlatformReady` 为 false（第 3 行），`android.reviewTrack` 为 "production"（第 17 行；必须先改为 beta 轨道）。

应用文档中的模型需要所有者批准：默认分支、规则集、环境和密钥。这是启用现有流水线，而不是新建第二条。

## 云端任务（修订版）

只通过现有分支、工作流和经评审的 PR 开展工作。绝不为了让某项内容通过而削弱门禁；应停下来并报告。

- **A. 只读审计。** 对照仓库重新核实本交接：构建、运行所有测试套件、检查 entitlement、隐私清单、required-reason API、许可证/署名、历史中的密钥以及发布配置。产出发现；不做任何改动。
- **B. 带测试的修复。** 在 `feature/v2-hotspot-parity`（或从其切出的分支）上修复 A 发现的问题，每个修复都配测试，并按 BRANCHING.md 通过 PR 合入 `dev`。
- **C. `release/2.0.0`** 由现有经评审的 PR 流程（release-pr / candidate 工作流）创建，不手动创建。
- **D. 商店与分发暂存，不正式上线：**
  - Apple：以**手动发布**方式提交 2.0.0 审核（不自动发布）。
  - Google Play：仅将 AAB 上传到**内部或封闭 beta 轨道**。把发布配置中的 `android.reviewTrack=production` 改为 beta 优先。
  - Mac：公证后的 DMG、Sparkle 签名和校验和**暂存**，不标记为 Latest，也不在 appcast 中上线。
  - 在不削弱任何门禁的前提下，使 `publishMode=manual-final-approval` 和 `crossPlatformReady=false` 与上述安排一致。
- **E. README 与网站改版**仅在暂存分支/预览中进行。
- **F. 公开发布前停止。** App Store 发布、Play 正式版、Mac Latest 发布和网站上线均由所有者最终批准。

## 云端运行前或期间所有者需执行的操作

- 批准或拒绝崩溃安全的隐私护盾助手（目前仅为原型）。
- 对 47 个已复核的分支删除给出许可（带 SHA 的列表在本地集成报告中；会话的安全检查阻止了执行）。
- 提供或确认审计列为缺失的发布密钥/环境。
