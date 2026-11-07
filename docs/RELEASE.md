# 发布流程

ExtendPad 发布包含 Mac 应用和 Android 接收端。发布从 `release/<version>` 分支构建，并且只有在通过所需的验证和发布门槛后才会提升到 `main`。

## 版本管理

`version.txt`、`.release-please-manifest.json` 和 `CHANGELOG.md` 必须与发布分支一致。Git 标签使用 `vX.Y.Z`；现有标签绝不移动。

Android version codes 单调递增。Mac 的营销版本和构建版本来自发布配置。本地构建默认为 `0.0.0`，不是发布产物。

## 候选流水线

每次推送到 `release/<version>` 都会运行 `.github/workflows/release-candidate.yml`：

1. `plan` 验证分支、版本以及不存在现有标签，然后记录确切的候选提交。
2. `mac` 构建、签名、公证并验证发送端和接收端 DMG 及其更新源。
3. `android` 运行测试和 lint，构建并签名发布包，然后将其上传到配置的测试轨道。
4. `summary` 报告就绪状态，但不发布。

更新的推送会取消旧的候选运行。构建和上传作业不会创建 GitHub release 或标签。

## 凭据与环境

发布凭据只存在于其各自预期的受保护 GitHub 环境中。工作流在访问机密前会使用固定版本的 action 和环境检查。绝不要为了方便而将签名或商店凭据复制到仓库级机密中。

使用 `scripts/release/release-secrets.rb status` 进行不披露敏感信息的状态检查。`apply-environments.sh` 和 `apply-rulesets.sh` 需要显式的 `--apply` 和仓库管理权限。

Android 生产发布需要生产审查轨道和单独的、按版本设置的 `ANDROID_PRODUCTION_AUTHORIZED` 值。测试轨道不计为公开可用。

## 发布

`release-publish.yml` 仅支持手动触发，并从匹配的发布分支在已审查的候选提交上运行。其按序阶段为：

1. 验证候选和所需的商店状态。
2. 验证确切的 Mac 产物和更新源，创建并验证 release，然后将其设为 Latest。
3. 完成已授权的 Android 发布。Managed publishing 可能需要执行明确的 Play Console Publish 操作。
4. 发布网站清单，仅包含已确认上线的平台。
5. 提议将已发布的源代码提升到 `main`。
6. 记录已发布或待定状态，而不隐藏未完成的工作。

恢复需要相同的发布批准，并重新验证线上 release、产物哈希和商店状态。Mac 更新源验证失败时，会恢复之前的 Latest release，而不是留下可见的部分更新。

## 本地验证

```sh
ruby scripts/release/check-release-workflows.rb
ruby -Iscripts/release/lib -e \
  'Dir["scripts/release/test/*_test.rb"].sort.each { |f| require File.expand_path(f) }'
```

同时运行 Mac 和 Android 测试，并在可能的情况下检查物理设备行为。不要将源代码审查、自动化测试、模拟器测试和物理 QA 说成可以互换。

## 分支规则

参见 [BRANCHING.md](BRANCHING.md)。开发以 `dev` 为目标；发布修复进入发布分支并合并回来。已发布的标签和发布资产是不可变的兼容性契约。
