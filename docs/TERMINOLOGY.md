# MeowDisplay 术语与文案指南

为 Mac 应用、Mac 接收端、iPhone/iPad 和 Android 应用、网站及文档统一一套词汇。使用简短、平实的句子，告诉人们该做什么。

宣传语：**Mac Everywhere, On Whatever Display**。它出现在“关于”下方和 README 中，绝不出现在主屏幕上。

各平台的控制和设置一致性：[RECEIVER_CONTROLS.md](RECEIVER_CONTROLS.md)。

**营销 / 公开文档：** 不要将 **“Windows”** 用作独立的功能标题；它可能与 Microsoft Windows 操作系统混淆。请改为解释为 **“Mac windows”**、**“Window view”** 或 **“Choose the Mac windows you want”**。在应用 UI 中，现有的 **Windows** 模式标签保持不变，直到经过明确审查的产品文案更改；不要重命名 wire 值、设置键或 UI 测试标识符。此能力与 Windows 操作系统移植无关（未计划的想法 #84）。

MeowDisplay 的产品范围是[个人优先](PRODUCT_SCOPE.md)：欢迎专业/商业使用，但企业远程管理、托管账户/中继、Windows 和 Linux 移植不是计划内工作。在 issue 中讨论的想法不是交付承诺。

## 规范名称

