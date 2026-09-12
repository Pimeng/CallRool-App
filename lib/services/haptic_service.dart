import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 点击控件的轻微震动反馈。
///
/// 设置页里的「震动反馈」开关通过 [setEnabled] 全局控制，
/// 关闭后所有调用都会直接跳过。震动只在 Android / iOS 上生效，
/// Web、桌面与测试环境（不支持的平台）静默忽略，避免无意义的系统调用。
abstract final class Haptic {
  static bool _enabled = true;

  /// 当前是否允许震动（对应设置里的「震动反馈」开关）。
  static bool get enabled => _enabled;

  static void setEnabled(bool value) => _enabled = value;

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// 轻点反馈：按钮、开关、状态切换等常规操作。
  static void light() {
    if (!_enabled || !_supported) return;
    HapticFeedback.lightImpact();
  }

  /// 选择反馈：切换 Tab、筛选、勾选等轻量选择，比 [light] 更轻微。
  static void selection() {
    if (!_enabled || !_supported) return;
    HapticFeedback.selectionClick();
  }
}
