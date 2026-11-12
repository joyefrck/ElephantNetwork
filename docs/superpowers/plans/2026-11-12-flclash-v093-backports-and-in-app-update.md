# 大象网络底层修复与应用内升级实施方案

> 执行方式：在当前会话按任务分批实施，使用仓库现有 UI、Core/平台、本地化与测试技能；本机未安装单独的 executing-plans 技能。

**Goal:** 分批移植 FlClash v0.9.3 及此前尚未覆盖的稳定性改进，完成四个平台的应用内下载和安装，保持大象网络的四个主菜单及顺序，暂不发版。

**Architecture:** 以 `ab76ad5ee7fd0d2a14569fcc6ec7535368be2122` 为基线，保留大象网络现有 Flutter 界面、账号、受管订阅和分发体系。底层按依赖分批移植；更新检查、下载和状态管理使用共享 Dart 层，安装交给受范围限制的原生实现与系统安装器。Core 生命周期继续由现有 desktop lifecycle、Android ServiceState 和 SystemExitCoordinator 持有。

**Tech Stack:** Flutter/Riverpod、Go/Mihomo、Android Kotlin/PackageInstaller、Windows Inno Setup/Rust Helper、macOS 原生升级辅助程序、Linux 系统包管理器。

## 交付约束

- 主菜单固定为 `dashboard → proxies → account → tools`，中文为“仪表盘 → 代理 → 账号 → 工具”。桌面、手机、横竖屏、窄宽布局和 TV 均保持四项及相同顺序；开启日志也不得增加第五项。
- 日志、诊断、自定义配置、更新下载状态等能力进入工具页二级页面或已有页面详情，不生成新的一级导航。
- 保留现有 E 图标、主题和导航交互，不移植 prism_ui 或上游整套界面。
- 保留 Android applicationId、macOS bundle identifier、Windows 安装器 AppId、Linux 包名及各平台数据目录。保留账号邮箱、登录会话、受管订阅归属、用户配置与 DNS 策略。
- 更新源继续使用 Xboard `/api/v1/app/update`。分别发送 app_key、平台、ABI、版本号和构建号；安装包来自该接口选中的大象网络官方包。
- 使用独立的 `codex/flclash-v093-backports` 开发分支。本地分批提交；GitHub 推送按用户后续指令执行。
- 本阶段只允许代码修改、测试和验证用构建。不创建发布 tag，不创建 GitHub Release，不上传正式安装包，不修改生产软件中心或生产更新记录。
- 不新增代码注释；生成文件通过相应生成器更新。

## 用户能看到的升级流程

启动首帧后检查更新；相同版本号但构建号更高也进入更新流程。弹窗显示版本号、构建号、升级内容，提供“更新”和“取消”。

选择更新后直接在 App 内下载，显示进度、已下载大小和总大小，并提供取消。下载完成后校验文件，按钮切换为“立即安装”和“稍后”。稍后安装时可以在工具页找到同一条任务；再次启动恢复经过重新校验的待安装任务。

共享状态顺序为：

```text
idle → checking → available → downloading → verifying → ready → installing
                                  ↓             ↓          ↓
                               canceled        failed     deferred
```

实际实现使用单一状态模型表达阶段，`deferred` 保持已校验文件和任务元数据。更新按钮不会仅打开浏览器。下载期间允许继续使用代理；用户确认安装后，才通过统一退出流程停止代理、恢复系统设置并交给安装器。

| 平台 | 交付的安装行为 | 验收边界 |
| --- | --- | --- |
| Android 手机、TV | App 内下载 APK；校验包名、签名、ABI 与 versionCode；通过 PackageInstaller 更新本应用 | 系统要求的安装来源授权和安装确认保留；拒绝或取消后能够重试，不丢失任务和账号 |
| Windows 安装版 | App 内下载 EXE；用户确认后启动安装器，等待旧进程正常退出，保留安装路径并重启 | 沿用现有 Inno AppId；需要 UAC 时使用系统授权；不能用强杀进程替代应用退出清理 |
| macOS | App 内下载 DMG；只读挂载，校验并暂存 ElephantRoute.app；独立辅助程序等待旧进程退出后替换当前安装位置并重启 | 替换失败保留或恢复旧应用；需要权限时走系统授权；保留 bundle identifier 和钥匙串可访问性 |
| Linux 官方 DEB | App 内下载 DEB；校验包名和架构；通过系统授权运行包管理器安装，完成后以原登录用户重启 | 不能直接覆盖包管理器拥有的文件；安装失败保留诊断结果；需要系统依赖时明确展示包管理器结果 |

