<!-- 集成文件夹中 COMPLETION-MATRIX.md 的脱敏副本（2026-10-31）。本地路径和个人姓名已移除；原件与证据保存在集成文件夹中。 -->

# MeowDisplay 2.x 需求状态（2026-10-28，完成度检查）

> Android 对齐、USB 和 Tailscale 相关行已被 RECONCILIATION-2026-10-29.md 取代（依据代码阅读）。

COMPLETE = 已构建、已测试，并在有硬件的情况下确认可用 · PARTIAL = 可用但存在已指明的缺口 ·
MISSING = 未构建 · BLOCKED = 需要我们没有或不适合触碰的硬件/操作系统 · NOT VERIFIED = 已构建并通过单元测试，但从未端到端运行。
证据路径相对于本文件夹。提交位于 `feature/android-secure-core`。

| 需求 | 状态 | 证据 / 缺口 |
| --- | --- | --- |
| 镜像、扩展、窗口模式 | COMPLETE（Android），NOT VERIFIED（iOS、Mac 接收端真机） | Moto 上的 W10、W14；iOS 按规则不在设备上运行 |
| 每个接收端的源独立 | COMPLETE（单元 + 单接收端物理） | 每个接收端一个引擎；ReceiverOwnershipTests；未物理运行两个接收端同时连接 |
| 最多 3 个手机磁贴 | COMPLETE | Moto 3 个磁贴（W10/28），预设上限为 3（W14 p1） |
| 最多 9 个平板磁贴 | PARTIAL | 布局 + 容量已测试（Swift/Kotlin 向量、平板模拟器）；从未运行 9 路实时采集（无平板硬件）；预算优先给活动磁贴 |
| 吸附、交换、拖拽、分隔条调整 | COMPLETE（Android 物理），NOT VERIFIED（iOS UI） | W14 p1；已修复 28a1ed4 |
| 独立的 0/90/180/270 磁贴旋转 | COMPLETE | Moto 在 0 和 90 度点按位置精确（W10 探针日志） |
| 统一光标、悬停 vs 活动 vs Mac 焦点 | COMPLETE（Android） | 活动边框 + 胶囊，Mac 焦点不同时输入暂停（W10/25） |
| 安全的逐窗口输入路由 | COMPLETE | 按下即置顶、拖拽绑定到所属磁贴、键盘门控（373ff6e，测试） |
| 物理键盘/鼠标/触控板 | PARTIAL / BLOCKED | 所有平台均有代码 + 测试；Moto 未连接蓝牙/OTG 外设；iOS 设备不可触碰 |
| 三指长按总览 | COMPLETE（Android） | W10 |
| 可移动可折叠的窗口选择器 | COMPLETE（Android） | 轨道边缘位置持久化；把手不再遮挡磁贴胶囊（28a1ed4） |
| 无头 Mac | PARTIAL | 窗口模式使用任何现有显示器（包括扩展虚拟显示器）；没有显示器时会提示使用扩展。按设计不为每个磁贴创建虚拟显示器。未在无头状态下运行（没有这样的 Mac） |
| 台前调度与空间 | PARTIAL / BLOCKED | 可采集被覆盖窗口、其他空间和屏幕外窗口（W1）；此处台前调度已关闭（`GloballyEnabled=0`）且未切换；未运行全屏空间（会移动用户的屏幕） |
| Android 与 iPhone Duo 折叠屏布局 | COMPLETE（Android 模拟器），NOT VERIFIED（iPhone Duo） | Android 模拟器铰链（6d23b19）；iOS 铰链逻辑已单元测试；应要求跳过了 Duo 模拟器检查 |
| 一个工作区中的多台发送 Mac | PARTIAL | 每台 Mac 的布局和窗口标识（测试 W14）；尚未构建混合两台 Mac 磁贴的单一工作区；双 Mac 物理测试 BLOCKED |
| 多个 macOS 用户会话 | PARTIAL | 每个账户都是独立的发送端（SAME_MAC_SESSIONS.md）；在 macOS 上无法同时采集非活动会话 |
| 统一版与独立版 Mac 接收端 | NOT VERIFIED | 可构建；双 Mac QA BLOCKED |
| Android/iOS 功能对齐 | PARTIAL | Android 缺少编辑器、USB 和显示/推流设置；演示（213a0a5）和远程（60bb1e4）已完成 |
| 连接说明、术语、引导 | COMPLETE | TERMINOLOGY.md、Android 帮助与关于、iOS 如何连接（2640788、3b826f8） |
| Tailscale 发现、USB 传输 | PARTIAL | 所有接收端（包括 Android）都支持远程（Tailscale/VPN）（手动地址；按设计不枚举 tailnet）；USB 仍仅限 Apple |
| 安全发现与回归 | COMPLETE | F1/F2/F3 + 9 项评审发现；测试套件全绿 |
| 画中画（Android） | COMPLETE | 0ae4cd8，Moto |
| 性能叠层（Android） | COMPLETE | a1d7a64，Moto；它发现了在 381adce 中修复的解码器回退问题 |
| 负 A/V 偏移（Android） | COMPLETE | 37f43bd，Moto |
| 自定义布局编辑器、功能托盘组合键编辑器（Android） | MISSING | 大型 UI 功能；iOS 已有 |
| iOS 物理键盘/指针 | NOT VERIFIED | 代码在 f6b9904 中；设备不可触碰 |
| iOS 模拟器 UI 测试 | COMPLETE | iPhone 18 Pro 模拟器上 9/9（3 项需要重跑：负载下的时序问题） |
| iPhone/iPad 物理 QA | COMPLETE（2026-10-31） | iPhone 自 2026-10-29 起；iPad（第 9 代，iPadOS 27.0.1）由所有者在 2000053–2000058 上手动验证，见下文 "iPad QA 2026-10-31" |
| 双 Mac 与折叠屏物理 QA | BLOCKED（硬件） | 未运行 |
| 自然触控（直接触控默认） | COMPLETE | Swift+Kotlin 引擎、fixtures、窗口模式测试、iOS UI 10/10、Moto ADB QA（REPORT: Natural Touch）；未验证真人手指手感 |
| 台前预览窗口切换器（iOS + Android） | COMPLETE | 两个平台均已构建并测试；Moto ADB QA，以及在真机 iPhone 上针对实时 Mac、仅查看模式的 XCUITest（evidence/SP）。iPad 于 2026-10-31 手动验证（从台前预览拖拽、单一“取消”区域、固定工具栏、空间总览）。未验证：设备上的右边缘、TalkBack/VoiceOver 走查 |
| 整屏 ↔ 窗口视图切换 | COMPLETE | 完整桌面卡片、“切换到窗口视图？”提示（8 秒后自动隐藏）、设置 → 显示 镜像/扩展/窗口；Moto sp14–sp18 |
| 术语梳理（34 项经评审的修复） | COMPLETE | ff854da、3145db9、eb3caac；请求控制系列；设备上的 iPhone 演示测试；Moto 360 dp 设置页面无裁切（evidence/TERM） |
| 极简主页（iPhone + Android） | COMPLETE | 307dfb1、42f90cc、89030f3、36d8c1b、baf0f73；iPhone 真机截图 + Moto（包括 360 dp） |
| Android 远程设备 | COMPLETE（已通过远程授予请求控制：等待你的授权） | 敲门 + Mac 回拨、远程配对、保存的地址、有界恢复、诚实的路由标签。通过 LTE + Tailscale 实时运行：镜像 44 fps，窗口模式 + 台前预览 52 fps / 64 ms，音频正常流动，推流中途开/关 Wi-Fi（保持连接 / Mac 在 1.3 秒内重拨），Mac 重启恢复，断开连接会停止恢复，输入关闭时请求控制被正确拒绝。通过远程授予控制权、实时远程配对和“需要批准”仍需 Mac 侧操作 |
| 键盘上的输入条 | COMPLETE | iOS 辅助栏（d3a7469、45da72f），iPhone 真机 UI 测试；Android 栏（187681a），Moto 在真实键盘上的设备内预览（bd480c0）。未验证 iPad 浮动键盘 |
| 光标跟随（输入时缩放） | PARTIAL（已单元测试） | Mac AX 光标 → `textCaret` 消息 → 接收端（d3a7469、187681a）；Swift + Kotlin 测试和共享向量；未在实时 Mac 上运行（会向用户的 App 输入文字） |
| 隧道上的 Mac 敲门路由 | COMPLETE | 36a92fb + c104aa8：隧道敲门从源地址回拨；215 项路由/远程测试 + 完整套件 |

