# MeowDisplay：产品范围与构想

**让 Mac 无处不在，显示在各种屏幕上**

MeowDisplay 是**以个人为先的显示与控制工具**。它让你在已有的设备上以
另一种方式查看和使用 Mac。优先事项是出色的交互、可靠的显示模式、清晰的
权限控制、隐私和良好性能——而不是管理他人的电脑。

## MeowDisplay 是什么

- **Mac 发送端：** 镜像 Mac 屏幕、创建扩展的 Mac 工作区，或在窗口视图中
  使用各个 Mac 窗口。
- **接收端：** Android 和 Mac，各自具备
  [PARITY.md](PARITY.md) 中记录的功能。
- **直接设备连接：** 在支持的情况下使用 USB、本地网络，或通过
  Tailscale 等私有网络进行远程访问。配对、对端身份
  和权限控制至关重要；见 [SECURITY.md](../SECURITY.md)。
- **同样适用于工作。** 欢迎个人、设计师、开发者和其他
  专业人士将其用于商业用途或工作场所。
  **以个人为先是一种设计重心，而不是禁止商业使用的限制。**
  实际的许可权利和义务见 [LICENSE](../LICENSE)
  （GPL-3.0），本说明不构成许可条款。

## MeowDisplay 不打算成为什么

MeowDisplay **目前并不是作为企业远程
桌面、远程服务台或 IT 设备群管理产品来开发的**。用户
管理、组织身份、无人值守的设备群注册、集中
监控和托管支持服务都超出了预期范围。
这并不禁止使用**你自己的已授权 Mac** 进行远程工作。

MeowDisplay 目前也不要求或运行开发者托管的
云账户、媒体中继或集中式设备目录。通过用户自选网络进行的远程访问
不是托管式 MeowDisplay 远程服务。

**不计划提供 Windows 和 Linux 的发送端/接收端应用。** 维护者
专注于直接使用和可测试的平台，而移植到新的操作系统
会带来大量持续的维护和兼容性工作。
如果情况发生变化，可能会重新考虑这些想法；但不会附带路线图、资金
门槛或实现承诺。

## 在哪里讨论不同方向

以下公开 issue 是**讨论跟踪器，而不是工作承诺**：

| 方向 | 讨论 |
| --- | --- |
| Windows 发送端或接收端 | [#84](https://github.com/raiseCatError/meowdisplay/issues/84) |
| Linux 发送端或接收端 | [#85](https://github.com/raiseCatError/meowdisplay/issues/85) |
| 企业远程桌面或 IT 管理 | [#86](https://github.com/raiseCatError/meowdisplay/issues/86) |
| 托管账户、中继或集中同步 | [#87](https://github.com/raiseCatError/meowdisplay/issues/87) |

针对**受支持**应用的具体请求和推测性想法使用
不同的 [GitHub issue 表单](../CONTRIBUTING.md)。维护者可能根据产品方向
和能力阅读、讨论、推迟、拒绝或关闭建议。**建议或 issue 并不保证会被考虑、
实现、支持或安排发布时间。**

## 范围与发布状态

想法跟踪器并不能说明某项功能是否已在发布的构建中可用。已实现的行为和
分发状态见 [README](../README.md)、[接收端功能对等](PARITY.md)
和实际的 [发布](https://github.com/raiseCatError/meowdisplay/releases)。

发布遵循 [RELEASE.md](RELEASE.md)。商店上传、审核、批准、
测试轨道和公开生产是不同的状态：在相应的
商店或 GitHub Release 实际确认之前，任何文档都不应声称某个平台
已向公众提供。当前源码支持 Mac、
Mac 接收端和 Android。
