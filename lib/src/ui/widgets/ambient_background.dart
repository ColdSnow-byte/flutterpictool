import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 纯装饰性的环境背景层：缓慢漂移的柔光色斑 + 极淡网格。
///
/// 只负责观感，不参与交互，也不进入无障碍树。
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  /// 30 秒一轮，量化成 450 档 → 约 15fps 的实际重绘频率
  static const int _steps = 450;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  )..repeat();

  static double _quantize(double value) =>
      (value * _steps).roundToDouble() / _steps;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.pageGradient),
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) => CustomPaint(
                // 色斑漂移本身很慢，把进度量化到约 15fps，
                // 避免为一个纯装饰背景每帧重绘整屏。
                painter: _AmbientPainter(
                  progress: _quantize(_controller.value),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({required this.progress});

  /// 0 → 1 的循环进度，用于驱动色斑漂移
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double angle = progress * 2 * math.pi;

    void blob({
      required Alignment center,
      required double radius,
      required Color color,
      double drift = 1,
    }) {
      final Offset origin = Offset(
        (center.x + 1) / 2 * size.width +
            math.sin(angle * drift) * size.width * 0.045,
        (center.y + 1) / 2 * size.height +
            math.cos(angle * drift * 0.8) * size.height * 0.05,
      );
      final double r = radius * size.shortestSide;
      canvas.drawCircle(
        origin,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: origin, radius: r)),
      );
    }

    // 色斑刻意做得比「背景本身好看」更明显一些：
    // 上面那层液态玻璃要靠这些颜色才有折射与提鲜的空间。
    blob(
      center: const Alignment(-1.05, -1.05),
      radius: 0.62,
      color: const Color(0xFF6D9DFF).withValues(alpha: 0.42),
      drift: 0.6,
    );
    blob(
      center: const Alignment(1.12, -0.72),
      radius: 0.52,
      color: const Color(0xFFAF86FF).withValues(alpha: 0.34),
      drift: 1.35,
    );
    blob(
      center: const Alignment(0.42, 1.15),
      radius: 0.68,
      color: const Color(0xFF63DCD2).withValues(alpha: 0.30),
      drift: 0.9,
    );
    blob(
      center: const Alignment(-0.62, 0.55),
      radius: 0.46,
      color: const Color(0xFF7FB4FF).withValues(alpha: 0.26),
      drift: 1.7,
    );

    _paintGrid(canvas, size);
  }

  /// 极淡的网格，边缘用径向遮罩渐隐，保证中间内容可读
  void _paintGrid(Canvas canvas, Size size) {
    const double step = 48;
    final Paint gridPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    final double offset = progress * step;
    for (double x = -step + offset % step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = -step + offset % step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final Rect bounds = Offset.zero & size;
    final Offset focus = Offset(size.width / 2, size.height * 0.42);
    final double fade = size.longestSide * 0.75;
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = RadialGradient(
          colors: <Color>[Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: focus, radius: fade)),
    );
  }

  @override
  bool shouldRepaint(_AmbientPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