Windows 便携 ZIP、Linux RPM/AppImage 作为同一升级模块的后续格式适配。先检测当前安装格式，只有已有对应官方包和完成端到端验证的格式才展示应用内安装能力；不能把打开外部网页算作“已完成应用内安装”。四个平台的正式交付最低覆盖上表的现有主要安装格式。

## 更新数据与文件约束

现有 Xboard 返回 version、build_number、platform、arch、download_url、file_size、sha256 和 release_notes，先复用已有字段。若测试发现某平台元数据缺失，记录缺项；本阶段不改生产数据。

- SHA256 必须是有效的 64 位十六进制值；缺失、格式错误或不匹配时不进入可安装状态。
- 按目标平台和架构筛选下载，拒绝不匹配的安装包。文件类型同时检查内容特征，不只依赖 URL 后缀。
- 下载保存到应用自有的任务目录，使用随机任务 ID 和 `.part` 文件；完成并校验后再原子改名。
- 限制重定向协议为 HTTPS。下载失败或取消时清理未完成文件，保留可重试状态。
- 用流式计算 SHA256，避免将整个安装包载入 UI isolate。安装前再次校验文件和任务元数据。
- 任务同一时间只能有一个；启动检查、工具页手动检查和多次点击复用同一任务。
- Android 必须校验与已安装应用一致的签名及包名。macOS、Windows 若已有发布者签名，额外检查发布者身份；SHA256 校验本身不等同于发布者签名验证。
- 原生安装器不能接受任意 shell 命令；只消费经过验证的升级任务。不得给现有 Core/Helper IPC 增加任意文件覆盖、删除或命令执行接口。
- 保留安装前的应用回退材料。自动回退只适用于可原子替换的应用文件；系统包管理器和不可逆数据迁移采用单独的恢复方案，不能承诺失败后必然自动降级。
- Linux 打包元数据携带构建号，例如 DEB 的 `2.1.0+build22102`；应用内语义版本仍为 `2.1.0`。Android versionCode、macOS CFBundleVersion、Windows 文件版本与 Xboard build_number 一致。

## 第一阶段 菜单保护与稳定性修复

### S0 固定四个主菜单

**Files:** `lib/common/navigation.dart`、`lib/providers/state.dart`、`test/common/navigation_test.dart`、`test/pages/home_test.dart`。

- [ ] 先扩展现有导航测试，对 `openLogs=false/true` 和 mobile/desktop 模式分别断言四项完全相等，不只检查第一项和第三项。
- [ ] 修正 `logs` 的模式列表：开启日志时保留工具页入口，移除 desktop 一级导航归属。
- [ ] 对导航状态和实际页面切换补测试：四项顺序、窄宽布局切换、账号返回、TV 遥控器焦点和返回行为。
- [ ] 运行 `flutter test test/common/navigation_test.dart test/pages/home_test.dart --reporter expanded`。

固定断言为：

```dart
const expected = [
  PageLabel.dashboard,
  PageLabel.proxies,
  PageLabel.account,
  PageLabel.tools,
];
for (final openLogs in [false, true]) {
  final items = navigation.getItems(openLogs: openLogs);
  for (final mode in [NavigationItemMode.mobile, NavigationItemMode.desktop]) {
    expect(
      items.where((item) => item.modes.contains(mode)).map((item) => item.label),
      expected,
    );
  }
}
```

### S1 分应用代理名单保护

**Files:** `lib/views/access.dart`、`android/app/src/main/kotlin/com/follow/clash/packages/PackageResolver.kt`；新增 `test/views/access_test.dart` 中的相关回归用例。

