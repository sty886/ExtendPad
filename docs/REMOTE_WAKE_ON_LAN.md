# 远程唤醒局域网（Wake-on-LAN）— 中继设计（中继尚未实现）

这是一份针对 Tailscale 远程里程碑的本地设计说明。它有意不作为上游项目文档。

## 当前状态

**唤醒并连接已发布，但仅限 Mac 的本地网络。** 接收端通过一个已经过认证的会话获知一台已配对 Mac 的 MAC 地址和广播地址（`Shared/WakeOnLAN.swift` 中的 `WakeMetadata`），随后 `Shared/WakeConnectCoordinator.swift` 发送标准的 Wake-on-LAN UDP 广播，请求 Mac 连接，并请求提升为交互式唤醒。只有当固定且双向认证的 TLS 对端与目标 Mac 匹配时，该尝试才会成功。它要求 Mac 启用“网络访问唤醒”，适用于已登录且处于睡眠或锁定状态的 Mac，不覆盖冷启动。

**下文描述的中继仍未实现。** 魔法包永远不会通过 Remote/Tailscale 路由，因此无法从外部唤醒位于另一个网络上的睡眠 Mac。对已唤醒 Mac 的远程连接与此无关，可独立工作。

## 为什么这很难

Tailscale 让 iPhone 获得通往 Mac tailnet 地址的路由 IP 连接，但那是叠加网络路径，而不是 LAN 网段。传统的 Wake-on-LAN 是在 Mac 的*本地*以太网/Wi-Fi 网段上传递的二层广播（或单播）魔法包。tailnet 对端无法直接发出该数据包——它不在同一个广播域中，而且 Tailscale 默认不桥接二层。

## 模型

```
iPhone
  → Tailscale (routed IP, already-authenticated tailnet peer)
  → an always-on relay device on the Mac's LAN (also on the tailnet)
  → ordinary Wake-on-LAN magic packet, sent locally
  → Mac wakes
  → MEOW's normal Remote reconnect takes over from here
```

中继可以是任何已经接入 Mac 家庭网络并注册到同一 tailnet 的常开设备：树莓派、NAS、另一台 Mac，或者可能是路由器——但路由器集成被推迟，需先调查用户硬件（例如 TP-Link Archer AX5400/AX73 级别的设备）是否提供安全、稳定且经过认证的机制。在验证之前，不应假定存在此类机制。

## 未来任何实现的硬性约束

- 中继只能唤醒用户显式登记过的 MEOW 设备（其自己已配对 Mac 的 MAC 地址），绝不能唤醒手机在请求时提供的任意主机。
- 不开放公共 UDP WoL 端口。中继只接受来自已认证 tailnet 对端的唤醒请求。
- 不提供通用的远程命令执行面——中继唯一暴露的动作是“发送这一个预先配置好的魔法包”。
- 唤醒是尽力而为的：支持的情况是睡眠 → 唤醒。完全关机的 Mac 的冷启动不在范围内，且不得作出承诺。

## 期望的最终 UI 状态

```
Awake/reachable   → Connect
Asleep/wakeable   → Wake
Offline/no relay  → Offline
```

这些由中继支撑的状态尚未接入。`ConnectionRoute` 以及远程候选/连接路径不依赖唤醒状态；当 Mac 不可达时，它们只会以清晰的“peer unreachable”/“Mac asleep”诊断失败（参见远程里程碑的第 7 阶段），与任何其他不可达路由的情况完全相同。

## 为什么中继尚未实现

构建中继（协议、登记、认证以及运行位置）是一块独立的常开基础设施，具有自身的安全面。将其并入第一个远程连接里程碑，可能会破坏该里程碑实际要验证的核心路径：“手机通过 Tailscale 到达已唤醒的 Mac”。这是有意划出范围的，而不是疏忽。