## 2026-10-30 — 当日简报（分支 `feature/v2-hotspot-parity`，仅本地，未推送）

状态词同上。"Unit" = Swift 和/或 Kotlin 测试通过；installed = 已安装到 iPhone + iPad（构建 2000032 = ca189eb），除非另有说明。Moto 和 Mac Dev App 为 d379a5a（上次安装时 Moto 未连接；此后 Mac 发送端无改动）。

| 需求（简报） | 状态 | 证据 / 缺口 |
| --- | --- | --- |
| A. 每窗格自由画布平移（任意边缘或角到中心，0.7x–8x，抬起后保持） | PARTIAL | a88a3b5；WorkspaceFreePanTests 6/6 + 共享工作区向量（Swift + Kotlin）。缺口：空白画布尚未与缺失视频区分绘制；无物理检查 |
| B1. 从台前预览将窗口和 App 拖到窗格 | PARTIAL（单元） | 从画廊、紧凑台前预览和空间总览拖窗口（75e5266、U3）。从轮播和搜索结果拖 App（b5bf4ba）：只有一个窗口时直接放入，多个时弹出选择器，没有时提示打开（需控制权），其第一个新窗口落在放置位置；`testAnAppDroppedOnAPanePlacesItsWindowOrAsks`。缺口：Launchpad 中的 App 无法拖拽（Launchpad 覆盖窗格）；无物理检查 |
| B2. 窗格中的标签组 | PARTIAL（单元） | 添加、切换（仅显示的标签页推流）、拖出以拆分、合并、移除此标签页 vs 在 Mac 上关闭窗口，这些原本已有。ca189eb 增加了每标签页旋转 / 适应-填充 / 缩放（随布局保存，旧记录仍可加载），以及沿自身标签拖拽重排；`testEachTabKeepsItsOwnViewAndTabsReorder`、Kotlin `WorkspaceTabsTest`。缺口：未检查“完整桌面”作为标签页；无物理检查 |
| B3. 在每个需要控制权的操作旁内联“请求控制” | NOT VERIFIED | 68cc73e（iOS）、e53759f（Android）、ccddbdf（侧边条/已关闭磁贴、远程 Finder 标题栏）；App 拖放对话框也会提供（b5bf4ba） |
| B4. 台前预览每次新打开时重置临时筛选 | NOT VERIFIED | 1d10689（iOS + Android） |
| B5. 浏览或开始拖拽绝不会把镜像/扩展切换到窗口模式 | COMPLETE（单元） | 只有完成的拖放或选择窗口才会请求窗口模式；`testStagePeekBrowsingChangesNothing…`、`testAWindowDroppedOnTheDesktopStartsWindowModeBesideIt` |
| 台前调度采集调查（公开 API + SkyLight 实验） | COMPLETE（研究） | RESEARCH-2026-10-30-stage-manager-capture-lab.md、evidence/SM-lab/。在 macOS 27.0 上没有任何方法能从侧边条返回真实窗口；App 中不使用私有 API |
| 从设备关闭台前调度 | NOT VERIFIED（等待所有者） | 8902a1b：运行所有者的两个快捷指令（"MeowDisplay Stage Manager Off/On"），等待 macOS 响应，失败时报告；StageManagerSwitchTests 4。需要先创建这两个快捷指令一次 |
| 侧边条窗口回到舞台后更快重启（2 秒） | COMPLETE（单元） | 8902a1b、WindowCaptureHealthTests |
| 隐私护盾（远程开启，本地默认关闭；用 Mac 自身键盘输入登录密码解锁；绝不出现在设备画面中） | NOT VERIFIED（等待所有者确认） | d060f8c、3324ad5（安全修复）、9965776；PrivacyShieldPolicyTests 7、Kotlin SessionProtocolTest。未在屏幕上检查：设备画面中没有遮盖层、其下的 App 未被节流、密码提示显示在其上方 |
| 空间总览 + 设置 ▸ 展开布局 | PARTIAL（单元） | 5f8bf47（共享排布，SpatialOverviewTests 5 + Kotlin 向量）、d379a5a（iOS + Android 视图、设置）。无物理检查 |
| 手机画廊每行两个窗口 | NOT VERIFIED（设备） | 5a5c562（共享规则 + 向量）。针对实时 Mac 的 iPhone UI 测试现在通过长按后拉动来打开台前预览（长按后抬起会关闭它）；其 15:25 的运行被跳过，因为 iPhone 未能在 30 秒内进入 Mac 上的窗口模式 |
| iOS 上的远程 Finder 存储 / 共享 | NOT VERIFIED | 60dd727 |
| iPad 冒烟测试 | DONE（2026-10-31） | 见下文 "iPad QA 2026-10-31" |