- [ ] 复现“勾选系统应用 → 隐藏系统应用 → 保存”，断言名单仍包含隐藏项。
- [ ] 保存操作只排序并去重，不按当前可见列表裁剪名单。
- [ ] 智能选择只重新分配当前可见应用，保留隐藏应用的原有选择；扫描失败不覆盖名单。
- [ ] 剪贴板导入逐行 trim、校验包名、去重；完全无效输入提示错误并保留原名单。
- [ ] 每次进入检查应用列表权限，拒绝权限时保留已选名单。
- [ ] 运行对应 Flutter 测试，并在 Android 手机上验证 allowlist/rejectlist 两种模式实际分流。

### S2 Mihomo 四补丁与测速超时联动

**Files:** `core/Clash.Meta`、`core/constant.go`、`core/common.go`、`core/hub.go`、`lib/models/core.dart`、`lib/providers/state.dart`、`lib/providers/actions/proxies.dart`、`test/core/protocol_contract_test.dart`；新增或扩展 Core 超时测试。

- [ ] 固定审计目标 `024245dc72bc92f48237f865119afe0cd53ac9e6`，先核对相对当前 `c5062921` 的四个提交，不追随浮动分支。
- [ ] 移入 provider 节点列表版本检查和 url-test 首选节点缓存修复，保留全组不可用时的一秒节流。
- [ ] 把当前 App 测速超时传给 provider 默认健康检查；provider 显式超时继续生效，同一节点与 URL 的手动检查使用相容的超时依据。
- [ ] 保留大象现有测速并发限制和去重行为，防止 AnyTLS 延迟测试回归。
- [ ] 回归场景：无效首节点、测速中替换订阅节点、全组失效、显式 provider 超时、批量测速、AnyTLS。
- [ ] 运行 `flutter test test/core/protocol_contract_test.dart test/providers/action_test.dart --reporter expanded`；在 `core/` 执行 `CGO_ENABLED=0 go test .` 和 `CGO_ENABLED=0 go vet .`。不启用 Core 覆盖率采集。

### S3 Android Doze 与 NTP、时区、启动

**Files:** `android/service/src/main/java/com/follow/clash/service/modules/SuspendModule.kt`、`ServiceModules.kt`、`android/app/src/main/kotlin/com/follow/clash/plugins/ServicePlugin.kt`、`android/core/src/main/java/com/follow/clash/core/Core.kt`、`core/common.go`、`core/runtime.go`、`lib/core/lib.dart`。

- [ ] 去除因熄屏和 Doze 暂停代理隧道的旧逻辑，保留用户显式停止、系统撤销 VPN 和 Always-on 的现有所有权。
- [ ] 完整配置加载与运行时更新统一屏蔽 Android NTP 写系统时间，并补首次加载回归测试。
- [ ] 在当前 JNI 架构内先实现后台预加载 Core 和共享状态后台解析；不为了这两项提前强行切换 gomobile。
- [ ] Android Go 时区初始化在并发工作启动前完成，校验 UTC+8 和设备改时区后重启。
- [ ] JDK 17 编译 `:app:compileDebugKotlin`、`:service:compileDebugKotlin`、`:core:compileDebugKotlin`。
- [ ] 实机覆盖 Doze、熄屏、Wi-Fi/移动网切换、常驻 VPN、快速启停、系统撤销及推送/长连接恢复。

### S4 Windows 启动兼容性

**Files:** `lib/common/system.dart`；新增 `test/common/system_init_test.dart`。

- [ ] 注入设备信息读取器，复现 Windows InstallDate 导致的 RangeError。
- [ ] 对 Windows 此类异常回退版本信息；其他平台和其他异常保持原有错误路径。
- [ ] 测试正常值、异常日期和非 Windows 异常，补 Windows 实际启动检查。

## 第二阶段 优先交付应用内安装及恢复能力

应用内升级从原第三阶段提前，作为这一阶段的首要交付；四个平台都完成上表中的主要安装格式后，才将此功能标为完成。

