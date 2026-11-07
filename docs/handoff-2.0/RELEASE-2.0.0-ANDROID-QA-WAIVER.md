# MeowDisplay 2.0.0：Android 物理 QA 豁免

**状态：所有者已批准豁免（2026-10-31）。未执行，未通过。**

## 决定

对于 2.0.0 发布候选版本，所有者决定不需要额外的
Android 物理 QA。Android 作为必需平台参与协调的
2.0.0 发布（`.github/release-config.json` 中的 `crossPlatformReady: true`、
`requiredPlatforms: ["mac", "ios", "android"]`）。

该决定基于已有证据：

- 开发和模拟器测试；
- 自动化测试（`dev` 上 `Tests` 的 `android` 任务）；
- 早先在 Moto 上的物理设备测试，记录在
  [COMPLETION-MATRIX.md](COMPLETION-MATRIX.md) 中，并附有其日期和
  限制（例如，物理键盘/鼠标和折叠屏检查在那里记录为 PARTIAL 或 BLOCKED）。

## 豁免涵盖的内容

仅涵盖此候选版本额外的 Android 设备手动 QA。2.0.0 未运行任何新的
Android 物理检查，也不得报告任何检查已运行或通过。

## 豁免不涵盖的内容

该豁免不绕过任何其他保障。Android 仍必须通过：

- 发布 lint 和自动化测试套件；
- 针对已注册上传证书（`6a9ac078…338e94`）的上传密钥签名验证；
- versionCode 高于 Google Play 已有的所有构建；
- 在配置的审核轨道（`alpha`）上进行 Google Play 审核；
- 发布门禁：等待 Mac、iOS 和 Android 针对同一发布提交获批，
  然后等待所有者的最终批准（`publishMode: manual-final-approval`）。