## 2026-10-30 晚间 — P0 连接、隐私护盾闪烁、台前调度设置、窗口 UI 打磨、清理、锁定 Mac

分支 feature/v2-hotspot-parity（本地，未推送）：ff74ca5、673445b、0fc5b2d、103ed8b、b604745、3a5b3c7。
已安装：Mac Dev App 103ed8b（~/Applications）；iPad iOS 2000036；iPhone 仍为 2000033（安装被拒绝："usage assertion"，手机锁屏？）；Moto 未连接。

| 项目 | 状态 | 已验证 | 未验证 / 受阻 |
|---|---|---|---|
| P0 iPhone 无法连接 | 已找到根因：macOS 本地网络隐私阻止 Dev App 的外拨（nehelper 按二进制 UUID 重新缓存；LaunchServices 副本过期）。修复：唯一 UUID（ebb37cf）、从 ~/Applications 运行、单一 LS 注册（交换脚本）、产品检测 + 设备提示（dc36bd2） | 于 15:57–16:08 连接并推流（AWDL，约 13 ms；窗口模式采集 2.0 秒，准入后首帧 2.4 秒） | 自 16:16 起每个新构建都会再次受阻：所有者需在系统设置 ▸ 本地网络中关闭/开启 MeowDisplay Dev。之后需重新检查镜像/扩展实时运行 + 重连 |
| P0 隐私护盾闪烁 | 已从 Mac 日志证实原因：会话集合清空时遮盖窗口被销毁，下一次欢迎时最多 3 秒后才重建；重连时暴露 0.1–13 秒。已修复（ff74ca5）：池化的持久遮盖窗口，保持到本地解锁（失败关闭），遮盖期间退出前先锁定屏幕 | PrivacyShieldPolicyTests 9/9 | **未做安全验证**：尚未进行物理显示器观察（需要所有者确认 + 可弃置桌面）；App 崩溃/被杀仍会暴露（需要独立的遮盖进程） |
| 安装两个快捷指令 | 文件已构建（is.workflow.actions.stagemanager.set、operation set、state off/on），用 `shortcuts sign --mode anyone` 签名，16:46 在“快捷指令”中打开 | 已签名（AEA1） | 等待所有者点按“添加快捷指令”；然后检查 `shortcuts list`；内容只能由所有者的导入预览验证（没有受支持的读取 API） |
| Mac 设置中的一键设置 | 已完成（673445b）：自动设置、仅设置缺失项、轮询 → 就绪、复制已标记项、在“快捷指令”中打开 | StageManagerSwitchTests 7/7 | 尚未在 App 中逐项点按验证（快捷指令待处理） |
| 接收端：添加到当前舞台 / 关闭 / 需要设置 | 已在 iPhone/iPad/Android 上完成（103ed8b）；Mac 对 AXWindowsIDs 包含该窗口的侧边条项使用 WindowManager 的 AXAddToStage | StageStripAccessTests；AX 只读检查显示 AXAddToStage + AXWindowsIDs | 在可弃置侧边条窗口上的物理运行需要所有者确认 |
| 从手机锁定 Mac | 已完成（ff74ca5）：PROTOCOL 6.16，需要控制权，真实锁定状态 | 单元测试（Mac、Kotlin）；构建 | 未运行（会锁定所有者的 Mac） |
| 清理旧 ID | 已完成 Mac 已知设备 + iOS 已配对 Mac（0fc5b2d） | KnownDeviceCleanupTests 2/2 | Android：未存储配对日期 → 后续处理 |
| 完整桌面默认镜像 | 已完成（ff74ca5）：Mac 全新默认 + Android 查看全屏 | 构建 | 实时检查 |
| 标签页菜单被裁切 | 已修复（b604745）：测量、放置在安全区、可滚动；内联“请求控制” | iOS 构建 | 设备截图 |
| 每标签页旋转 | 代码路径已端到端检查（请求旋转 → Mac TileContentTransform） | — | 需要在手机上实时复现（被本地网络阻止） |
| 等待/重连 | iOS/Android 上的加载指示器 + 减弱动态效果；Mac 上的 startupStep 计时（dc36bd2） | 构建 | 尚未加入接收端首帧显示计时 |
| 过期的“选择窗口” | 已修复（3a5b3c7）iOS + Android | 构建 | 设备检查 |
| 每 App 菜单栏跟随标签页 | 未开始 | — | — |

