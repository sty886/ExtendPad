# 分支、发布与仓库独立性

MeowDisplay 作为独立产品进行管理：拥有自己的分支、版本、CI、发布和路线图。OpenDisplay 项目是可选的的外部参考（[REFERENCE.md](REFERENCE.md)），绝不是我们发布的来源。Git 历史、GPL-3.0 义务、版权声明和提交署名都完全保持原样。

## 分支模型

| 分支 | 角色 | 规则（`.github/rulesets/`） |
| --- | --- | --- |
| `main` | 最新**已发布** MeowDisplay 版本的精确来源；其标签 `vX.Y.Z` 指向发布提交。仅通过该发布的提升 PR 进行更改。落到 `main` 上永远不会发布任何东西。 | PR（仅合并提交）、必需检查、禁止删除或强制推送、无绕过 |
| `dev` | 活跃开发：功能、修复、Android 和 Mac 工作通过 PR 集成到这里。 | PR、必需检查、禁止删除或强制推送 |
| `release/<version>` | 一个发布在各平台的候选（RELEASE.md）。从已批准的 `dev` 基线创建；接收发布修复、QA 发现和分发准备工作；修复会被前向移植到 `dev`。每次推送都会构建候选；未经批准不会发布。 | 只有管理员可以创建（其自有规则集，因此管理员绕过仅覆盖创建）；PR、必需检查、禁止删除或强制推送。签名环境只允许 `release/*`，因此这决定了谁可以访问签名密钥 |
| `feature/*`、`fix/*`、`infra/*` | 短期工作，通过草稿 PR 进入 `dev`（发布修复则进入发布分支）。 | — |
| `reference/opendisplay` | 外部项目 `main` 的只读副本，仅由 `reference-sync.yml` 移动（快进、无标签）。绝不能作为功能或发布的基础。 | 仅快进、永不删除、无绕过（临时措施，直到专用 App 写入它） |
| `release-state` | 发布工作流的持久记录（`releases/<version>.json`）。不含源代码。 | 除其唯一绕过者——所有者的专用发布 App（`meowdisplay-release`，App ID 5582030）——外，任何人不得创建、更新、删除或强制推送；发布工作流使用该 App 的令牌 |

必需检查：`mac`、`release-tooling`、`android`（Tests）和 `conventional`（PR 标题）。

## 产品范围与分支

