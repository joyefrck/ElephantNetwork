<div>

[**English**](README.md)

</div>

## 大象网络

[![License](https://img.shields.io/github/license/joyefrck/ElephantNetwork?style=flat-square)](LICENSE)

大象网络官方多平台客户端，基于
[FlClash](https://github.com/chen08209/FlClash) 与 ClashMeta。

本仓库保留 FlClash 的完整功能，并新增 Xboard 强制登录、原生账户概览、
账号受管订阅，以及套餐、订单、支付和工单入口。第一阶段正式发布 Android、
Windows 与 macOS。

客户端以 GPLv3 开源分发。每个二进制版本必须同步发布对应源码标签、许可证、
修改声明、构建说明和 SHA-256。详见 [NOTICE](NOTICE)、
[上游维护说明](docs/UPSTREAM.md)、[隐私约定](docs/PRIVACY.md) 与
[发布门禁](docs/RELEASE_GATES.md)。

## 功能

- Android、Windows、macOS 三端代理、TUN、系统代理与配置管理
- Xboard 登录、账户余额、套餐与流量信息
- 登录后自动创建带 `flag=flclash` 的大象网络受管订阅
- 套餐、订单、支付和工单 WebView，Windows 缺少 WebView2 时降级系统浏览器
- Android Keystore、macOS Keychain、Windows 系统保护存储

## Android 外部操作

```bash
com.elephantroute.action.START
com.elephantroute.action.STOP
com.elephantroute.action.TOGGLE
```

## 构建

```bash
git submodule update --init --recursive
flutter pub get
dart setup.dart android
dart setup.dart windows
dart setup.dart macos
```

三端命令需要分别在具备对应 SDK 和签名环境的构建机上运行。正式发布前必须完成
Android 旧包签名核对，以及 Windows、macOS 旧服务和 Helper 的真实覆盖安装验收。

## 上游归属

FlClash 的版权、许可证、Git 历史和原作者信息均保留。本 fork 的大象网络功能不
代表上游作者对产品的认可或背书。