### 物理检查 17:12–17:40（所有者已确认；evidence/privacy-shield-2026-10-30/）
- 连接：所有者切换本地网络后，iPhone（2000036）于 17:14:42 连接（QUIC）；窗口采集在准入后 5.0 秒完成（其中 3.2 秒的间隔是进程首次视频编码：17:14:42.848 → 45.885；见下文）。
- 隐私护盾，**窗口层遮盖检查**（不是物理显示器验证）：用 WindowServer 屏幕窗口跟踪（约 105 Hz），并在遮盖层下放置可弃置的洋红色测试图案，在 100 秒内跨 3 次 iPhone App 重启和一次断开，发现遮盖窗口始终列在图案之上，0 个间隙；断开后遮盖保持（“保持遮盖直到解锁”）。阳性对照：所有者用密码解锁后（17:35:07），跟踪立即报告遮盖消失。列在其上方的只有 macOS 自身的锁屏和密码提示。这证明了什么：每次采样时窗口服务器都把遮盖窗口排在其他所有内容之上。它没有证明什么：面板实际显示的内容（采样之间的合成帧、显示器重配置、外接显示器或镜像路径）。**独立的物理显示器验证仍未完成**：在相同切换过程中，用肉眼或摄像头观察面板，或在外接显示器线缆上接采集设备。App 崩溃仍会暴露（见 DESIGN-2026-10-30-crash-safe-shield.md）。
- 快捷指令：两个都已安装（`shortcuts list`）；不打开编辑器无法读取内容。
- 锁定 Mac：发送 Control-Command-Q 后 Mac 在 0.43 秒内锁定，从会话的锁定状态回读确认。
- 添加到当前舞台：无效。对侧边条项调用 AXAddToStage 四次返回成功（护盾开/关、测试图案开/关；'MeowDisplay RC Test'、'All Shortcuts'），但窗口从未离开侧边条。App 会如实报告“失败”。需要另一种受支持的方式，或去掉该按钮。

### 17:40 之后（本地提交 41a3cbe … 28405df，未推送）

已安装：iPhone 与 iPad iOS 2000040（28405df）。Mac Dev App 仍为 103ed8b（新 Mac 代码未换入：每个新构建都可能再次触发本地网络隐私）。Moto 未连接。
回归：Mac 单元测试 2402 项，3 项失败，全部在 WorkspaceZoomTests（平移停在源边缘 / 缩放不足时的居中）。这些问题早于今天：它们与 a88a3b5 预期的自由画布平移相矛盾，且今天没有提交触碰该代码。Android core + app 单元测试 976/976。

| 项目 | 已完成 | 已验证 | 未验证 |
|---|---|---|---|
| 添加到当前舞台 | 生产环境中隐藏（41a3cbe）：仅当 `StageStripAccess.isAvailable` 时 Mac 才报告 `stageAddAvailable`；研究保留在 RESEARCH-2026-10-30-add-to-stage.md | 构建通过；接收端在没有该标志时隐藏按钮 | 进一步的 AXPress 实验需要所有者确认和可弃置窗口 |
| 在 Mac 上显示 + 关闭台前调度 | 已恢复并相邻显示（41a3cbe） | 构建 | 设备检查 |
| 每 App 菜单栏跟随标签页 | 每个菜单请求都带上窗格预期的 App；若顶层回复命名了另一个 App（上一个标签页的），则在 0.4 秒后重问，最多 3 次（a6d4523、32d71a1 iOS/Mac；5116572 Android） | AppMenuTests 2/2；AppMenuModelTest 3/3 | 在设备上观察标签页切换 |
| 窗格菜单适配 | 自然高度，仅当高于可用空间时才滚动（a6d4523） | iPhone 截图（evidence/rotate/） | — |
| 每标签页旋转 | 已在 iPhone 上复现并可用：`testRotatesAPaneOnTheLiveMac` 将完整桌面窗格旋转 90°，重置视图可恢复 | iPhone 上的实时 UI 测试（evidence/rotate/） | Android 设备（Moto 未连接） |
| 窗口模式启动停顿 | 原因：进程中的首个 VideoToolbox 编码器单独耗时 0.65–1.05 秒（首次启动时 3.0 秒）；后续编码器 0–4 ms，一个 HEVC 会话可为 H.264 预热。修复：启动 2 秒后创建并释放一个 64×64 编码器（fd0212d）。同时修复：完整桌面窗格在流尚不存在时（启动时间读为 0）被当作“停滞”重启，导致每次启动多花 ≥1 秒 | WindowCaptureHealthTests 8/8；独立计时脚本 | 在下次换入 Dev App 时计时。每次启动的剩余开销：音频载波流的 `startCapture` 0.8–2.1 秒，窗格不会等它 |
| Android 旧 Mac 条目 | 现在固定的记录会保存配对时间（同一次原子写入）；Mac 卡片中的“清理”会准确列出将删除的条目及日期。无日期的配对之间不做平台猜测：无日期条目比任何有日期条目都旧；完全没有日期时不提供清理（8cbab2f，另见 Shared/KnownDeviceCleanup） | PairedMacCleanupTest 3/3；KnownDeviceCleanupTests 3/3 | 在 Moto 上。现有 Android 固定记录无日期，因此只有再次配对某台 Mac 后才会出现“清理” |
| 隐私护盾的 OLED 保护 | 遮盖层保持黑色；其消息和“解锁”按钮每分钟移动到屏幕另一个九分之一区域，本地无输入 1 分钟后变暗，5 分钟后熄灭；本地鼠标或按键会立即恢复。适用于每个显示器（macOS 不会说明哪些面板是 OLED）（ad9be49） | PrivacyShieldPolicyTests 11/11；Mac App 构建 | 在屏幕上：需要换入 Dev App 并开启护盾（所有者已确认） |
| 崩溃安全护盾 | 仅设计：DESIGN-2026-10-30-crash-safe-shield.md | — | 未构建；没有特权助手 |

