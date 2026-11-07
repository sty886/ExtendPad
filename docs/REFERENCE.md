# OpenDisplay 参考

MeowDisplay 起源于 [OpenDisplay](https://github.com/peetzweg/opendisplay) 的一个分支，现在独立开发和发布（[BRANCHING.md](BRANCHING.md)）。OpenDisplay 是一个**外部参考**：值得阅读以获取修复和思路，但绝不是 MeowDisplay 的发布、版本或路线图的来源。它的历史、其 GPL-3.0 许可证以及贡献者署名都按原样保留在本仓库中。

凡两者不同之处，以 MeowDisplay 自身的设计为准：安全协议（pv 22：基于转录认证的配对、固定双向 TLS 1.3、按连接进行会话准入和输入授权）、接收端控制、统一 Mac 应用的角色，以及我们的性能要求。OpenDisplay 的版本号绝不设定 MeowDisplay 的版本号。

## `reference/opendisplay`

OpenDisplay `main` 的只读副本，由 `reference-sync.yml` 保持最新：

- 它检查外部仓库的固定身份（节点 `R_kgDOS2SYLQ`、`peetzweg/opendisplay`、默认分支 `main`），并检查抓取的提交是否与 GitHub API 报告的一致；
- 它只创建或快进 `reference/opendisplay`，绝不强制推送，也不抓取任何标签（外部项目的标签永远不会进入 MeowDisplay 的标签命名空间）；
- 它绝不合并、摘取（cherry-pick）、打标签、发布或触碰其他分支，也不持有任何机密；其推送使用 `GITHUB_TOKEN`，该令牌不会启动任何工作流，因此该分支上外部项目的工作流文件不会运行；
- 作业摘要和 `reference-sync` 产物记录外部提交、前一个提交以及结果（`created`、`fast-forwarded`、`unchanged`、`diverged`、`mismatch`）。

它在被手动触发时运行，并在仓库变量 `REFERENCE_SYNC` 为 `enabled` 后每天运行。其规则集只允许快进更新，绝不允许删除，且任何人都不享有绕过权限。（若要将更新仅限同步工作流，需要一个 GitHub 在用户所属仓库上接受的绕过操作者，即所有者自己的 GitHub App；GitHub 的 Actions 应用不是其中之一。等到发布 App 存在时再恢复：见 BRANCHING.md。）

**重写历史。** 如果 OpenDisplay 重写了 `main`（旧 head 不再是祖先），同步会以 `diverged` 停止，且不做任何更改。此时由人工：(1) 查看我们上游发生了什么变化；(2) 在当前 `reference/opendisplay` 上创建 `reference/opendisplay-archive/<date>` 以保留旧副本；(3) 为这一项有意的操作临时禁用参考规则集，将 `reference/opendisplay` 移动到新的外部 head，然后重新启用；(4) 在下方记录。产品分支绝不牵涉其中。

## 吸纳：决定采用什么

`reference-intake.yml`（手动触发，只读）对自上次审查以来的参考提交运行 `scripts/reference/intake.rb`。对于每个看起来像安全、可靠性、渲染/解码、平台兼容性或回归修复的变更，它会报告：外部 PR 或提交、其描述的问题、MeowDisplay 是否已有该变更（相同的补丁，或我们历史中的引用）、它是否触及协议、配对或传输代码、其所属领域（Mac、iOS、Shared、Android、Linux、发布工具链）以及一个建议的初始推荐。

由人工逐项决定：**ignore**（忽略）、**investigate**（调查）、**adapt**（我们自己的该思路实现）或 **port**（变更本身）。不会自动应用任何内容。被采纳的变更是一个进入 `dev` 的普通 MeowDisplay PR，带有自己的测试，并且：

- 绝不削弱安全协议（无明文传输、无更弱的配对、不依据发现元数据建立信任）；
- 在提交信息中以纯文本注明其来源，例如“Port of OpenDisplay reference PR 424”，绝不写成 `owner/repo#N`（那会交叉链接到外部项目）；
- 保留所复制内容的 GPL-3.0 头信息和作者署名，并在 PR 中说明复制了什么以及为什么没有优先采用我们自己的实现。

只有在有正当理由时才为候选项创建 issue 或草稿 PR，并且未经审查绝不合并。

## 台账

| 审查至 | 日期 | 报告 | 备注 |
| --- | --- | --- | --- |
| `v1.28.0` (`a7df481`) | 2026-10-26 | 2026-10-26 上游追赶审计（维护者笔记） | 已移植或比较：320、304、288（自研编解码协商）、219、392；有意不同：325。下一批候选：346、393（含 413 的容忍度）、399、323 |
| `bcf8e2b` | 2026-10-27 | 对 `v1.28.0..bcf8e2b` 运行 `intake.rb` | 一个候选：OpenDisplay 参考 PR 424（Mac 只向看起来像 Android 的 USB 设备询问配件模式）。**调查**以用于未来的 Android USB 绑定；MeowDisplay 目前没有 Android USB 路径。 |
