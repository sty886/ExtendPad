# ExtendPad 设置指南

ExtendPad 使用一台 Mac 作为发送端，并支持 Android 设备和其他 Mac 作为
接收端。当前功能概览见 [README.md](../README.md)，平台差异见
[PARITY.md](PARITY.md)。

## 要求

- Mac 发送端：macOS 14 或更高版本。
- 独立 Mac 接收端：macOS 12 或更高版本。
- Android 接收端：Android 10 或更高版本。
- Mac 构建：`.xcode-version` 中指定的 Xcode 版本和 XcodeGen。
- Android 构建：JDK 17 和 Android SDK。

## 生成并构建 Mac 应用

`project.yml` 是纳入版本管理的 XcodeGen 规范。`.xcodeproj` 在本地生成，
不得直接编辑。

```sh
./generate.sh
xcodebuild -project ExtendPad.xcodeproj \
  -scheme OpenSidecarMac \
  -configuration Debug \
  -derivedDataPath build/macos build
```

构建独立接收端：

```sh
xcodebuild -project ExtendPad.xcodeproj \
  -scheme OpenSidecarMacReceiver \
  -configuration Debug \
  -derivedDataPath build/mac-receiver build
```

如需签名的本地构建，请在运行 `generate.sh` 前创建 `.env`，内容为
`DEVELOPMENT_TEAM=YOURTEAMID`。绝不要提交签名密钥、描述文件或 `.env`。

### 在没有描述文件的情况下构建

Mac 应用的 `TrustStore` 使用数据保护钥匙串，这需要描述文件（即
`keychain-access-groups` 权限）。在没有 Apple 开发者账户登录 Xcode 的 Mac
上，常规构建仍可启动，但无法创建其身份：`SecItemAdd` 会失败并返回
`-34018`（`errSecMissingEntitlement`），因此 Mac 永远不会广播
`_opendisplay-mac-pair._tcp`，USB 发现会返回“主机不可用”，接收端则一直
显示“正在查找主机…”。

这种情况请构建登录钥匙串变体：

```sh
xcodebuild -project ExtendPad.xcodeproj -scheme OpenSidecarMac \
  -configuration Release -derivedDataPath build/macos-local \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=LOCAL_FILE_KEYCHAIN \
  CODE_SIGN_ENTITLEMENTS="" CODE_SIGNING_ALLOWED=NO build

codesign --force --deep --sign "Apple Development: <your identity>" \
  build/macos-local/Build/Products/Release/ExtendPad.app
```

它把身份、固定项和信任存储在登录钥匙串中，使用 `.local` 钥匙串命名空间，
而不是数据保护钥匙串。这与使用描述文件签名的构建属于不同身份，因此接收端
需要单独与它配对一次。

## 构建并安装 Android

在仓库根目录执行：