标签、按钮和标题使用 Title Case；在正文句子中，如果给出了小写形式，则使用小写。若某个应用当前有所不同，[不一致](#inconsistencies-found-and-fixed)列表说明了更改内容。

### 基础

| 使用 | 含义 | 不要使用 |
| --- | --- | --- |
| **Mac app** | 发送屏幕的 Mac 上的 MeowDisplay（Mac 应用） | host app, server, sender (fine in code and protocol docs) |
| **this iPhone / this iPad / this device** | 接收设备，在其自己的应用中（此 iPhone / 此 iPad / 此设备） | client, receiver (fine in code), "the display" |
| **Mac Receiver** | 在显示另一台 Mac 的 Mac 上运行的 MeowDisplay。应用本身名为 **MeowDisplay Receiver**（菜单、窗口标题）（Mac 接收端） | |
| **Pair** | 一次性信任步骤：两个屏幕显示相同代码，由你确认（配对） | link, bond, trust (as a verb) |
| **Codes Match** | 配对时的确认按钮（代码匹配） | Confirm, OK |
| **Connect** | 与已配对的 Mac 开始会话（连接） | stream, start streaming (as a button) |
| **Disconnect** | 结束会话；配对保留（断开） | stop, close |
| **Forget This Mac** / **Forget This Device** | 移除配对；再次使用需重新配对。已经指明 Mac 的行可以只写 **Forget…**（忘记此 Mac / 忘记此设备） | unpair, remove trust |
| **Allow** / **Not Now** / **Always Allow** / **Block** | Mac 的回答（允许 / 暂不 / 始终允许 / 阻止） | Accept, Deny (as labels) |
| **Wi-Fi**, **USB**, **Remote** (another network, e.g. Tailscale) | 设备如何连接（Wi-Fi、USB、远程——另一个网络，例如 Tailscale） | WiFi, wireless, LAN (in UI), tunnel |
| **Add Remote Mac** | Android：用于访问此 Wi-Fi 之外 Mac 的表单和 Mac 列表下方的链接。一个 **Address** 字段，然后是 **Pair New Mac** 或 **Use for a Paired Mac**。Pair over Remote 是 Mac 首次配对时的窗口（添加远程 Mac） | Add Server, Add Host, Add Endpoint |
| **Address** | 在另一网络上访问 Mac 的位置：名称（MagicDNS）或 IP 地址，可选 `:port`。它是一个提示；由配对决定 Mac 是谁。菜单项：**Add Address for…**、**Edit Address for…**、**Remove Address**（地址） | Endpoint, Host, IP (in UI) |
| **Security Details** | Android 的每台 Mac 菜单项：Mac 的安全密钥、短 ID 和已保存地址（安全详情） | Fingerprint, Certificate |
| **Contacting your Mac…** · **Waiting for your Mac to connect…** · **Needs approval on your Mac** · **Reconnecting…** | Android 远程状态下 Connect 进行中的状态：请求正在发送、请求已送达且 Mac 应回拨、Mac 用户必须允许、丢失连接后的恢复（正在联系你的 Mac…… / 等待你的 Mac 连接…… / 需要你的 Mac 批准 / 正在重新连接……） | Knocking, Pinging, Dialing back |
| **Remote** · **Local** | 已连接会话运行的位置：卡片上的 **Connected · Remote · Tailscale**，以及性能叠层中的 **Remote (Tailscale)**。仅当证据显示 Tailscale 时才点名 Tailscale；否则使用 **Remote** 或 **VPN**。此 Wi-Fi 上的会话在叠层中不显示路由（远程 / 本地） | Tunnel, Relay, Cloud |
| **Nearby** | 此设备当前在本地网络上看到的已配对 Mac（Android Macs 列表）。已保存地址显示为 **Saved remote · address**（附近） | Available locally, Online |
| **Auto-Reconnect** | 丢失连接后自行重新连接（自动重连） | Automatic Reconnection |
| **Settings & Help** | 主屏幕上的设置入口。在会话内，同一屏幕的标题为 **Settings**（设置与帮助） | Preferences, Options |
| **Macs** · **How to Connect** · **This Device** | 主屏幕：一张 **Macs** 卡片，然后是 **How to Connect** · **This Device** 链接。This Device 显示名称 Macs 列表（在 Android 上还有安全密钥）（Macs · 如何连接 · 此设备） | Your Macs, Nearby Devices, Device Details |
| **paused** | Mac 暂停了画面（已暂停） | frozen, suspended |

### 显示与窗口模式

| 使用 | 含义 | 不要使用 |
| --- | --- | --- |
| **Mirror** | 按原样显示 Mac 显示器（镜像） | duplicate, clone, "Mirroring a display" as a label |
| **Extend** | 为此设备增加一个独立桌面（扩展） | second display (in UI), virtual display (in UI), "Extended desktop" as a label |
| **Display Mode** | 包含镜像和扩展的设置；当 Mac 提供时，**Windows** 加入其中（显示模式） | Mode, Touch Mode, What This Device Shows |
| **Windows** | 显示模式标签和控制：并排显示你选择的 Mac 窗口（窗口） | app mode, window streaming |
| **Window view** | 你在 Windows 中看到的：用磁贴代替整个屏幕。在应用文案中使用（"Switch to Window view?"）（窗口视图） | Window mode (in app copy) |
| **Window mode** | 文档和正文中的同一事物。不是按钮（窗口模式） | |
| **Full Desktop** | 整个 Mac 屏幕，从窗口视图返回的方式。台前预览的顶部卡片和概览中的镜像/扩展按钮都通向那里（完整桌面） | Whole display, Desktop mode |
| **tile** | 一个窗口在窗口视图中的位置（磁贴） | pane, slot (code only) |
| **Stage Peek** | 默认窗口切换器：按住屏幕边缘，滑动浏览，点按一个窗口（台前预览） | peek, flyout. (Stage Manager is the Mac's own feature; Stage Peek is not it) |
| **Rail** | 可选的窗口切换器：一个细手柄，打开一条窗口带。**Move Rail** 移动它（轨道） | dock, sidebar, tab bar |
| **Window Switcher** | 选择 **Stage Peek** 或 **Rail** 的设置（窗口切换器） | Window Picker, Quick Switch |
| **Stage Peek Edge** | **Left** 或 **Right**（台前预览边缘） | |
| **Hidden on this screen** | 不再放得下的磁贴（在此屏幕上隐藏） | Stacked, Offscreen |
| **Arrange**, **Maximize**, **Restore Layout**, **Rotate**, **Fill Tile** / **Show Whole Window**, **Remove Tile** | 磁贴操作（排列、最大化、恢复布局、旋转、填充磁贴 / 显示整个窗口、移除磁贴） | |
| **Close Window on Mac…** | 关闭真实的 Mac 窗口（始终确认）（在 Mac 上关闭窗口……） | close tile |
| **Typing paused** | 由于 Mac 上另一个应用位于前台，磁贴未接收按键（输入已暂停） | |
| **Switch to Window view?** | 完整桌面上的首次提示。**Yes** / **No**；8 秒后自动消失（切换到窗口视图？） | |

### 输入与触控

| 使用 | 含义 | 不要使用 |
| --- | --- | --- |
| **Input Mode** | 设置：**Direct Touch** 或 **Trackpad**。"Input" 仅命名输入模式设置和输入设置页面；向 Mac 请求权限称为 "control"（输入模式） | Touch Mode, Pointer Mode |
| **Direct Touch** | 在你想要指针的位置触摸（直接触控） | absolute mode, touchscreen mode |
| **Trackpad** | 指针相对于你的手指移动，像笔记本电脑触控板。小写的 "trackpad" 指物理触控板（触控板） | Mouse mode, Relative mode |
| **Touch Style** | Direct Touch 的设置：**Natural Touch** 或 **Classic**（默认）。在 Trackpad 中不显示（触控样式） | Touch Mode |
| **Natural Touch** | 点按即点击，滑动即滚动，按住后移动即拖动，触摸并按住即右键单击（自然触控） | Natural (alone), macOS mode |
| **Classic** | 最初的 Direct Touch：手指就是指针，点按后按住即拖动（经典） | Legacy, Old |
| **Smart Touch** (Experimental) | 仅限 Classic。在 Mac 指示可滚动的区域用一根手指滚动；按住标题栏移动其窗口。品牌名称；永不翻译（智能触控，实验性） | Smart Scroll |
| **Request Control** | 请求 Mac 允许此设备控制它。在设置中和屏幕上使用相同标签，适用于 iPhone、iPad、Android 和 Mac 接收端（标题栏）（请求控制） | Request Input, Enable Input, ask for control |
| **Requesting Control…** | 请求正在等待 Mac（正在请求控制……） | Requesting Input…, Requesting… |
| **Control Allowed** | Mac 已为此会话同意（已允许控制） | Input Allowed, Input Enabled, Allowed for this session |
| **Control Declined** | Mac 拒绝了，或提示超时（控制被拒绝） | Input Declined, Not allowed |
| **Control Not Available** | Mac 不接受来自此设备的控制请求。句子形式为 "This Mac isn't accepting control requests"（控制不可用） | Input Not Available, Requests disabled by Mac |
| **Controlling** / **Paused** | Mac 接收端的活动状态。Paused：控制在此处暂停，点击可恢复（正在控制 / 已暂停） | Control Paused |
| **Allow Input** | Mac 应用自己的主开关。接收端无法更改它。其在 Mac 上的按设备策略是 **Input Requests**（Ask, Always Allow Requests, Never Allow Requests）（允许输入） | |
| **View Only** | 设备显示 Mac 但无法控制它。每个会话都从这里开始（仅查看） | read-only, locked, view-only |
| **Request Control Automatically** | 每台 Mac：被阻止的触摸会自行请求；Mac 仍然决定（自动请求控制） | Request Input Automatically |
| **Trackpad Sensitivity** | Trackpad 的速度滑块（触控板灵敏度） | Trackpad Speed |
| **Local View Navigation** | 平移、缩放和重置你自己的视图；绝不会发送到 Mac（本地视图导航） | |
| **Viewport** / **App** / **Disabled** | 捏合或旋转的作用（视口 / App / 禁用） | |

### 控制

| 使用 | 含义 | 不要使用 |
| --- | --- | --- |
| **control tray** (**Control Tray** in labels) | 修饰键和系统键的托盘：⌘ ⌥ ⌃ ⇧ Esc Tab Dock Keyboard Settings（控制托盘，标签中使用 **Control Tray**） | Main Tray, Main Controls (iPad Strip and Overlay layouts only), tool bar |
| **function tray** (**Function Tray**) | 第二个独立托盘，提供一键快捷操作：Zoom In、Zoom Out、Undo、Redo（功能托盘） | shortcut bar, Fn tray |
| **Control Profile** / **Function Profile** | 每个托盘使用的已保存配置：Default、Profile 1、Profile 2（控制配置档 / 功能配置档） | |
| **chord** / **palette** | 按住一个修饰键，出现匹配快捷键的调色板（组合键 / 调色板） | |
| **Strip**, **Overlay**, **Custom** | iPad 和平板控制布局（条形、叠层、自定义） | |
| **Haptics** | 振动反馈；**Smart Touch Haptics** 是按住反馈（触觉反馈） | Vibration |
| **Picture in Picture** | 使用其他应用时，Mac 的仅查看浮动窗口（画中画） | picture-in-picture, PiP (in UI) |
| **Performance Overlay** | 画面上方的实时帧率、比特率和延迟（性能叠层） | Performance overlay, HUD, analytics |

## 语气与写作规则

- **简短、平实的动词。** 点按、按住、拖动、选择、打开、关闭。不要用 "utilize"、"initiate"、"toggle"、"engage"。
- **不要使用用户没有要求的术语。** 说 "the Mac says the area scrolls"，而不是 "the accessibility element is scrollable"。在应用文案中跳过协议、编解码器、传输和 API 词汇。在 PROTOCOL.md 中可以。
- 以动作为先："Tap Pair, then check that both screens show the same code."
- 说明由谁决定："The Mac decides." "Your Mac confirms it."
- 错误信息按此顺序说明发生了什么以及下一步该做什么："Macbook didn't connect. Check that MeowDisplay is open on it and that both are on the same Wi-Fi, then try again."
- 当某项功能在某个平台上不可用时，要明确说明（"Not available on Android yet. Use Wi-Fi."）。不要暗示不存在的功能。
- 应用中不要使用 "simply"、"just"、"seamlessly"、"effortlessly"、"Oops"、感叹号或营销形容词。
- 按钮是 Title Case 的动词（"Choose Windows…"、"Start Picture in Picture"）；省略号表示还有下一步。
- 开关是 Title Case 的名词或名词短语（"Auto-Reconnect"、"Picture in Picture"）；其下方的说明是句子。
- 菜单项遵循同样的规则："Fill Tile"，而不是 "Fill tile"。
- 在每个屏幕上以相同方式命名功能。如果标签和说明对同一事物使用不同词语，那么其中之一是错的。
- 已知 Mac 名称时，用其名称称呼 Mac（"Show Macbook here?"），否则用 "your Mac"。
- 数字保留单位："66 ms"、"+250 ms"。
- 每个应用使用一种撇号风格：Apple 应用和 Android 中使用直撇号 `'`（大多数字符串已经使用它）。不要在相邻字符串中混用 `'` 和 `’`。
- 文档中的路径使用箭头：Settings → Display → Choose Windows…。每个名称都完全保持应用显示的样子，包括省略号。

## 不得更改的标识符

这些标识符存在于协议或存储数据中。可以更改人们阅读的文字，但绝不能更改这些：

- Wire 值：显示模式 `mirror`、`extend`、`window`；消息类型如 `windowCatalogRequest`、`workspaceRequest`、`inputRequest`；代码中比较的传输标签（例如 iOS 性能叠层的 `"WiFi"` / `"USB"` 路由值）。
- 存储键：`avSyncOffsetMs`、`pictureInPictureEnabled`、`autoReconnectEnabled`、`showAnalytics`、`wifiRemembered`、`inputMode`、`touchStyle`、`windowSwitcher`、`stagePeekEdge`、`invertVerticalScroll`、Android 的 `workspace` 和 `diagnostics` 偏好文件、Bonjour 服务类型 `_opensidecar._tcp` 和 TXT 键。
- Bundle 和包标识符、keychain 服务名称、URL scheme。
- UI 测试使用的辅助功能标识符，例如 `windowSwitcherPicker`、`stagePeekEdgePicker`、`touchStylePicker`。

## 平台名称

各应用今天对同一事物的称呼。空白行不是不一致。

| 概念 | Mac 应用 | iPhone / iPad | Android | Mac 接收端 |
| --- | --- | --- | --- | --- |
| 设置入口 | Settings… | Settings & Help | Settings & Help | Settings… |
| 如何连接 | Devices (empty state) | How to Connect | How to Connect | — |
| 窗口选择器 | — | Show Mac Windows… / Choose Windows… | Choose Windows… | Windows |
| 窗口切换器设置 | — | Controls → Window Switcher | Display → Window Switcher | — |
| 画中画 | — | Picture in Picture | Picture in Picture | — |
| 性能数字 | — | Performance Overlay (Diagnostics) | Performance Overlay (Session) | Performance Overlay (System) |
| 请求控制 | Input Requests (policy), Always Allow Requests | Request Control (Settings and on screen) | Request Control (Settings and on screen) | Request Control (title bar) |
| 显示模式设置 | Display Mode | Display Mode | Display Mode | Display Mode |
| 帮助页面 | — | About | Help | — |


<a id="inconsistencies-found-and-fixed"></a>
## 已发现并修复的不一致

通过阅读 `iOS/`、`Shared/`、`MacReceiver/` 和 `AndroidReceiver/` 中的字符串字面量发现（2026-10-29），与产品负责人一起审查，然后在代码、测试和文档中应用（2026-10-29）。**Outcome**（结果）是以下之一：**Done**（按提案应用）、**Changed**（已应用，但决定与提案不同）、**Kept**（差异是有意的）或 **Already done**（更早修复）。审查中有三行发生变化：与 Mac 交互的权限在所有地方都是 **Request Control**，而不是 Request Input（第 1、28、30 行）。

“differs”列记录更改前的措辞；行号指的是当时的代码。裸 Swift 文件名位于 `iOS/` 下；裸 Kotlin 文件位于 `AndroidReceiver/app/src/main/kotlin/com/raisecaterror/meowdisplay/android/`（`receiver/`、`ui/`、`receiver/workspace/`）下。

| # | 概念 | 差异位置（文件:行，文本） | 规范 | 结果 |
| --- | --- | --- | --- | --- |
| 1 | 向 Mac 请求控制 | `iOS/ReceiverSettings.swift:623` "Request Control"；`MacReceiver/ReceiverInputController.swift:270` "Request Control"；`MacReceiver/ReceiverInputForwarding.swift:429-434` "Requesting Control…"、"Control Declined"、"Control Not Available"、"Control Allowed"、"Control Paused"；`Shared/Protocol.swift:428-432` "Allowed for this session"、"Not allowed"、"Requests disabled by Mac"；对比 `iOS/OpenSidecarPhoneApp.swift:4528` 和 `ReceiverScreen.kt:459` "Request Input" | **Request Control**、**Requesting Control…**、**Control Allowed**、**Control Declined**、**Control Not Available**。**Controlling** 和 **Paused** 保留为 Mac 接收端的活动状态 | Changed。提案是 Request Input；决定是 Request Control。还更改了：iOS 和 Android 的屏幕提示（Enable Input 和 Request Input 都读作 Request Control；Input Enabled 读作 Control Allowed）、辅助功能提示、Request Control Automatically、演示控制、Android 的 Input 页面状态行以及 Mac 接收端的 "Control Paused"（现在为 Paused） |
| 2 | Direct Touch / Trackpad 的设置 | `ReceiverSettings.kt:160` "Touch Mode"；iOS `ReceiverSettings.swift:645,670` "Input Mode" | **Input Mode** | Done |
| 3 | 触控板速度 | `ReceiverSettings.kt:163` "Trackpad Speed"；iOS "Trackpad Sensitivity" | **Trackpad Sensitivity** | Done |
| 4 | 滚动方向（同一偏好，开启 = 自然） | iOS `ReceiverSettings.swift:697,699` "Invert Vertical Scrolling" / "Invert Horizontal Scrolling"；Android `ReceiverSettings.kt:188-189` "Natural Vertical Scrolling" / "Natural Horizontal Scrolling" | **Natural Vertical Scrolling** / **Natural Horizontal Scrolling** | Done。先进行了检查：`ScrollDirectionPolicy` 在两个平台上相同（手势管道传递自然增量；开启时原样传递，关闭时翻转该轴），且两者都默认开启，因此在 iOS 上开启也是自然滚动。存储键 `invertVerticalScroll` 和 `invertHorizontalScroll` 不变 |
| 5 | 主托盘 | iOS "Show Control Tray"、"Collapse Control Tray"、"Auto-hide Control Trays"、标题 "Main Controls"、说明 "Main Tray"、编辑器区块 "Main Tray"；Android "Main Tray"、"Show Controls"、"Collapse to Settings Button"、"Auto-hide" | 区块和开关使用 **Control Tray**；"Main Controls" 仅保留用于 iPad Strip 和 Overlay 边缘选择器 | Done |
| 6 | 键盘按钮 | iOS "Show Keyboard Button"；Android "Keyboard Button" | **Show Keyboard Button** | Done |
| 7 | 托盘配置档选择器 | iOS "Active Profile"、"Function Profile"；Android "Profile"（两次） | **Control Profile** 和 **Function Profile** | Done |
| 8 | 横屏侧边 | iOS "Landscape Tray Side"；Android "Landscape Side" | **Landscape Tray Side** | Done |
| 9 | 功能托盘位置 | iOS "Function Tray Position"；Android "Position" | **Function Tray Position** | Done |
| 10 | 调色板样式 | iOS "Palette Style"；Android "Palette" | **Palette Style** | Done |
| 11 | 控制提示 | iOS "Show Control Hints"；Android "Control Hints (Strip)" | **Show Control Hints**，Android 上说明为 "Hints appear on the Strip layout only." | Done |
| 12 | 表面网格 | iOS "Show Surface Grid"；Android "Surface Grid When Video Is Off" | **Show Surface Grid**，说明 "Shown while Video is off." | Done |
| 13 | 本地视图导航 | iOS "Allow Local View Navigation"；Android "Local View Navigation" | **Allow Local View Navigation** | Done |
| 14 | 捏合和旋转选择器 | iOS "Pinch / Zoom"、"Rotation"；Android "Pinch"、"Rotate" | **Pinch / Zoom**、**Rotation** | Done |
| 15 | Mac 音频开关 | iOS 和 Mac 接收端 "Audio"；Android "Mac Audio" | **Audio** | Done |
| 16 | 刘海 / 挖孔 | iOS "Avoid Notch"；Android "Avoid Cutouts"（同一偏好，`avoidNotch`） | 两者都保留：Android 手机有挖孔摄像头，而不是刘海 | Kept |
| 17 | 性能叠层 | iOS "Performance overlay"、"Metal renderer (experimental)"；Android 和 Mac 接收端 "Performance Overlay" | **Performance Overlay**、**Metal Renderer**，带有 Experimental 徽章（与 Smart Touch 使用的橙色徽章相同） | Done |
| 18 | 连接日志 | iOS "Connection log"；Android "Share Connection Log"；Mac 接收端 "Reveal Log Files in Finder" | 在所有地方将对象命名为 **Connection Log**；动词可以不同（Share、Reveal） | Done。iOS、其屏幕标题和搜索条目；Mac 接收端按钮 "Reveal Connection Log in Finder" 及其搜索条目。Mac 应用保留自己的 "Reveal Log Files in Finder" |
| 19 | 显示模式设置 | iOS "Display Mode"；Android "What This Device Shows"；Mac 接收端选择器 "Mode" | **Display Mode** | Done |
| 20 | 应用文案中的窗口视图与窗口模式 | iOS 和 Android "Used in Window mode."；"Switch to Window view?" | **Used in Window view.** "Window mode" 保留在文档中 | Done |
| 21 | 窗口视图的整屏一侧 | 台前预览卡片上的 "Full Desktop"；概览上的 "Whole display:" | **Full Desktop:** 作为概览标签 | Done |
| 22 | 磁贴菜单大小写 | iOS Title Case；Android sentence case | Title Case，与 iOS 一致 | Done（Android 菜单和点击 "Remove Tile" 的模拟器冒烟测试） |
| 23 | View Only 拼写 | 画中画说明和 Android 主屏幕摘要中的 "view-only"、"view only" | **View Only**；画中画说明："It shows your Mac; control stays in MeowDisplay." | Done |
| 24 | Android 主屏幕摘要 | "Mirroring a display"、"Extended desktop"、"Showing Mac windows" | **Mirror**、**Extend**、**Windows**，与 **View Only** 或 **Controlling** 组合（"Mirror · View Only"） | Done |
| 25 | 画中画 | Android "picture-in-picture" | **Picture in Picture** | Done |
| 26 | 设置和帮助名称 | Android 页面标题 "Help & About"；Natural Touch 提示说 "Settings & Help > Input" | Android 页面 **Help**；提示："go to Settings → Input"（两个平台一致） | Done |
| 27 | 触摸帮助已过时 | `iOS/ReceiverSettings.swift` "Touch: tap to click, drag to drag, two-finger pan to scroll." | "Touch: tap to click, swipe to scroll, press and move to drag, hold to right-click." | Already done（提交 c8d0132） |
| 28 | Mac 接收端说输入不会被发送 | `MacReceiver/ReceiverOverviewSettingsView.swift:140` "…there is no input permission to request."；`ReceiverSettingsCategory.swift` 中的代码注释也这么说 | "Use Request Control in the video window's title bar to control the other Mac with this Mac's keyboard and trackpad." 该区块标题为 **Control** | Changed。提案说 Request Input；决定是 Request Control。说明文字和代码注释已修复 |
| 29 | "Window" 在 Mac 接收端有两层含义 | `MacReceiver/ReceiverDisplaysSettingsView.swift:71` 区块 "Window" | 区块 **Video Window** | Done |
| 30 | 撇号和措辞 | `iOS/OpenSidecarPhoneApp.swift:4531` "isn’t accepting input requests"（弯撇号）；`iOS/ReceiverSettings.swift:635` "isn't"（直撇号）；Android "isn't accepting input requests" | 每个应用一种撇号风格，直撇号 `'`（大多数 Apple 字符串已经使用它，因此 `iOS/` 和 `MacReceiver/` 中的弯撇号被改为直撇号）；所有地方都用 "control requests" | Changed。提案说 "input requests"；决定是 "control requests" |
| 31 | Connect 的顺序 | iOS 先 Mirror，再 Extend；Android 先 Extend，再 Mirror | 先 Mirror，再 Extend | Done |
| 32 | Mac 应用大小写 | Android "Get the Mac App"；iOS "Get the Mac app" | **Get the Mac app** | Done |
| 33 | 忘记 | iOS "Forget"；Mac 接收端 "Forget…"；Android "Forget This Mac" | 在指明 Mac 的行中使用 **Forget…**（会打开确认）；在菜单中使用 **Forget This Mac** | Done（iOS 行；确认按钮保持 "Forget"） |
| 34 | 说明中的术语 | Android "when the Mac says the element under it scrolls" | "Scroll with one finger where the Mac says the area scrolls. Hold a title bar, then drag, to move its window." | Done |

34 行：29 项完成，3 项在审查中更改（1、28、30），1 项保留（16），1 项已提前完成（27）。第 4 行是在检查两个平台上开启即自然滚动后完成的。

有意保留：Mac 应用自己的名称 **Allow Input**（主开关）和 **Input Requests**（按设备策略）。它们属于应答请求的 Mac，而不属于发出请求的接收端。如果它们也应读作 "control"，请与 Mac 应用的设置搜索关键词一起更改。String Catalog 只包含英文，因此没有翻译发生移动；它们的键已重命名以匹配新措辞。
