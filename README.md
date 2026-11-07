# fch · 添加通话记录

一个越狱 iOS（roothide / rootless）用的小 App：手动往本机通话记录里写入一条记录，
可在「电话」App 的最近通话里看到。

> 只在自己拥有、且已越狱的设备上使用。它会直接写入系统通话记录数据库，
> 请自行承担风险，并只用于你自己的设备。

## 功能

- 选联系人（系统联系人选择器）或直接填号码
- 选时间（系统日期时间选择器）
- 类型：呼出 / 呼入 / 未接
- 通话时长：手填，或留空按「随机范围」随机（默认 10–20 秒，点数字用气泡滚轮调）
- 收藏常用号码：在「收藏」里保存、选取、左滑删除
- 结果用底部横幅提示，不弹对话框打断操作

## 实现要点

- App 自行带 `com.apple.private.security.storage.CallHistory`、
  `com.apple.private.CallHistory.read-write` 等授权（见 `tools/App.entitlements`），
  因此可以直接打开受 data vault 保护的通话记录库，**不需要常驻后台进程**。
- 写库：`Sources/FCLStore.m` 往 Core Data 的 `ZCALLRECORD` 表插一行，
  主键取 `Z_PRIMARYKEY` 里 `CallRecord` 的 `Z_MAX`+1 并同步更新，`ZDATE` 用 Core Data 时间戳，
  整个插入在一个 `BEGIN IMMEDIATE` 事务里完成。
- 界面上的控件都是常驻实例，控件动作里不重建表格（重建会把正在触摸的控件销毁，主线程卡死）。

## 目录

```
Sources/
  FCLAppDelegate.m      App 入口与窗口
  FCLRootController.m   主界面（表格、时间、类型、时长、随机范围、收藏）
  FCLStore.{h,m}        通话记录库读写
  pkgid.h               包标识符（构建脚本从这里读）
Resources/
  App-Info.plist        App 的 Info.plist
  AppIcon/              图标（由 tools/makeicon.m 生成）
apelin/
  build.sh              构建脚本，产出 .deb
  postinst              只用于摘掉早期版本装过的后台进程
tools/
  makeicon.m            生成图标
  App.entitlements      App 的签名授权
  Daemon.entitlements   生成图标用的命令行工具所需授权
  schemadump.c          只读打印通话记录库结构（开发用）
  chquery.c             对通话记录库执行只读 SQL（开发用）
```

## 构建

需要 iOS 工具链（clang + iPhoneOS SDK）与 `ldid`、`dpkg-deb`。

```sh
sh apelin/build.sh    # 需要 APELIN_* 环境变量；在 Apelin IDE 里直接 apelin_project_build
```

产物是 `com.fch.callhistory_<版本>_iphoneos-arm64e.deb`，安装后 App 出现在桌面（名称 `fch`），
包标识符 `com.fch.callhistory`。

图标由 `tools/makeicon.m` 生成：

```sh
clang -arch arm64e -fobjc-arc -o .build/makeicon tools/makeicon.m \
  -framework UIKit -framework Foundation -framework ImageIO
ldid -Stools/Daemon.entitlements .build/makeicon   # 不带授权会被系统直接杀掉
.build/makeicon Resources/AppIcon
```

## 开发小结

- 通话记录库位置：`/var/mobile/Library/CallHistoryDB/CallHistory.storedata`（WAL 模式）。
- 不带授权时**连 root 也读不了**这个库（EPERM）。
- `Sources/fclw.m` 是开发用的命令行工具（不进安装包）：`--add`、`--probe`、`--dump`、`--copydb`。
