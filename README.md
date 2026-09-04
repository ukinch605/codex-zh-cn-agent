# Codex 一键汉化（Codex Desktop zh-CN Agent Installer）v1.3.8

> 让 Codex 的界面完整变成中文（左侧会话、新聊天、项目、计划、插件、设置、顶部菜单），全程离线，不登录 OpenAI 账号，不改原版安装，可一键恢复英文。
> Fully localize Codex Desktop to Chinese (sidebar, new chat, projects, plans, plugins, settings, native menus). Works offline with API-key mode. Never modifies the original install and is fully reversible.

---

## ✨ 一句话搞定（One-sentence setup）

### 方式 A：让 Codex agent 帮你装（推荐 / Recommended）

把下面任一句发给你的 Codex：

- 推荐（还没下载仓库，最省事）：克隆 https://github.com/ukinch605/codex-zh-cn-agent 并按照仓库里的 README 和 AGENTS.md 的说明，帮我把 Codex Desktop 界面汉化成中文。
- 已经用 Codex 打开本仓库目录：按本仓库 README 和 AGENTS.md 的说明，帮我把 Codex Desktop 界面汉化成中文。

> 仓库拉取由 agent 自动完成（git clone 失败会自动回退到 zip 下载）；只有完全离线时才需要先把仓库克隆到本地或用 Codex 打开仓库目录。

Codex 会按 `AGENTS.md` 的流程自动完成：拉取仓库 → 检测版本 → 安装（弹一次 UAC，点「是」）→ 自动重启为中文版（几秒内完成）→ 安装入口自动切换助手 → 验证并汇报。以后从任何入口打开 Codex 都会自动是中文版。

### 方式 B：下载后双击（Fallback）

1. 下载 Release 中的 `codex-zh-cn-agent-v1.3.8.zip` 并解压；
2. 双击「安装汉化.bat」，UAC 弹窗点「是」，选 1 安装；
3. 完成后从桌面快捷方式（中文系统为「Codex 汉化版」，其他语言系统为「Codex zh-CN」）或双击「启动汉化版.bat」启动。

---

## 版本兼容性（Version compatibility）

汉化原理依赖 Codex 内置代码中的特征串，因此与具体版本相关。下表记录已真机测试通过的版本；新版本由维护者测试后追加。

| Codex 版本 | 测试日期 | 状态 | 备注 |
| --- | --- | --- | --- |
| 26.803.5235.0 | 2026-08-08 | ✅ 通过 | 本仓库 v1.3 收录 |
| 26.803.10989.0 | 2026-08-14 | ✅ 通过 | 应用内版本 26.803.81509；本仓库 v1.3.1 起收录 |
| 26.818.5229.0 | 2026-08-23 | ✅ 通过 | 本仓库 v1.3.5 起收录（26.818 新版本线） |
| 26.818.8289.0 | 2026-08-24 | ✅ 通过 | 本仓库 v1.3.7 收录 |
| 26.820.7780.0 | 2026-08-26 | ✅ 通过 | 本仓库 v1.3.7 收录 |
| 26.831.1445.0 | 2026-09-02 | ✅ 通过 | 本仓库 v1.3.7 收录（pnpm 长路径修复后实测） |
| 26.901.4073.0 | 2026-09-04 | ✅ 通过 | 本仓库 v1.3.7 收录（26.901 新版本线） |
| 26.901.2854.0 | 2026-09-04 | ✅ 通过 | 本仓库 v1.3.8 收录 |

> 你的版本不在表里？安装器会先做通用特征探测，大多数情况下仍能自动安装；只有结构变化过大才会报「版本无法自动识别」，此时请按下方「故障排查与反馈」提交诊断文件。
>
> 通用探测安装成功时会自动导出候选特征串（`%USERPROFILE%\.codex\zh-cn-agent\logs\candidate-<版本>.json`），把该文件提交 issue 即可让维护者快速收录新版本，让工具持续跟上 Codex 更新。

## 更新策略（Update strategy）

- **默认完全离线**：安装、汉化、启动均不联网，也不访问 OpenAI。
- **跟随 Codex 更新**：商店版 Codex 自动更新后，重新运行一次「安装汉化.bat」选 1 即可（安装器检测到版本变化会自动重建汉化副本）。
- **可选在线更新（默认关闭）**：双击「检查更新.bat」，工具会自动对比 GitHub 最新 Release，有新版本时下载并重新安装（仅一次 UAC）。断网时会提示“离线模式”，不影响已有汉化。
- **遇到「版本无法自动识别」**：说明新版代码结构有变化，请把诊断文件内容提交 issue（见下方反馈方式），维护者更新特征串后即可支持。