### U1 共享更新任务与下载校验

**Files:** 扩展 `lib/features/update/app_update_client.dart`；新增 `lib/features/update/update_release.dart`、`update_download.dart`、`update_store.dart`、`update_installer.dart`、`lib/providers/update.dart`、`lib/widgets/update_download_dialog.dart`；调整 `lib/providers/actions/common.dart`、`lib/views/tools.dart`、四份 ARB。

- [ ] 先写元数据、同版本不同构建、错误架构、错误 SHA256、重定向、取消、断网、并发任务和重启恢复测试。
- [ ] 用单一 Riverpod 更新任务控制检查、下载、校验和待安装状态。工具页与弹窗订阅同一状态，不各自创建下载任务。
- [ ] `AppUpdateClient` 传递 platform、arch、file_size 和 sha256；构建号比较继续采用现有 Xboard 规则。
- [ ] 下载到受控任务目录，成功校验前不得生成可安装状态。任务恢复时重新验证文件。
- [ ] 安装器接口返回明确的成功、用户取消、待授权和失败结果；失败可以重试。界面显示可操作的状态，不把“浏览器已打开”视为安装成功。
- [ ] 跑 `flutter test test/features/update/ test/widgets/app_update_test.dart test/widgets/update_download_dialog_test.dart --reporter expanded`。

安装器边界固定为以下职责：

```text
prepare(release, verifiedFile) → 校验包身份、架构、构建号和安装环境
install(preparedTask) → 请求系统授权或交给受限安装流程
recover(taskId) → 查询持久化任务与系统安装结果
discard(taskId) → 只清理该任务的自有文件
```

### U2 Android PackageInstaller

**Files:** `android/app/src/main/AndroidManifest.xml`、`android/app/src/main/kotlin/com/follow/clash/plugins/AppPlugin.kt`、新增同模块安装结果接收器、`lib/plugins/app.dart`；扩展 Android 包安装测试。

- [ ] 加入安装本应用所需权限和受限制的结果接收通道，使用 PackageInstaller session，不暴露任意 APK 安装接口。
- [ ] 安装前检查 `com.elephantroute`、当前签名、目标 ABI 和 versionCode。使用真实签名测试包，不能以不同签名包替代升级测试。
- [ ] 安装来源未授权时显示系统授权；恢复到 App 后继续同一任务。系统要求用户确认时保留确认流程。
- [ ] 安装结果在进程重启后仍可读取；拒绝安装、安装失败和返回工具页均不会删除账号或已验证任务。
- [ ] 手机和 TV 分别验证同版本构建号递增升级、权限拒绝与恢复、取消和重试。

### U3 Windows 原位安装

**Files:** `windows/packaging/exe/inno_setup.iss`、`lib/plugins/app.dart` 或 Windows 安装器适配、`lib/providers/actions/system.dart`、`lib/providers/actions/system_exit.dart`。

- [ ] 增加升级参数，记录旧进程 PID 和原安装位置；安装器先等待应用正常退出再覆盖。
- [ ] Flutter 确认安装后调用现有统一退出流程清理系统代理、Core 和 Helper；安装器不在正常升级路径提前强杀应用。
- [ ] 保持现有 AppId、应用目录和卸载信息，安装成功后以普通用户上下文启动新应用。
- [ ] 回归管理员/普通用户安装、UAC 拒绝、同版本更高构建、Core 正在运行和退出超时。

### U4 macOS 原位更新

**Files:** 新增 `services/updater/` 的 macOS 安装实现，调整 `plugins/setup/` 中对应打包步骤、`macos/Runner/` 的调用边界及 Dart 安装器适配。

- [ ] 只读挂载已验证 DMG，读取并匹配 `com.elphantroute.elephantNetwork`、CFBundleVersion 和架构；只接受预期的 ElephantRoute.app。
- [ ] 将新应用暂存到当前安装位置所在文件系统，提前检查替换条件和可用空间。
- [ ] 独立更新辅助程序等待 App 和 Core 完成退出；替换时保留旧应用，失败回退文件，成功后重启并检查构建号。
- [ ] 用户目录可写时不提权；替换受保护安装目录时使用系统授权。权限拒绝保留可重试任务。
- [ ] 回归 Apple Silicon/Intel、`/Applications` 和用户自选路径、钥匙串登录保留、拒绝授权、替换失败及卷卸载清理。