Windows 和 Linux 发送端或接收端（[#84](https://github.com/raiseCatError/meowdisplay/issues/84)、[#85](https://github.com/raiseCatError/meowdisplay/issues/85)）、企业远程管理（[#86](https://github.com/raiseCatError/meowdisplay/issues/86)）以及托管账户或中继（[#87](https://github.com/raiseCatError/meowdisplay/issues/87)）是未计划的想法，不是分支、开发目标或里程碑。欢迎对 MeowDisplay 的**商业使用**；参见 [PRODUCT_SCOPE.md](PRODUCT_SCOPE.md)。

### 文档与发布快照

已发布的标签 `vX.Y.Z` 及其指向的发布永不改变。发布后合并到 `dev` 的文档不会追溯修改该标签；它会随下一次发布的提升到达 `main`。如果文档必须更早到达 `main`，请使用单独的纯文档提升 PR（如 `promote/2.0.0-main` 所做的那样），绝不要使用携带未发布代码的 PR。不要仅仅为了包含文档而更改已冻结发布候选的提交。

发布工具链遵循同样的规则：仅手动触发和定时工作流从默认分支运行，因此对其的修复（`.github/workflows/release-*`、`scripts/release/`、`.github/rulesets/`、发布配置文件和发布文档）可以通过纯工具链提升 PR（如 `promote/release-tooling-main` 所做的那样）提前到达 `main`，绝不使用携带应用代码的 PR。随后将同一分支合并到 `dev`，以保持两者协调。

## 历史仓库迁移快照（2026-10-30）

本节记录迁移检查点，而非当前分支或发布可用性。自下文的 2.0.0 提升以来，`main` 是默认分支，`dev` 是开发分支；当前平台发布渠道见 [README.md](../README.md#platform-availability--november-2-2026)。

- `raiseCatError/meowdisplay` 是公开的，并且是 `peetzweg/opendisplay` 的 GitHub **网络分支**。
- **默认分支：`legacy/dev-opendisplay-next`**（`3f24b51`），即原 `dev/opendisplay-next`，重命名以便 `dev` 能够存在（Git 无法在同一目录下同时保留 `dev` 和 `dev/…`）。一旦发布工作流的恢复和商店安全修复进入 `dev`，且定时工作流被确认不活动，它就会变成 `dev`。
- **`dev`**（在 `3f24b51` 创建）通过 PR 接收 2.0 集成（`feature/v2-hotspot-parity`，位于 `52727ce`）；之后每次更改都通过 PR 到达。
- **`main` = `a186369`**：fork 点时外部项目的树。**它与 MeowDisplay 的线没有共同历史**，后者的第一个提交是 `94aaa88`（2026-09-24）；`main`、继承的标签以及两个重启前的标签 `pairing-encryption-v1` 和 `pre-testflight-ultrareview-2026-09-17` 持有那段更早的历史，永远不会被删除。其继承的 `release.yml` 和 `pages.yml`（以及旧默认分支的 `app-store-candidate.yml`）已在 Actions 设置中**禁用**。
- **`release/app-store-rc` = `65d46e8`**：v1.20.0（`cbbad7f`）的来源及其后续修复；包含在 `52727ce` 中。
- 开放的 PR #19、#24–#28 和 #30 都包含在 `52727ce` 中，并在集成 PR 合并后作为已包含项关闭。
- 一个 GitHub Release：**MeowDisplay 1.20.0 for Mac**（Latest），其资产是线上 Sparkle 更新源。
- 规则集：“Protect Main Branch”、“Protect development branch”（现在同时覆盖旧分支名和重命名后的分支名）以及 `.github/rulesets/` 中的规则集（一旦应用）。必需检查：`mac`、`release-tooling`、`conventional`、`android`。

## 2.0.0 的稳定提升（2026-11-02）

- `v2.0.0`（`3a9bc81`，`release/2.0.0` 的合并）是已发布的版本；标签永不移动。
- `main` 的旧 head `a186369` 已经在 `v2.0.0` 的祖先中（它通过早期合并进入了 MeowDisplay 的线），因此第 10 步不需要 `commit-tree`：提升分支 `promote/2.0.0-main` 是 `v2.0.0` 与 `dev` 标签后文档的合并，通过 PR 合并到 `main`。文档以外的每个文件（`*.md`、`assets/readme/`、`.github/FUNDING.yml`）都与 `v2.0.0` 相同；树中不存在任何继承的 `release.yml`/`pages.yml`，上游历史和作者保留在 `main` 的祖先中。
- 同一提升分支也会合并到 `dev`，将发布提交（版本、变更日志、发布配置）带回开发。
- 默认分支是 `main`。开发 PR 以 `dev` 为目标；发布修复进入 `release/<version>` 并合并回 `dev`；下一个发布按 `release/<version>` → `main` 提升。
- `release-stores` 环境允许 `main` 和 `release/*`（在 `dev` 为默认分支时它曾允许 `dev`），与工作流中的 `"$DEFAULT_BRANCH,release/*"` 检查一致。

## Fork 关系：运营独立性与 GitHub 元数据

作为网络分支是 GitHub 元数据：它将仓库分组，在某些工具中建议父仓库作为 PR 基础（`gh pr create` 需要 `-R raiseCatError/meowdisplay`），并共享 Git 对象存储。它不授予外部项目访问我们的分支、机密、Actions、发布或设置的权限，我们的任何工作流也不依赖它。

运营独立性（本文档和 RELEASE.md）不需要改变 fork 关系。分离 fork、重命名、转移或替换仓库是独立的决策，各有其风险（发布资产 URL、Sparkle 更新源重定向、App Store 和网站链接都指向 `raiseCatError/meowdisplay`），并且**不**属于本次迁移的一部分。

## 迁移风险

| 风险 | 为何重要 | 迁移序列中的缓解措施 |
| --- | --- | --- |
| 任何落到今天的 `main` 上的内容都会运行外部项目的 `release.yml` 和 `pages.yml` | release-please 可能打开或创建一个发布；没有更新源的 Latest 发布会让每台已安装 Mac 的更新返回 404 | 在携带 MeowDisplay 仅手动触发工作流的提交到达之前，不会有任何东西落到 `main` 上：第一次提升是 2.0.0 通过新流水线发布 |
| `release/app-store-rc` 未受保护 | 已发布的源代码可能被强制推送或删除 | 先保护它（第 1 步） |
| 工作流文件必须存在于默认分支上才能被手动触发，而定时工作流只在那里运行 | 否则监控、同步和守卫无法运行 | `dev` 尽早成为默认分支（第 6 步），2.0.0 之后是 `main`（第 13 步） |
| 堆叠 PR #24 → #25 → #26 | 乱序重定向或压缩会重放或丢失已审查的更改 | 按审查顺序以合并提交合并；仅在父 PR 合并后重定向每个 PR |
| 机密可被任何分支上的任何工作流读取 | 来自另一分支的工作流（或参考分支的文件）可能读取签名密钥 | 将它们移入仅限 `release/*` 的环境；删除仓库级副本 |
| 发布状态和参考分支 | 手动推送可能损坏状态或导入外部代码 | 将写入限制到工作流需要一个 GitHub 在用户所属仓库上接受的绕过操作者：GitHub 自己的 Actions 应用（integration 15368）会被拒绝（“must be part of the ruleset source or owner organization”）；所有者创建并安装的 GitHub App 会被接受。在没有这样一个 App 的情况下，任何持有 `contents: write` 的东西都可以写入 `release-state`：所有者，以及本仓库任何分支上被授予 `contents: write` 的任何工作流（其 `GITHUB_TOKEN`）。因此 **`release-state` 采用故障关闭**（任何人不得创建或更新它），直到所有者的发布 App 存在并成为其唯一绕过者；届时发布工作流会用该 App 的令牌写入它。无论谁可以写入它，发布过程都从不信任它：publish-mac 和每次恢复都需要 `release-publish` 批准，并且在发布任何内容之前，会重新推导商店对记录构建的实时批准、针对此确切提交且带有记录哈希的 GitHub Release，以及此提交的成功 publish-mac 作业（`verify-live`、`verify-resume`）。`reference/opendisplay` 暂时仅允许快进且永不删除：更新只能使其前进，同步在推送前会验证外部 head |

## 迁移序列

每一步都可逆，不重写任何历史，也不强制推送任何内容。⚑ = 所有者的批准或账户。

1. ✅ ⚑ 禁用继承的 `release.yml`、`pages.yml` 和 `app-store-candidate.yml`（Actions 设置）。重新启用其中任何一个都需要单独的安全审查。
2. ✅ ⚑ 在将新名称加入其规则集后，将 `dev/opendisplay-next` 重命名为 `legacy/dev-opendisplay-next`（相同提交、相同保护；PR #19 和 #24 会自动重定向）。
3. ✅ 在 `3f24b51` 创建 `dev`。
4. ⚑ 从包含 `.github/rulesets/*.json` 的检出中应用它们（`scripts/release/apply-rulesets.sh`，然后 `--apply`），包括 `tags.json`（永不删除或移动任何标签）。旧的两个规则集保留。
5. ⚑ 创建受保护环境并将签名机密移入其中（RELEASE.md § 凭据）；在删除每个仓库副本之前，先证明其替代品工作正常。
6. 一旦包括 Android 在内的所有必需检查在确切的 `52727ce` 树上通过，就合并 2.0 集成 PR（`feature/v2-hotspot-parity` → `dev`）。将 #19、#24–#28 和 #30 作为已包含项关闭。
7. ⚑ 在发布工具链修复进入 `dev` 且定时工作流被确认在没有其变量时不活动后，将默认分支设为 `dev`。设置 `EXPECTED_DEFAULT_BRANCH=dev`。
8. ⚑ 启动参考分支（手动触发一次 **Reference sync**；审查后设置 `REFERENCE_SYNC=enabled`）。
9. ⚑ 在协调 QA 后从 `dev` 切出 `release/2.0.0`；随后是发布 PR 和候选流水线（RELEASE.md）。
10. ✅ ⚑（2.0.0 已通过普通 PR 合并完成；见上文）仅在批准的公开发布时，**在不重写 `main` 的情况下协调它**：一个提升分支，其单个提交具有 `v2.0.0` 的树和两个父提交 `v2.0.0` 与 `main`（`git commit-tree 'v2.0.0^{tree}' -p v2.0.0 -p main`），通过 PR 合并到 `main`。这样 `main` 的树就等于该标签的树，上游历史及其作者保留在 `main` 的祖先中，且新树中不存在任何继承的工作流。普通的 `--allow-unrelated-histories` 合并会产生冲突并保留仅 `main` 的文件；重置 `main` 将是强制推送：两者都不采用。后续发布按正常方式将 `release/<version>` → `main` 提升。
11. ✅ ⚑ 发布后将默认分支设为 `main`；开发 PR 继续以 `dev` 为目标。发布修复在 `release/<version>` 上进行并合并回 `dev`。
12. ⚑ 仅根据重新验证的清单和明确列表进行分支清理：提交在其他地方不存在的分支首先归档为标签；`main`、每个标签和 `legacy/dev-opendisplay-next` 保留。

## 本次变更不影响的内容

已发布的 v1.20.0 版本、其标签、资产和 URL；线上 Sparkle 更新源；bundle 标识符、Keychain 组、Bonjour 服务类型（`_opensidecar._tcp`）、协议标识符、Xcode target 和 scheme 名称（`OpenSidecar*`）、签名元数据。这些是兼容性契约；重命名其中任何一项都是一次独立且有正当理由的迁移。