### 18:30 之后（本地提交 0ea6bc7 … b8b84fd，未推送）

已安装：Mac Dev App = b8b84fd（19:40，~/Applications；新的二进制 UUID，因此本地网络可能需要所有者再次切换）。iPhone = iOS 2000045（da6b6ed）；iPad = 2000044（a8d12da；2000045 的安装被拒绝，iPad 可能已锁定）。Moto 未连接。
回归（19:40，b8b84fd）：Mac 单元测试 2414 项，2 跳过，5 失败，均不在新代码中：4 项是仍在期待旧默认值的测试（自然触控、手机使用直接触控），1 项是真实问题：新的 iOS 屏幕常亮计时器使用了 `systemUptime`，这是隐私清单未声明的 required-reason API（PrivacyManifestTests 捕获）。两者均已在 a8d12da 中修复（改用 CACurrentMediaTime，与其余 iOS 代码一致）；这五项通过。Android core + app 983/983。

| 项目 | 已完成 | 已验证 | 未验证 |
|---|---|---|---|
| 隐私护盾崩溃 | 显示遮盖层时发生两次崩溃（18:38:42、18:39:03）：通知面板的 SwiftUI 宿主自行调整窗口大小，其高度在 33/34 pt 之间翻转，经过过多约束计算后 AppKit 抛出异常。现在所有护盾窗口都有固定尺寸；遮盖层是纯 AppKit 并放置消息（a97e13b） | 受监督运行 2 中无崩溃；PrivacyShieldPolicyTests | 崩溃报告保存在 evidence/privacy-shield-oled-2026-10-30/ |
| OLED 保护，受监督运行 2（18:52:09–18:58:11） | — | 两个显示器上均有遮盖；对“解锁”的脚本化（非物理）点击被忽略；+60.0 秒时变暗；消息每分钟移动（位置 1–5）；+90/+200/+330 秒的非物理指针移动没有产生任何变化；断开连接时遮盖保持；重新以镜像连接、再切到窗口模式时遮盖保持；+300 秒时熄灭；所有者触摸时变亮；用密码解锁 | 13,577 个样本，18:58:04.77 出现一个“间隙”，当时内置显示器关闭（18:58:04.136 合上盖子）：跟踪器使用了过期的显示器矩形，因此在那次重排期间无法检查 BenQ。所有者（19:50）：他们合上了盖子，BenQ“显示 Mac 显示的内容”。跟踪器应在每个样本重新读取显示器信息 |
| iOS 屏幕常亮 | 与 Android 一致：仅在前台观看 Mac 画面时保持常亮（镜像、扩展、窗口），重连时有 30 秒宽限；进入设置、主页、后台、连接失败时恢复自动锁定。设置 ▸ 通用 ▸ 推流时保持屏幕常亮（185fa54） | ScreenAwakePolicyTests | 在设备上观察 |
| 缩放测试 | 已更新为自由画布规格（0ea6bc7）；实现未变 | WorkspaceZoomTests 通过 | — |
| 输入默认值 | 直接触控样式为 Classic；手机默认触控板，iPad 和平板默认直接触控；schema 21 对现有安装应用一次（e9bbfb0） | InputDefaultsTests、ControlPreferencesJsonTest | 在设备上 |
| 每窗格触控板光标 | 在触控板模式下，光标位于聚焦窗格：始终绘制在该窗格（Mac 发送工作区指针，而不是其自身光标所在位置），绝不会滑入相邻窗格，首次从窗格中心开始，之后按窗格和标签页回到原位置；在缩放、平移、旋转和调整大小过程中保持位于窗口的同一点。另一个窗格通过获得焦点（其标签、触摸）来获取光标（d846d63） | WindowWorkspaceTargetingTests 27/27；在 iPhone 上实时验证（19:52–19:56，evidence/twist-cursor-2026-10-30/）：光标绘制在聚焦的完整桌面窗格中心；触摸 Chrome 窗格使其聚焦，光标跳到该窗格中心；旋转手势再次聚焦完整桌面，其光标回到原位并随窗格旋转 | 用手指移动：本次会话没有控制权（显示“请求控制”），因此未应用相对移动。iPad、Moto |
| 自由窗格旋转 | 两指可将窗格旋转到任意整数度；手指下的窗口点在旋转时保持在其下方；尺寸只随两指间距变化；8° 的扭转才会启动（捏合的手抖绝不会触发旋转）；开启吸附旋转时在直角处有磁吸（±5°）；即时旋转预览；菜单中的“旋转”跳到下一个直角。传输格式和保存的布局保持整数（c8923d1 Mac + iOS，b8b84fd Android） | WorkspaceFreeRotationTests 6/6（Mac）、WorkspaceFreeRotationTest 6/6（Android）；Android 983/983；在 iPhone 上实时验证：合成的 50° 两指扭转将完整桌面窗格旋转约 42°（8° 启动阈值），Mac 合成清晰；“重置视图”可恢复（testTwistTurnsAPaneAndTheTrackpadCursorShowsOnTheLiveMac） | 真人手指在玻璃上（手感、磁吸）；iPad；Moto |