## 它能做什么 / 不做什么

- 把网页主体（左侧会话、新聊天、项目、计划、插件、设置等）和原生菜单（文件/编辑/视图/帮助）全部变成中文；
- 使用 API Key 模式（不登录 OpenAI 账号）同样生效；
- 安装时把商店版复制到 `%USERPROFILE%\.codex\zh-cn-patched\` 再打补丁，**原版安装从未被改动**；
- 只写入 `localeOverride = "zh-CN"`，不碰 `auth.json`、API Key、模型和任何账号配置；
- 安装结尾采用「过渡监督式重启」：以普通用户权限启动汉化副本、防止原版进程抢回、失败自动重试；验证稳定后立即退出，无任何后台驻留，全程写日志与结果文件；
- 安装后附带「入口自动切换助手」（登录自启、事件驱动、不联网、占用可忽略）：以后从开始菜单/任务栏/商店瓦片打开 Codex，约 1~2 秒内自动切换为中文版；助手每 5 分钟自检一次，进程意外终止后最多 5 分钟自动恢复，不会出现"静默失效"；恢复原版/卸载时自动移除；
- 安装/卸载时自动清理旧版本汉化副本，磁盘占用保持在一个程序副本的量级（约 1.7GB），不会随 Codex 更新和聊天记录累积而膨胀；
- 卸载后完整恢复英文，无残留。

## 常见问题（FAQ）

- **打开还是英文？** 安装后从任何入口打开 Codex 都会在约 1~2 秒内自动切换为中文版（原版英文窗口会短暂出现后被自动替换，属正常现象）。若未生效，先彻底关闭 Codex（任务栏右键退出），再重跑「安装汉化.bat」。
- **GitHub 打不开 / 下载不了仓库？** agent 会自动按「GitHub 直连 → 备用域名 → 镜像站」的顺序尝试，全程不会改动你的网络设置；如果全部失败，会明确告诉你改用离线包：从 Release 下载 `codex-zh-cn-agent-v1.3.8.zip`（可以请朋友帮忙下载后传给你），解压后双击「安装汉化.bat」即可，全程不需要访问 GitHub。
- **桌面快捷方式叫什么？** 中文系统为「Codex 汉化版」，其他语言系统为 ASCII 名「Codex zh-CN」；双击它可直接启动中文版。
- **Codex 自动更新后汉化失效？** 重新运行「安装汉化.bat」选 1 即可；如果提示“版本无法自动识别”，按下方反馈方式提交诊断文件。
- **需要管理员权限吗？** 只需要安装/卸载时（复制商店安装目录会弹 UAC，点「是」）；日常启动不需要。
- **会改我的模型/API 配置吗？** 不会。只写 `localeOverride = "zh-CN"`。
- **会不会越用越臃肿？** 汉化副本只是程序本体的可写拷贝（约 1.7GB）；聊天记录存储在共享的 `%USERPROFILE%\.codex\` 下，不会写入副本。Codex 更新后旧版本副本会被自动清理，磁盘占用不会持续膨胀。
- **第一次安装为什么有点慢？** 需要把约 1.7GB 的程序复制一份并打补丁，杀毒软件扫描还可能造成几十秒延迟，1~3 分钟属正常，请耐心等待不要中断。
- **日志显示“事件监听不可用，已进入定期扫描模式”？** 部分受限环境无法注册系统事件监听，助手会自动改用每 10 秒扫描兜底，切换延迟最长约 10 秒，功能不受影响。
- **每几分钟闪一个命令行窗口？** v1.3.5 及更早版本中，这是入口助手每 5 分钟自愈触发造成的短暂闪现，属正常现象、不影响使用；v1.3.6 起改为完全隐藏启动，不再闪现。
- **会有常驻后台吗？** 安装后会有一个登录自启的轻量「入口自动切换助手」，仅在检测到原版入口被打开时动作，不联网、不自动打开 Codex、不读取任何账号数据；助手每 5 分钟自愈一次，即使进程被意外终止也会自动恢复；可随卸载/恢复原版一并移除。
- **工具装在哪个固定目录？** `%USERPROFILE%\.codex\zh-cn-agent\`；桌面快捷方式指向该目录，仓库文件夹删除后汉化入口仍可用。

## 故障排查与反馈（Troubleshooting & feedback）

- 安装日志：`%USERPROFILE%\.codex\zh-cn-agent\logs\install-*.log`
- 启动日志与结果：`%USERPROFILE%\.codex\zh-cn-agent\logs\launch-*.log` 与 `%USERPROFILE%\.codex\zh-cn-agent\launch-result.json`
- 版本无法识别的诊断文件：`%USERPROFILE%\.codex\zh-cn-agent\logs\diagnostic-<版本>.txt`
- 安装卡在“复制”阶段、报“未能找到路径的一部分”：新版 Codex 含 pnpm 长路径 junction，旧版工具的 Copy-Item 无法复制；请升级到 v1.3.7+（改用 robocopy /XJ 复制）。
- 提交 issue 时请附上诊断文件/日志的完整内容，并注明 Codex 版本（开始菜单或 `Get-AppxPackage | Where-Object Name -match Codex` 可查看）。

## 原理（给感兴趣的人）

1. 真正显示界面的是 `ChatGPT.exe`（`Codex.exe` 只是外壳）；
2. 网页中文由官方功能层 72216192 的 `enable_i18n` 开关控制，默认关闭、由服务端下发；
3. 本工具在 `app.asar` 中做两处等长原位修改强制打开开关，让程序加载内置 zh-CN 语言包；
4. 商店版不能原地修改，工具会复制一份到 `%USERPROFILE%\.codex\zh-cn-patched\` 再修改，原版保持不动；
5. 特征串维护在 `versions.json`，未知版本走通用探测，仍失败则产出诊断文件。
6. 安装完成后的重启由监督脚本完成：关闭旧进程 → 以普通权限启动汉化副本 → 验证稳定后立即退出（不驻留），全过程写入日志与 `launch-result.json`；桌面快捷方式名按系统代码页选择（中文系统「Codex 汉化版」，其他系统 ASCII 名「Codex zh-CN」），保证英文系统可正常创建。
7. 汉化副本按版本哈希命名；安装/卸载时自动清理旧版本副本，避免磁盘持续膨胀。
8. 为让“从任何入口打开都是中文”，安装时另装一个登录自启的入口助手：事件驱动监听 codex/chatgpt 进程，发现原版被打开时自动关闭并拉起汉化副本；不联网，恢复原版/卸载时移除。

## 目录结构

```text
安装汉化.bat / 启动汉化版.bat / 恢复原版.bat / 卸载汉化.bat / 检查更新.bat
scripts/install-zh-cn.ps1       # 安装/状态/验证/卸载/测试入口（含结果文件协议）
scripts/launch-zh-cn.ps1        # 启动汉化版（过渡监督式重启：日志 + 结果文件 + 失败重试）
scripts/entry-guard.ps1         # 入口自动切换助手（登录自启、事件驱动、不联网）
scripts/restore-original.ps1    # 恢复英文原版
scripts/check-update.ps1        # 可选在线更新（默认关闭）
scripts/publish-release.ps1     # 生成 Release zip（维护者用）
scripts/tests/                  # 离线测试 + 夹具
versions.json                   # 已测版本 → 特征串表
.github/workflows/ci.yml        # CI：离线测试 + bat 编码校验
```

## 免责声明

本工具为第三方汉化，仅供学习交流。不会修改账号、密钥或联网行为；卸载后完整恢复。

---

## English Quick Start

- **What**: A launcher that forces Codex Desktop to use its built-in Chinese UI and translates native Electron menus.
- **How (agent)**: Clone this repo and tell your Codex: *"Follow the README and AGENTS.md to localize my Codex Desktop to Chinese."*
- **How (manual)**: Download the Release zip, extract, double-click `安装汉化.bat`, choose 1.
- **Safe**: It copies the Store install to `%USERPROFILE%\.codex\zh-cn-patched\` and patches the copy; the original is untouched. It only writes `localeOverride = "zh-CN"` and never touches auth.json, API keys, or model settings. Fully reversible.
- **Updates**: Re-run the installer after Codex updates; optional online update via `检查更新.bat` (offline by default).
- **Requirements**: Windows 10/11, Codex Desktop from Microsoft Store. Admin (UAC) is needed only during install/uninstall.

## License

MIT
