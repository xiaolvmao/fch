# fch：添加通话记录

屏幕上有一个 App（「添加通话记录」，浅绿色图标）：选联系人、填号码、挑时间、选呼出/呼入/未接、填时长，
点「添加记录」直接写进系统通话记录库，电话 App 的最近通话里能看到。

## 结构
- `Sources/FCLRootController.{h,m}` —— App 主界面（表格：联系人／电话号码／收藏、时间、类型、通话时长、随机范围、添加记录）。
  两条硬约定：控件都是常驻实例、任何控件的动作里都不重建表格（否则主线程会卡死）；
  结果用底部横幅提示（系统绿／系统红），不弹对话框。
  随机时长范围在行内两个数字上用底部滚轮调（`inputView`），不新开页面；
  收藏列表是 push 出来的一页，数据存在 `~/Library/Preferences/com.fch.callhistory.favorites.plist`。
- `Sources/FCLAppDelegate.m` —— `UIApplicationMain` 与窗口。
- `Sources/FCLStore.{h,m}` —— 写库实现：Core Data 的 `ZCALLRECORD` 表，事务 + 主键维护。
- `Sources/pkgid.h` —— 包标识符的唯一出处，构建脚本从这里读包名。
- `Resources/App-Info.plist` —— App 的 Info.plist（`@PKGID@` 占位）。
- `Resources/AppIcon/` —— 由 `tools/makeicon.m` 生成的浅绿色图标。
- `apelin/build.sh` —— 外部构建脚本；`apelin/postinst` 只用来摘掉 1.0.0 早期版本装过的后台进程。
- `Sources/fclw.m` —— 开发用命令行工具（不进包）：`--add`、`--probe`、`--dump`、`--copydb`。

## 没有常驻进程
App 自己带 `com.apple.private.security.storage.CallHistory` + `com.apple.private.CallHistory.read-write`
（`tools/App.entitlements`），已实测以普通用户身份就能对通话记录库开读写事务，所以不需要 launchd 守护进程：
关掉 App 就没有任何本项目的进程在跑。

## 构建与安装
- 构建：`apelin_project_build`（跑 `apelin/build.sh`），产出 `/Applications/FCLCallLog.app`。
- 安装：`apelin_package_install`；装上后 App 自动注册（`uicache -l | grep com.fch` 可见）。
- 改包标识符：只改 `Sources/pkgid.h`，构建脚本会带到 Info.plist、control 与签名。
- 生成图标：`clang -arch arm64e -fobjc-arc -o .build/makeicon tools/makeicon.m -framework UIKit -framework Foundation -framework ImageIO`，
  **必须带 entitlements 签名**（`ldid -Stools/Daemon.entitlements`），否则 UIKit 版工具会被系统直接杀掉；
  然后 `.build/makeicon Resources/AppIcon`。桌面图标有缓存，换图标后可能要 respring 才更新。

## 关键事实
- 通话记录库受 data vault 保护：不带授权时连 root 都读不了，必须给二进制签上
  `com.apple.private.security.storage.CallHistory`、`com.apple.private.CallHistory.read-write`、`com.apple.private.security.no-sandbox`。
- App 在 `/Applications` 下用 `tools/App.entitlements` 签名（application-identifier、platform-application、
  no-sandbox、container-required=false），与其它越狱 App 一致。
- 表 `ZCALLRECORD` 的写入：新主键取 `Z_PRIMARYKEY` 里 `Z_NAME='CallRecord'` 的 `Z_MAX`+1，
  插入后同步更新 `Z_MAX`；`ZDATE` 是 Core Data 时间戳（自 2001-01-01 起的秒数）。
- 库是 WAL 模式，写入用 `BEGIN IMMEDIATE` 事务；`ZANSWERED`、`ZDISCONNECTED_CAUSE`（未接=6）、
  `ZORIGINATED`、`ZSERVICE_PROVIDER='com.apple.Telephony'` 照真实记录填。
- 调试：`fclw --dump` 看最新记录，`--copydb` 复制一份库，`FCL_DB_PATH` 可把工具指向副本。
