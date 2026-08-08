# Codex 一键汉化（Codex Desktop zh-CN Agent Installer）

> 让 Codex 的界面完整变成中文（左侧会话、新聊天、项目、计划、插件、设置、顶部菜单），全程离线，不登录 OpenAI 账号，不改原版安装，可一键恢复英文。
> Fully localize Codex Desktop to Chinese (sidebar, new chat, projects, plans, plugins, settings, native menus). Works offline with API-key mode. Never modifies the original install and is fully reversible.

---

## ✨ 一句话搞定（One-sentence setup）

### 方式 A：让 Codex agent 帮你装（推荐 / Recommended）

把下面这句话发给你的 Codex（需要先把本仓库克隆到本地，或用 Codex 打开本仓库目录）：

> 按本仓库 README 和 AGENTS.md 的说明，帮我把 Codex Desktop 界面汉化成中文。

或者让它自己拉取（网络可达时）：

> 克隆 https://github.com/ukinch605/codex-zh-cn-agent 并按照仓库里的说明帮我把 Codex 汉化。

### 方式 B：下载后双击（Fallback）

1. 下载 Release 中的 `codex-zh-cn-agent-v1.0.0.zip` 并解压；
2. 双击「安装汉化.bat」，UAC 弹窗点「是」，选 1 安装；
3. 完成后从桌面快捷方式「Codex 汉化版」或双击「启动汉化版.bat」启动。

---

## 中文完整指南

### 适用环境
- Windows 10 / 11
- Codex Desktop（Microsoft Store 版，已安装）

### 它能做什么
- 把网页主体（左侧会话、新聊天、项目、计划、插件、设置等）和原生菜单（文件/编辑/视图/帮助）全部变成中文；
- 使用 API Key 模式（不登录 OpenAI 账号）同样生效；
- 全程不需要联网 OpenAI。

### 怎么用
1. 获取本仓库：克隆，或下载 zip 解压到任意文件夹；
2. 用方式 A 对 Codex 说一句话，或双击「安装汉化.bat」；
3. 安装过程约 1-2 分钟（会复制一份程序），完成后 Codex 会自动重启为中文版；
4. 以后启动请用桌面快捷方式「Codex 汉化版」或「启动汉化版.bat」。

### 恢复英文
双击「恢复原版.bat」，然后从开始菜单打开 Codex 即可（原版从未被改动）。

### 卸载汉化
双击「卸载汉化.bat」，按提示确认。会删除汉化副本并恢复原配置。

### 常见问题
- **打开还是英文？** 先彻底关闭 Codex（任务栏右键退出），再双击「启动汉化版.bat」；仍不行就重跑「安装汉化.bat」。
- **Codex 自动更新后汉化失效？** 重新运行「安装汉化.bat」即可；如果提示“版本无法自动识别”，把窗口里的提示信息截图，到本仓库提 issue。
- **需要管理员权限吗？** 只需要安装/卸载时（复制商店安装目录会弹 UAC，点「是」）；日常启动不需要。
- **会改我的模型/API 配置吗？** 不会。本工具只写 `localeOverride = "zh-CN"`，不碰 `auth.json`、模型和密钥。

### 原理（给感兴趣的人）
1. 真正显示界面的是 `ChatGPT.exe`（`Codex.exe` 只是外壳）；
2. 网页中文由官方功能层 72216192 的 `enable_i18n` 开关控制，默认关闭、由服务端下发；
3. 本工具在 `app.asar` 中做两处等长原位修改强制打开开关，让程序加载内置 zh-CN 语言包；
4. 商店版不能原地修改，工具会复制一份到 `%USERPROFILE%\.codex\zh-cn-patched\` 再修改，原版保持不动。

### 免责声明
本工具为第三方汉化，仅供学习交流。不会修改账号、密钥或联网行为；卸载后完整恢复。

---

## English Quick Start

- **What**: A one-click launcher that forces Codex Desktop to use its built-in Chinese UI, and translates native Electron menus.
- **How**: Clone this repo and tell your Codex agent: *"Follow the README and AGENTS.md to localize my Codex Desktop to Chinese."* Or download the Release zip and double-click `安装汉化.bat`.
- **Safe**: It copies the Store install to `%USERPROFILE%\.codex\zh-cn-patched\` and patches the copy; the original is untouched. It only writes `localeOverride = "zh-CN"` and never touches `auth.json`, API keys, or model settings. Fully reversible via `恢复原版.bat` / `卸载汉化.bat`.
- **Requirements**: Windows 10/11, Codex Desktop from Microsoft Store. Admin (UAC) is needed only during install/uninstall.

## License
MIT