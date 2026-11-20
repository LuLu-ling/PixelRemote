// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get homeHeadline => '安全抵达每一台桌面。';

  @override
  String get homeSubtitle =>
      '输入 SSH 地址即可连接。PixelRemote 通过加密的 SSH 隧道传输 VNC，只需开放 SSH 端口。';

  @override
  String get addressHint => 'user@host:22，或 ~/.ssh/config 中的别名';

  @override
  String get connect => '连接';

  @override
  String get advanced => '高级选项';

  @override
  String get displayName => '显示名称';

  @override
  String get optional => '可选';

  @override
  String get vncHost => 'VNC 主机（从 SSH 服务器看）';

  @override
  String get vncPort => 'VNC 端口';

  @override
  String get identityFile => '私钥文件';

  @override
  String get identityFileHint => '默认使用 ssh-agent 和 ~/.ssh/id_*';

  @override
  String get startCommand => '启动命令';

  @override
  String get startCommandHint => '例如 x11vnc -localhost -display :0 -once';

  @override
  String get save => '保存';

  @override
  String get saved => '已保存';

  @override
  String get cancel => '取消';

  @override
  String get ok => '确定';

  @override
  String get close => '关闭';

  @override
  String get recentTitle => '最近连接';

  @override
  String get recentEmpty => '连接过的主机会显示在这里。';

  @override
  String get edit => '编辑';

  @override
  String get delete => '删除';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int count) {
    return '$count 分钟前';
  }

  @override
  String hoursAgo(int count) {
    return '$count 小时前';
  }

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 天前',
      one: '昨天',
    );
    return '$_temp0';
  }

  @override
  String get neverConnected => '尚未连接';

  @override
  String get footer => 'SSH 隧道 · RFB 3.8 · Tight · ZRLE · 扩展剪贴板';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get appearance => '外观';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get defaultSettings => '默认画面设置';

  @override
  String connectingTo(String target) {
    return '正在连接 $target';
  }

  @override
  String get stageResolving => '解析地址';

  @override
  String get stageConnecting => '建立 SSH 会话';

  @override
  String get stagePreparing => '准备远程主机';

  @override
  String get stageTunnelling => '打开加密隧道';

  @override
  String get stageNegotiating => '协商显示参数';

  @override
  String errorInvalidAddress(String address) {
    return '“$address”不是有效的 SSH 地址。';
  }

  @override
  String get errorHostUnreachable => '无法连接 SSH 服务器，请检查主机名、端口和网络。';

  @override
  String get errorAuthFailed => 'SSH 身份验证失败。';

  @override
  String get errorHostKeyRejected => '未信任主机密钥，已停止连接。';

  @override
  String get errorHostKeyChanged => '警告：该主机的密钥已变更，可能有人在拦截连接，已拒绝连接。';

  @override
  String errorVncUnavailable(String target) {
    return '远程主机上的 $target 没有服务在监听。请在远程主机上启动 VNC 服务，或在高级选项中设置启动命令。';
  }

  @override
  String get errorVncAuthFailed => 'VNC 密码错误。';

  @override
  String errorUnsupportedSecurity(String types) {
    return 'VNC 服务器只提供本客户端不支持的安全类型（$types）。请启用 “None” 或 “VncAuth”；SSH 隧道已对会话加密。';
  }

  @override
  String errorProtocol(String detail) {
    return '协议错误：$detail';
  }

  @override
  String get errorDisconnected => '远程会话已结束。';

  @override
  String get errorCancelled => '已取消连接。';

  @override
  String get secretSshPassword => 'SSH 密码';

  @override
  String get secretKeyPassphrase => '私钥口令';

  @override
  String get secretVncPassword => 'VNC 密码';

  @override
  String get secretChallenge => '需要验证';

  @override
  String secretFor(String subject) {
    return '用于 $subject';
  }

  @override
  String get hostKeyTitle => '验证主机身份';

  @override
  String hostKeyBody(String host) {
    return '这是首次连接 $host。继续之前，请确认以下指纹与服务器一致。';
  }

  @override
  String get hostKeyTrust => '信任并连接';

  @override
  String get streamSettings => '画面与传输';

  @override
  String get statsOverlay => '统计浮窗';

  @override
  String get sendKeys => '发送按键';

  @override
  String get fullScreen => '全屏';

  @override
  String get exitFullScreen => '退出全屏';

  @override
  String get refreshScreen => '刷新画面';

  @override
  String get disconnect => '断开连接';

  @override
  String get keySuper => 'Super / Win / ⌘';

  @override
  String get keyPrintScreen => '截屏键';

  @override
  String get quality => '画质';

  @override
  String get qualityLow => '低';

  @override
  String get qualityBalanced => '均衡';

  @override
  String get qualityHigh => '高';

  @override
  String get qualityLossless => '无损';

  @override
  String get frameRate => '帧率';

  @override
  String fps(int value) {
    return '$value fps';
  }

  @override
  String get resolution => '分辨率';

  @override
  String get resolutionNative => '服务器默认';

  @override
  String get resolutionWindow => '匹配窗口';

  @override
  String get resolutionUnsupported => '该服务器不支持调整分辨率，画面将在本地缩放。';

  @override
  String get colorDepth => '色深';

  @override
  String get depthFull => '全彩';

  @override
  String get depthHigh => '16 位';

  @override
  String get depthLow => '8 位';

  @override
  String get bandwidth => '带宽上限';

  @override
  String get bandwidthHint => '系统会控制帧的发送节奏，使视频流不超过此上限。';

  @override
  String get unlimited => '不限';

  @override
  String mbps(int value) {
    return '$value Mbps';
  }

  @override
  String get keyMapping => '键盘映射';

  @override
  String get mappingAuto => '自动';

  @override
  String get mappingOff => '关闭（原样发送）';

  @override
  String get mappingCtrlCmd => '交换 Ctrl ⇄ ⌘';

  @override
  String get mappingAltCmd => '交换 Alt ⇄ ⌘';

  @override
  String mappingActive(String mode, String local, String remote) {
    return '当前生效：$mode · $local → $remote';
  }

  @override
  String get osMac => 'macOS';

  @override
  String get osWindows => 'Windows';

  @override
  String get osLinux => 'Linux';

  @override
  String get osUnknown => '未知系统';

  @override
  String get showStats => '显示统计浮窗';

  @override
  String get statsTitle => '实时统计';

  @override
  String get statsLatency => '延迟';

  @override
  String get statsLoss => '丢包率';

  @override
  String get statsLossHint => '根据未响应的 SSH 保活探测估算';

  @override
  String get statsDown => '下行';

  @override
  String get statsUp => '上行';

  @override
  String get statsFrameRate => '帧率';

  @override
  String get statsResolution => '分辨率';
}