### 所有者 20:05 反馈之后（本地提交 86092d3 … 03f1a38，未推送）

20:17 安装：Mac Dev App = 03f1a38（pid 64109）。iPhone 与 iPad = iOS 2000046（03f1a38）。Moto 未连接。
稍后：iPad = iOS 2000047（990375b，辅助功能）。安装时 iPhone 不可用，仍为 2000046。

| 项目 | 已完成 | 已验证 | 未验证 |
|---|---|---|---|
| 窗格显示“正在重连…（第 5 次）”、“Mac 已停止发送…点按重试” | 从 Mac 日志得出的原因：会话开始后，Mac 只保持“显示器常亮”断言 60 秒。在空闲 Mac 上（此处被护盾遮盖），显示器约 19:59 休眠，窗口服务器停止，每次采集（Chrome、Zed，然后是完整桌面）都获得零帧、重试后放弃。所有者在 20:01:00 触摸 Mac 后它们恢复。修复：有设备观看时保持显示器休眠断言（已准入、视频开启、未暂停），在暂停、断开和拆除时释放（c9af421）。桌面窗格上的“已在 Mac 上关闭”是内置显示器随盖子关闭而熄灭 | StreamingDisplayAwakeTests 2/2 | 在设备上进行长时间空闲会话 |
| 旋转或平移时预览倾斜 | 原因：即时预览移动的是整个窗格边界框的快照；对于已经处于非直角角度的窗格，边界框的空角（深色）被拖到背景上，形成倾斜的深色形状。现在快照会遮罩到窗口自身的四个角（iOS 用 CAShapeLayer，Android 用 clipPath）（86092d3） | WorkspaceFreeRotationTests（轮廓角） | 在设备上 |
| 设置中的台前调度 | 在窗口模式下，Mac 始终报告台前调度的开/关状态；设置 ▸ 输入会显示它，并提供“关闭”（需确认；窗口模式结束时 MeowDisplay 会重新开启）或“开启”（设备端的“开启”会取消该恢复），仅限控制；“设置”会说明 Mac 上的一次性配置（03f1a38）。Android 相同 | Mac 测试、Android WorkspaceWireTest；iOS 构建 | 在设备上 |
| 窗格中的触控板 | 所有者：可用 | 所有者，20:05 | — |
| 全方位辅助功能 | iOS（990375b）：Mac 画面是单个直接触控元素；为连接、重连/断开、请求控制和文件提供朗读；Voice Control 名称；可调整的窗格分隔条；定时提示在 VoiceOver 下保持显示；减弱动态效果使用淡入淡出；标题。Android（45db122）：TalkBack 标签、角色、状态、标题、朗读、48 dp 触控目标、文本换行。商店指引：STORE-ACCESSIBILITY-2026-10-30.md | 完整 Mac 套件 2416/0 失败；iOS 构建；Android 984/984 | 在设备上使用 VoiceOver、Voice Control 和 TalkBack（文档中有所有者的检查清单） |

### 2026-10-30 夜间（所有者 21:00 后的决定；提交 3c15edd … ef262ea，未推送）

已安装：Mac Dev = 7f8a0f1（+ 尚未换入的后续提交：009582f Touch ID、6f7e313 日志行）。
iPhone 与 iPad = iOS 2000048。Moto = debug 7f8a0f1。级别：**Impl** = 代码已合入；**Auto** = 自动化
测试；**Phys** = 在真机上观察；**Release** = 可发布。

