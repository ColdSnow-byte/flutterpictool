import 'dart:async';

import 'package:flutter/material.dart';

/// 入场动画：延迟一小段时间后淡入 + 轻微上浮（可选带缩放）。
///
/// 用于卡片与列表项的错峰出现，避免整块内容「啪」地一次性弹出。
/// 动画只在首次挂载时播放一次，后续重建不会重放。
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 380),
    this.offset = 16,
    this.scaleFrom = 1,
    this.fade = true,
  });

  final Widget child;

  /// 延迟多久开始播放入场动画
  final Duration delay;

  final Duration duration;

  /// 起始纵向位移（像素，正数表示从下方浮起）
  final double offset;

  /// 起始缩放，1 表示不缩放
  final double scaleFrom;

  /// 是否淡入。
  ///
  /// 子树里若含 [LiquidGlass]（内部用 `BackdropFilter`）必须置为 false：
  /// `Opacity` 会新建图层，导致背景滤镜取不到背景。
  /// 此时改用 `LiquidGlass.opacity` 之类的方案做淡入。
  final bool fade;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  Timer? _delayTimer;

  /// 动画播完后直接返回子树，避免每帧都套一层 Opacity / Transform
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _start();
    } else {
      _delayTimer = Timer(widget.delay, _start);
    }
    _controller.addStatusListener(_onStatus);
  }

  void _start() {
    if (mounted) _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      setState(() => _settled = true);
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_settled) return widget.child;

    return AnimatedBuilder(
      animation: _progress,
      builder: (BuildContext context, Widget? child) {
        final double t = _progress.value;
        Widget result = Transform.translate(
          offset: Offset(0, widget.offset * (1 - t)),
          child: child,
        );
        if (widget.fade) {
          result = Opacity(opacity: t.clamp(0, 1), child: result);
        }
        if (widget.scaleFrom != 1) {
          result = Transform.scale(
            scale: widget.scaleFrom + (1 - widget.scaleFrom) * t,
            child: result,
          );
        }
        return result;
      },
      child: widget.child,
    );
  }
}

/// 一组 [FadeSlideIn] 的错峰延迟计算：第 index 项延迟 index * step
Duration staggerDelay(
  int index, {
  Duration step = const Duration(milliseconds: 55),
}) => Duration(milliseconds: step.inMilliseconds * index);
