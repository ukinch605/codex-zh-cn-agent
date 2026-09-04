# 研究线：26.900+ 受保护版本（README 只读存档，不承诺交付）

> 本目录用于沉淀“26.900+ 离线汉化”相关研究结论与可复现命令。
> 任何研究突破必须经维护者确认后才能转正式功能并发布。

## 已确认事实（2026-09-04，26.901.2854.0 / 26.901.4073.0）

- E1：对汉化副本（打补丁的 app.asar）启动，约 2~5 秒后主动退出。
  ExitCode = -2147483645（0x80000003 = STATUS_BREAKPOINT）。
- E2：同一副本换回原版 app.asar 后启动，稳定运行 >= 75 秒。
- E3：只把 app-initial JS 中一个 `return e` 的空格改为制表符（语义无影响），
  启动约 2 秒后同样以 0x80000003 退出。
  结论：官方对 app.asar 做“任何字节改动即退出”的整文件级保护，
  不是补丁语义问题，也不是复制/启动器问题。
- 本地缓存探测：在曾联网成功显示中文的机器上，遍历
  %APPDATA%\Codex 与 %LOCALAPPDATA%\OpenAI\Codex 全部文件，
  未发现 72216192 / enable_i18n 存档，开关疑似每次启动向服务端读取、不落本地。
- 代码证据：enable_i18n 在 app-initial（约 10.3MB）中仅出现 1 次，
  读取路径为 Statsig 功能层 72216192（VTn('72216192') -> a?.get('enable_i18n',!1)）；
  包内含完整 Statsig localStorage 提供器，但未见该 gate 落盘。

## 可继续探索的方向（不保证成功）

**最高优先：本地缓存预热/移植** —— 宿主机观察到“联网一次后显示中文”，
若开关/语言包状态缓存在本地 profile（%APPDATA%\Codex\web\Codex 的
localStorage/LevelDB），可在联网机上定位缓存落点 → 复制到离线环境验证是否
生效 → 若生效则研究最小化分发（只分发缓存文件，绝不带走账号/密钥）。
完全不碰 asar、不触发整文件校验，是最贴近国内目标用户的方向。

1. Statsig override：运行时通过 DevTools/console 查找 statsig 全局对象与
   override API，尝试本地覆盖 gate 72216192 的 enable_i18n。
2. CDP/运行时注入：启动原版后通过 DevTools Protocol 改写该读取点返回值
   （不落盘、不改 asar；需验证主窗口 webContents 可连接性）。
3. 再次核对不同 profile/分区缓存（codex-browser-app 分区、LevelDB 压缩值）。
4. 跟踪官方进展：设置中已出现“简体中文”，若其改为本地生效
   （不再依赖服务端开关），则 locale-only（localeOverride）即足够。

## 可复现命令（在受保护版本机器上执行，只读/可逆）

- 启动副本并观察退出码：见 E1/E2/E3 脚本（宿主机对话存档）。
- 缓存探测：
  findstr /S /M /C:"72216192" "%APPDATA%\Codex\*.*"
  findstr /S /M /C:"enable_i18n" "%APPDATA%\Codex\*.*"