### U5 Linux DEB 原位更新

**Files:** 新增 Linux 安装器适配及受限安装协调实现；调整 `linux/packaging/deb/` 和构建号传递；扩展安装器测试。

- [ ] 检测当前包管理器归属，检查目标 DEB 的包名 `elephant-network`、架构和包版本。
- [ ] 用户确认后通过系统授权执行固定的包管理安装命令。升级任务只携带经过验证的包，不接受任意命令。
- [ ] 安装完成后按原用户身份重启，保留桌面入口、文件归属和账号数据，校验实际运行构建号。
- [ ] 回归授权取消、依赖不满足、安装失败、同版本不同构建和待安装任务恢复；失败时显示包管理器返回结果。

### R1 Windows 遗留代理与 Helper 所属用户校验

**Files:** `plugins/proxy/windows/proxy_plugin.cpp`、`plugins/proxy/lib/`、`services/helper/src/service/`、`lib/core/desktop/helper_client.dart`、`lib/core/desktop/launcher.dart`；迁移时补充 `.agents/architecture.md`。

- [ ] 遗留代理清理只处理符合本应用规则、且已确认不再监听的本地代理；查询失败按仍在使用处理，不改其他应用代理或 PAC。
- [ ] Windows Helper 安装记录所属用户 SID，连接请求校验实际客户端身份；继续保留 Core 哈希、会话归属和 named-pipe peer PID 校验。
- [ ] Helper 与 Dart 同时升级协议版本；测试旧 Helper 被识别后进行受控重新安装，不绕过不匹配检查。
- [ ] Linux Helper 引入作为独立子任务，先完成安装所属用户与 socket 凭据校验，再切换 TUN 启动路径；正常 direct Core 保留现有降级行为。
- [ ] 用跨用户请求、错误会话、错误 Core 哈希、退出未确认、Helper 重启和遗留端口测试验收。

### R2 备份恢复与数据库一致性

**Files:** `lib/providers/actions/backup.dart`、`lib/common/backup.dart`、`lib/database/database.dart`、`lib/common/migration.dart`；新增 `test/providers/backup_action_test.dart`。

- [ ] 解包到临时目录，校验归档路径和格式，先解析并校验全部配置，再触碰活动数据。
- [ ] 文件替换保留撤销记录；数据库部分放到事务内，启用外键并处理旧备份中的孤立记录。
- [ ] 数据库失败回滚文件；文件失败不提交数据库。失败不得留下半套订阅或规则。
- [ ] 回归覆盖恢复、合并恢复、损坏包、新版本备份、路径越界、磁盘写失败、数据库中途失败与旧格式迁移。
- [ ] 安装升级本身不触发备份导入或清空账号，升级与恢复保持不同入口。

### R3 本地入口与配置安全边界

**Files:** `lib/common/task.dart`、`lib/models/clash_config.dart`、`lib/models/config.dart`、`lib/common/migration.dart`、`core/common.go`、相关网络设置页。

- [ ] 控制端口开启时生成并持久化有效 secret，恢复备份后重新验证；默认关闭的行为保持。
- [ ] 清理订阅带入的替代控制入口，并将可选本地代理认证贯穿配置构建、运行时更新和 App 自身代理请求。
- [ ] 安全模式作为独立构建/诊断能力验证，不擅自改变正常模式下用户选定的代理行为。
- [ ] 回归外部控制器关闭/开启/恢复备份、认证失败、loopback 和 Android VPN 系统代理声明。

## 第三阶段 统一 Core 协议与增强功能

这一阶段在升级通道和恢复能力完成后实施，每个子任务均保持四主菜单契约。