```sh
cd apps/android
./gradlew :core:test :app:testDebugUnitTest :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Debug 应用使用单独的 application ID，可与正式安装共存。测试、模拟器和签名
命令见 [Android README](../apps/android/README.md)。

## 权限

| 位置 | 权限 | 用途 |
| --- | --- | --- |
| 发送端 Mac | 屏幕录制 | 采集镜像、扩展和窗口内容 |
| 发送端 Mac | 辅助功能 | 注入已批准的触摸、指针和键盘输入 |
| 发送端 Mac | 本地网络 | 通过 Wi-Fi 发现并连接 |
| Android | USB 调试，仅用于 USB | 授权不透明的 ADB 隧道 |

连接不会授予输入权限。请在 Mac 上开启“允许输入”，并批准接收端对当前会话
的“请求控制”。

## 通过 Wi-Fi 连接

1. 在同一网络中的接收端和 Mac 应用上打开应用。
2. 在被要求时允许本地网络访问和防火墙访问。
3. 在接收端选择该 Mac，然后选择 **Wi-Fi**。
4. 在两台设备上确认相同的配对码。
5. 选择镜像、扩展或窗口。

接收端会列出它通过 Bonjour 发现的每一台正在运行的 Mac；无需输入 IP 地址。
发现本身绝不会选择路线或启动会话。

## 通过 USB 连接 Android

1. 安装 Android SDK platform-tools，以便使用 `adb`。
2. 在 Android 设备上启用开发者选项和 USB 调试。
3. 连接支持数据传输的线缆，解锁设备并授权此 Mac。
4. 安装并打开 Android 应用。
5. 正常配对并连接。

ExtendPad 仅将经授权的 ADB 转发用作不透明字节隧道。配对、固定身份和加密
传输仍然是必需的。同一时间只支持一台经授权的 Android USB 设备，因为主机
端口无法独立映射到多台设备。

Android 应用还声明了一条 AOA（Android Open Accessory）控制通道，在固件
能够完成配件切换的设备上可避开 platform-tools 和开发者选项。正式发布的
Mac 传输仍使用 ADB，因为经过测试的华为固件接受 AOA 的 GET_PROTOCOL 和
ACCESSORY_START，却从不重新枚举为配件；见
[TECHNICAL_NOTES.md](TECHNICAL_NOTES.md#usb-transport-aoa-versus-the-adb-tunnel-2026-11-07)。

## Mac 对 Mac 连接

Mac 接收端使用网络路线，包括受支持的有线网络。在接收 Mac 上安装主应用或
独立接收端，打开它，并与发送端配对。键盘和触控板转发需要与其他输入相同的
每会话控制授权。

## 远程访问

远程访问使用可到达的私有网络地址，例如 Tailscale 端点。它不提供托管中继，
也不替代配对。

1. 在两台设备上配置相同的私有网络。
2. 在接收端的远程设置中添加 Mac 的地址。
3. 远程配对，或对已配对的 Mac 使用已保存的地址。
4. 连接。发送端 Mac 进行认证并拨号到接收端。

唤醒并连接受硬件、唤醒以供网络访问和网络条件限制。见
[REMOTE_WAKE_ON_LAN.md](REMOTE_WAKE_ON_LAN.md)。

## 显示与输入

- **镜像**复制一块处于活动状态的物理显示器。
- **扩展**创建一块独立的虚拟显示器。
- **窗口**把选中的 Mac 窗口作为磁贴显示，移除磁贴时不会关闭窗口。
- **音频**由接收端启用；音画同步和重新同步可调整播放。
- **输入**在 Mac 为该会话授予控制权之前保持仅查看。
- **暂停**会停止媒体交互和远程输入，直到恢复。

见 [WINDOW_MODE.md](WINDOW_MODE.md) 和
[RECEIVER_CONTROLS.md](RECEIVER_CONTROLS.md)。

## 故障排除

- **附近没有接收端：** 确认两台设备都已打开、处于同一网络，并获得使用本地
  网络的权限。
- **没有画面：** 检查屏幕录制权限，以及所选的镜像源是否处于活动状态。
- **扩展不可用：** 在发送端 Mac 上启用视频采集并检查虚拟显示器错误。
- **输入没有反应：** 检查辅助功能、“允许输入”以及当前会话的控制授权。
- **Android USB 不可用：** 确认 `adb devices` 恰好列出一台已授权的
  `device`，而不是 `offline` 或 `unauthorized`。
- **远程访问失败：** 验证私有网络、已保存的地址，以及 Mac 能到达接收端、
  接收端也能到达 Mac。
- **日志：** 使用 Mac 应用的“日志”操作，或 Android 的“设置与帮助” →
  “诊断”。分享前请删除私有地址和内容。

## 测试

```sh
xcodebuild test \
  -project ExtendPad.xcodeproj \
  -scheme OpenSidecarMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO

cd apps/android
./gradlew :core:test :app:testDebugUnitTest
```

自动化测试不能替代对物理显示器、输入、音频、USB 和网络的验证。请记录实际
测试过的内容。