| 项目 | Impl | Auto | Phys | Release |
|---|---|---|---|---|
| 观看时显示器保持唤醒：跨观看者计为一个断言；在最后一个观看者离开、发送端停止、屏幕录制被撤销、切换出去时释放（3c15edd） | yes | 6 项测试，包括真实的 IOKit 断言 | yes：iPhone 和 Moto 一起保持 1 个断言（21:48–21:51）；每次都在最后一个观看者处释放（21:51:15、21:59:35、22:02:18、22:05:04）；会话内模式切换时也是 | no：电池供电、屏幕录制撤销和快速用户切换未做物理测试 |
| 19:59 的窗格停滞 | **原因已更正**：不是显示器休眠（`caffeinate -dis` 一直阻止了它）。停滞发生在台前调度关闭和显示器拓扑变化之后 | — | 部分复现：侧边条窗口（Chrome）在主页/返回后进入暂停，然后“恢复实时”，接着停滞（状态 3）并重试（21:45:22–31） | no：侧边条窗口的重试循环需要修复 |
| 采集无法避免地需要显示器供电 | 证据：显示器于 18:41:58.215 休眠，SCK 在 60 ms 后停止（-3815）。这台 Mac 在显示器休眠时立即锁定 | — | 日志证据 | — |
| VoiceOver/TalkBack 无法点击 Mac：在直接触控前画面不接受触摸；激活操作绝不会点击（7f8a0f1） | iOS + Android | 5 项 Mac + 4 项 Android 策略测试 | **no**：需要在设备上使用 VoiceOver（所有者）；Moto **没有 TalkBack**（LineageOS，无 Google 服务） | no |
| iOS 辅助功能审计（XCUITest） | 测试在 ef262ea 中 | 在 iPhone 上运行：主页 6 个问题（动态字体部分支持、Mac 名称被裁切）；实时会话 1 个（台前调度通知被裁切） | 仅 iPhone（iPad 已锁定） | 更大字体 / 对比度仍未声明 |
| 长时间空闲，窗口模式（完整桌面 + 侧边条中的 Chrome） | — | 实时 UI 测试 | **yes**：10 分钟无输入，2 个窗格，无重连横幅；主页返回在 129–136 ms 内恢复 | — |
| 首帧 | — | — | 镜像 0.14 秒（Moto），模式切换后 3.1 秒（iPhone）；窗口首个窗格帧热启动 62–78 ms，冷启动 1.5–2.1 秒；**扩展 37 秒（Moto）和 61 秒（iPhone）**：SCK 列出新虚拟显示器前约 9–20 秒，随后 SCStream 启动内 27–41 秒，其他设备的采集启动都在其后面等待 | **no：扩展启动是阻塞项** |
| 同时混合模式（物理，iPhone + Moto） | — | — | **yes**：A iPhone 镜像 + Moto 扩展；B iPhone 窗口 + Moto 镜像；C iPhone 扩展 + Moto 镜像（Moto 的普通“连接”保持上次模式）。会话内切换 窗口→镜像（查看全屏）和 窗口→扩展（总览）均可用；无故障横幅 | 扩展延迟见上 |
| 每窗格旋转 | 较早的提交 | 较早的测试 | 所有者在完整桌面上保存的倾斜和缩放在跨会话后保持；测试自身的旋转并重置被跳过（不会触碰已经旋转的窗格） | — |
| 窗格菜单 | — | 实时测试 | yes：8 行 | — |
| App 菜单 | — | 实时测试 | 未显示：会话没有控制权 | — |
| 设置中的台前调度 | 03f1a38 | — | “关闭”请求被 Mac **丢弃**（无控制权），而设备仍显示按钮可用。台前调度保持开启。现已记录日志（6f7e313） | no：设备必须显示需要控制权 |
| 护盾解锁使用 Touch ID（所有者要求，009582f） | yes，Mac 有 Touch ID 时该设置默认开启 | 2 项策略测试；完整套件 2427/0 | **no**：需要所有者在 Mac 前 | no |
| 崩溃安全护盾（隔离原型，e3c0297） | 仅原型 | 9 项策略测试；5 个窗口层场景（B：0 间隙；A：315 ms 下限） | 无面板或摄像头检查 | **未安装；请求批准**（设计文档） |
| 同名 Mac：每台 Mac 的短 ID（所有者要求 22:05；d25e4f3） | iOS 主页和已配对 Mac、Android 主页、Mac 设置 ▸ 系统中的“此 Mac 的 ID” | Mac 2 + Android 2 项测试，共享向量 "1764" | 尚未在设备上查看 | Android 已配对 Mac 页面和 Mac 用户名（需要经过认证的协议字段）仍待完成 |

22:2x 安装：Mac Dev = d25e4f3（pid 32262）；iPhone = iOS 2000049（d25e4f3）；iPad 仍为 2000048
（安装被拒绝，已锁定）；Moto = debug d25e4f3。混合模式证据：`evidence/mixed-modes-2026-10-30/`
（timeline.txt、xcresults、Moto 截图）；辅助脚本 `tools/moto-mode-session.sh` 和 `tools/mac-session-summary.sh`。

## 2026-10-30 深夜（22:30 简报之后）

| 项目 | 已实现 | 自动化测试 | 物理验证 | 可发布 |
|---|---|---|---|---|
| 扩展启动：共享 ScreenCaptureKit 请求代理（e268f46、ed34d39、0ea6ebf）+ 启动跟踪 | yes | 11 项 CoalescingFetchTests；Mac 套件 2445/0 | yes：Moto 冷启动 2.4 秒 / 热启动 0.7 秒，iPhone 1.2 秒（无 AltTab）；有 AltTab 10.8 时 19–21 秒（原因：alt-tab-macos#5861） | 经过浸泡测试后 |
| 应所有者要求移除 AltTab（App、偏好设置、缓存、启动代理、其 TCC 条目） | done | n/a | 对话框已消失（所有者已清理；屏幕上没有） | n/a |
| 仅查看模式下开关台前调度会就地请求控制权（iOS 设置 + 窗格，Android 设置）（c39f839） | yes | WorkspaceClientTests 门控测试 | Android 仅查看模式的设置会显示“请求控制”+ 原因（截图）；iOS 已安装 2000050，尚未查看 | iOS 检查后 |
| 侧边条窗口暂停：每次窗口变化使用一条新流，然后如实显示“暂停”（40222cd） | yes | WindowCaptureHealthTests | 尚未（需要实时侧边条场景） | no |
| 仅已配对设备可见的 Mac 用户名 + Mac 开关（73580dc、ec6c4f7 双向文本安全） | yes | Mac 3 + Android 3 项测试 | Moto 从经过认证的欢迎消息中存储了 "<owner name>" | iOS 查看后 |
| caffeinate -dis | 已调查（只读） | n/a | 10 月 28 日 22:49 在 Zed 终端标签页（ttys005）中手动启动，永久运行；不是 MeowDisplay；保持运行 | n/a |

23:2x 安装：Mac Dev ec6c4f7；iPhone 2000050；Moto ec6c4f7。iPad 仍为 2000048（已锁定）。
证据：evidence/extend-p0-2026-10-30/README.md、evidence/p1-2026-10-30/。
| 摄像头模式 / 麦克风模式（2026-10-29 简报） | **未构建**；所有者选择暂时跳过（23:4x）。需要 CoreMediaIO 摄像头系统扩展（App 位于 /Applications，需所有者批准）和 Core Audio HAL 插件（管理员权限） | — | — | no |
| 上文过时行：“每 App 菜单栏跟随标签页：未开始”已构建（bed6359 iOS、a1d8ea9 Android、5116572/a6d4523 修复）；“自定义布局编辑器、功能托盘组合键编辑器（Android）：MISSING”已构建（35d3022，在本分支上） | — | — | — | — |