| 子任务 | 文件责任与改动范围 | 必须通过的验收 |
| --- | --- | --- |
| C1 统一 Core 协议 | `core/method.go`、`core/constant.go`、`lib/core/method.dart`、`lib/core/interface.dart`、`lib/core/desktop/rpc_client.dart`、`test/fixtures/core_protocol.json`；按上游新命名和结果契约同步迁移 Dart/Go | 参数类型、错误类型、超时、配置拒绝、断线、落盘响应及过期响应清理；不能混装新 Dart 和旧 Core |
| C2 Android gomobile | `core/mobile/`、`android/core/`、`ServicePlugin.kt`、`lib/core/lib.dart`、`plugins/setup/` | Kotlin/Go 接口联编；快速启停、重连、进程销毁、系统撤销与 Always-on；ServiceState 继续是唯一原生意图所有者 |
| C3 自定义配置 | `lib/models/profile.dart`、`lib/database/`、配置合成与导入；入口放工具页二级配置管理 | 旧库迁移、URL/文件/custom 三类并存、受管订阅仍属于当前账号、导入失败不覆盖有效配置、未知新字段保持 |
| C4 出口与服务探测 | 新增 Core 路由解析/探测方法、Dart 探测 provider 和 IP 质量缓存表；入口放工具页诊断与现有详情 | 按实际出口测试，切路由后废弃旧结果；三天缓存、失败冷却、请求取消、重启后的缓存有效期 |
| C5 Geo 与编辑性能 | Geo URL 参数即时更新和完成事件刷新；大文件编辑读取/解析移出 UI isolate | 改 URL 后下一次同步使用新地址；文件信息在完成后刷新；大文本、中文输入、撤销、页面销毁无回归 |
| C6 事件与启动恢复 | Core 状态/优先/批量事件分层、无监听时减少编码；Android 分阶段启动记录和桌面更早取得数据锁 | 日志洪峰不挤掉加载状态；无 Flutter 引擎时正常代理；重复启动、启动中崩溃和异常配置可恢复 |

Flutter/Go 等工具链升级单独提交。先在当前 Flutter 3.44.4、Go 1.26.4 验证可移植修复，再按 C1/C2 的真实构建依赖决定工具链升级；不顺带把 Android 最低 API 从 23 提到 24。确需提高最低 API 时单独列出设备兼容影响再处理。

MITM 仍保持未启用；上游正式版尚未完整开放的实验能力不作为本次功能交付。

## 提交顺序与验证门槛

每一批独立提交，失败停留在该批修复；没有通过的批次不带入下一批验收。原生平台检查不能以 Flutter 测试代替。

```text
S0 菜单契约
→ S1 分应用代理
→ S2 内核与测速
→ S3/S4 平台稳定性
→ U1 共享下载与校验
→ U2/U3/U4/U5 四平台安装
→ R1/R2/R3 恢复与权限
→ C1/C2 协议与 Android 桥接
→ C3/C4/C5/C6 增强能力
```

