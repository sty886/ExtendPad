# 接收端控制

ExtendPad 接收端默认支持仅查看，并在发送输入前需要按会话获得 Mac 所有者的授权。

## Android

Android 提供直接触控和触控板模式、可自定义的控制托盘和功能托盘、配置档、组合键、键盘/鼠标输入，以及针对手机、平板和折叠屏的自适应布局。本地缩放和平移无需输入权限。参见 [../apps/android/RECEIVER_CONTROLS.md](../apps/android/RECEIVER_CONTROLS.md)。

## Mac 接收端

当视频窗口处于活动状态且发送端 Mac 已授予控制权时，Mac 接收端转发键盘和触控板事件。它使用与 Android 相同的共享会话、输入和撤销规则。输入不会被全局捕获。

## 通用规则

- 连接和控制是两项独立的权限。
- 每个连接开始时都没有输入授权。
- 暂停、撤销、忘记和连接替换都会停止输入，并释放按住的键、按钮和手势。
- 接收端本地的布局和视口状态保留在接收端上。
- 由 Mac 决定哪个显示器或窗口接收已批准的输入。

实现细节位于 `packages/shared/`、`apps/android/core/src/main/kotlin/` 和 `apps/macos-receiver/ReceiverInputForwarding.swift`。