AltTab 对话框，23:4x：没有残留的 AltTab 进程或文件；49 个残留提醒属于 macOS 的
UserNotificationCenter（自 10 月 28 日起运行，持有 AltTab 排队的请求）。应所有者要求用
SIGTERM 结束它（launchd 会按需重启）；所有提醒窗口已消失。

## 2026-10-31 午夜之后（最终本地简报 + 附录；提交 058bbe4 … 752f3c3，随分支推送）

| 项目 | 已实现 | 自动化 | 物理 | 可发布 |
|---|---|---|---|---|
| 窗口模式：所选窗格内显示仅查看“请求控制”胶囊（058bbe4 iOS、2747368 Android） | yes | PaneRequestControlTests 5（+64 相关）；Android 套件 | Moto：窗格内胶囊（较早的运行）；iPhone 未手动复检 | yes，待所有者在 iPhone/iPad 上查看 |
| 调度中心暂停窗格，无重启循环；提示“Mac 上已打开调度中心。视频已暂停。”；一个窗格提供“退出调度中心”（需控制权）或内联“请求控制”（0941f86、752f3c3） | yes（Mac、iOS/iPadOS、Android） | MissionControlTests 8；Android WorkspaceWireTest；完整 Android 994/994 | Moto + iPhone，键盘进入/退出：检测 0.7 秒，关闭后所有窗格在 0.1–0.3 秒内恢复实时，0 次重启；连续 3 次快速循环无问题；两个接收端共享一次检测。证据：evidence/mission-control-2026-10-31/ | 带控制权退出和触控板手势进入未手动测试（需要所有者）；隐私护盾遮盖 + 调度中心未测试；iPad 未安装（不可用） |
| 空间总览（所有者要求） | 已构建：Shared/SpatialOverview.swift、iOS StagePeekGallery（iPhone + iPad）、Android StagePeekOverlay；设置 展开布局 ▸ 空间总览 | 现有测试 | — | yes |

00:12 安装：Mac Dev 0941f86；iPhone 2000052；Moto 752f3c3。iPad 仍为 2000048（不可用）。


## iPad QA 2026-10-31（所有者手动验证；提交 cdeda71、b94abf6 和名称提交；已推送）

设备：iPad（第 9 代，iPad12,1），iPadOS 27.0.1，开发者模式开启。构建原地安装
（未卸载；保留配对：每次更新后同一设备 ID 均被准入）：2000053 → 2000058。
Mac Dev = cdeda71（Smart Touch 深度修复）。iPhone = 2000058。Moto = b94abf6 debug。

| 检查 | 结果 |
|---|---|
| 连接、窗口模式、两个窗格（Finder、Chrome）、窗格选择 | 通过 |
| 捏合缩放、平移、每标签页旋转、重置视图 | 通过 |
| 空间总览 / 自适应 iPad 布局、竖屏 ↔ 横屏旋转 | 通过 |
| 窗格内的仅查看“请求控制”胶囊；在 Mac 上批准；输入和点按可到达 Mac | 通过 |
| 调度中心：提示、窗格暂停且不重启、恢复；带控制权退出调度中心 | 通过（Mac 日志：6 次打开/关闭循环，0 次重启） |
| iPad + Moto 同时连接 | 通过（00:45） |
| 从主页镜像和扩展 | 通过 |
| 滚动 | 首次 FAILED（两指拖拽移动了已缩放的窗格；Smart Touch 在 Chrome 的 12 层 AX 后放弃）→ 已修复 cdeda71 → 通过 |
| 从台前预览拖拽 App | 首次 FAILED（与手指有偏移；出现两个“拖到此处取消”区域）→ 已修复 cdeda71 → 通过 |
| 紧凑台前预览滚动时的预览工具栏 | 首次 FAILED（抖动）→ 已修复 b94abf6（iOS + Android）→ 报告已修复 |
| 从长按菜单、工具栏和预览共享 | 首次 FAILED（副本被 /private 路径检查拒绝，且无提示）→ 已修复 b94abf6 → 共享面板可打开 |
| 存储到设备 | 首次 FAILED（同样问题；随后崩溃：Photos 代码块被隔离到主 actor）→ 已修复 b94abf6 → 通过（照片存入“照片”，其他文件存入“文件” ▸ MeowDisplay ▸ 下载，并提示位置） |
| 展开视图：点按空白处关闭 | 已构建 b94abf6（所有者要求） |
| App 栏：滚动时变宽，下拉展开到包含全部 App 名称的行，把手，上滑收起；“所有 App”上滑关闭 | 已构建 b94abf6 + 名称提交（仅 iPhone/iPad；Android 未构建） |
| App 栏先展开四行，再展开整个屏幕，停在“展开”和“关闭”上方（“紧凑”会缩小它）；搜索会过滤 App 栏 | 已构建 70d3507 + 9b8ba92，iOS 2000061（搜索也会过滤 Android 的 App 行）；StagePeekDockLayoutTests 5/5；尚未手动检查 |
| Android 会话结束时崩溃（关闭时的 InterruptedException） | 在 Moto 崩溃日志中发现，已用测试在 b94abf6 中修复 |

iPad 上未检查：VoiceOver 走查、更大字体、隐私护盾遮盖（所有者的
privacyShield.local 处于关闭状态）。iPad 上的自动化实时 XCUITest 在没有保存的
窗口布局时会跳过（其布局最初为空）。