每批使用相关的窄测试；涉及模型、provider 或数据库时运行生成器；完成批次后运行根包全量检查：

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze --no-fatal-infos
flutter test --reporter expanded
```

有 ARB 变化时另运行 `dart run intl_utils:generate`。有 Go/Helper/插件变动时增加：

```bash
cd core
CGO_ENABLED=0 go test .
CGO_ENABLED=0 go vet .
```

```bash
cargo fmt --manifest-path services/helper/Cargo.toml -- --check
cargo test --manifest-path services/helper/Cargo.toml
flutter test plugins/proxy/test/proxy_test.dart
```

Windows runner 另跑 Helper 的 `windows-service` 测试；Android 用 JDK 17 编译修改模块，桌面分别构建对应目标。构建脚本对 Windows、Linux 和 macOS 的支持在所属主机或验证 runner 上检查。

## 应用内升级完成标准

- [ ] 四个平台均用两份私有测试安装包验证完整链路：带更新器的基线构建 → 同版本更高构建号的目标构建。测试构建号如 22102 → 22103，不代表对外发布版本。
- [ ] 从已安装基线 App 开始，完成发现新版、展示升级内容、App 内下载、SHA256 校验、安装授权、安装和重新启动；重启后的实际 buildNumber 与目标一致。
- [ ] 登录邮箱、登录会话、账号、受管订阅、代理选择和必要系统设置保持有效；系统代理清理和恢复符合预期。
- [ ] 取消、断网、错误 SHA256、错误包名/签名/ABI、拒绝授权、磁盘空间不足和安装失败均有确定状态与重试路径。
- [ ] 所有平台、日志设置和窗口宽度下仍严格显示四个主菜单及原顺序。
- [ ] 未具备目标主机或实机证据的平台标记“待验证”，不得用其他平台通过替代该平台完成。
- [ ] 当前旧安装包需要先安装一次包含更新器的新构建，之后才能使用该链路；仅修改服务器更新信息不会让旧包自动获得新安装能力。
- [ ] 所有测试产物仅用于验证，不发布正式 tag、Release、安装包或生产更新记录。

## 执行记录 2026年11月12日

- S0 已完成代码和 11 项导航/页面测试，并本地提交 `7890282d`。日志开启不再增加第五主菜单。TV 实机焦点验证仍待进行。
- S1 已完成名单保留、智能选择范围保护、剪贴板校验、权限检查与授权入口；分应用代理两种模式的 widget 测试通过。
- S2 已固定到 `024245dc`，接通 setup/update/shared state 的超时参数，保留旧测速并发逻辑，扩大 RPC 等待预算容纳 provider 显式超时。Go 超时政策测试通过。
- S3 已移除 Doze 暂停，完整与运行时配置共用 NTP 限制；后台预加载、后台状态解析已编译。时区在 Go 包初始化阶段读取系统属性并使用内置 tzdata。
- S4 已增加 Windows 设备日期越界降级和针对性测试。
- 已通过 30 项相关 Flutter 测试、Go 包与 timezone 测试、Go vet、Android app/service/core Kotlin 编译和全库静态检查；根包全量 915 项测试通过。跨平台实机验收尚未完成。
- S1–S4 本地提交 `260be454`，未推送 GitHub。
- U1 已加入共享任务、流式下载、逐跳 HTTPS 重定向检查、受控临时目录、SHA256 校验、取消/重试、持久化与恢复，以及弹窗/工具页共用状态。更新按钮已不再打开浏览器。
- U2 已加入 Android PackageInstaller 会话、包名/签名/ABI/versionCode 检查、安装来源授权及持久化回调；Kotlin 编译通过，手机与 TV 安装实测待验证。
- U3 已加入 Windows 安装器的原用户授权后握手、等待旧 PID 退出、避免正常更新路径强杀、按原用户启动新程序、安装器版本及架构标记校验；Windows 主机编译与实际 UAC/安装验收待验证。
- U4 已加入独立 macOS 更新辅助程序、DMG 只读挂载、Bundle ID/版本/架构/现有发布者检查、等待 App/Core 退出、同文件系统暂存与旧应用回退；私有 Debug 构建成功，真实 DMG 与模拟启动失败回退测试通过。受保护目录授权及两份真实客户端升级验收仍待验证。
- 本机 Xcode 仅支持 macOS 12+ 的构建目标，私有构建使用临时 xcconfig 覆盖到 12.0；仓库中的 11.0 设置未提高。此构建不能作为 macOS 11 兼容性证据。
- U5 已加入 Linux DEB 包名/架构/版本与包管理归属检查，通过系统授权运行固定包管理器命令并重新启动。现有打包器已保留 `2.1.0+22101` 形式的构建号，继续采用该格式，避免改变语义版本和历史包版本顺序。已在本机交叉编译 Linux 辅助程序，Linux 安装验收待验证。
- U 阶段已通过更新相关 Flutter 测试及 926 项全量测试，最后补充的失败恢复、版本比较与真实路径修正后，36 项更新专项测试通过。全库静态检查和 Android Kotlin 编译通过。
- R/C 阶段尚未开始；没有发布安装包或修改生产更新记录。四个平台的真实升级验收未完成，不能将更新功能整体标记完成。
