import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 液态玻璃着色器程序的加载与缓存。
///
/// `ImageFilter.shader` 只在 Impeller 后端可用；加载失败或后端不支持时
/// [LiquidGlass] 会自动退回「高斯模糊 + 高光」的近似实现。
abstract final class LiquidGlassProgram {
  static const String assetKey = 'shaders/liquid_glass.frag';

  static ui.FragmentProgram? _program;
  static bool _attempted = false;

  /// 是否可用真实的折射着色器
  static bool get available => _program != null;

  /// 在 `runApp` 之前调用一次即可
  static Future<void> load() async {
    if (_attempted) return;
    _attempted = true;

    try {
      if (!ui.ImageFilter.isShaderFilterSupported) return;
      _program = await ui.FragmentProgram.fromAsset(assetKey);
    } catch (_) {
      // 后端不支持或资源缺失：静默退回模糊实现
      _program = null;
    }
  }

  /// 每个玻璃控件都要有独立的 shader 实例（uniform 是共享状态）
  static ui.FragmentShader? createShader() => _program?.fragmentShader();
}

/// iOS Liquid Glass 风格的玻璃面板。
///
/// 与常见的「毛玻璃」不同，这里用片元着色器对背景做**边缘折射**：
/// 靠近圆角边缘的背景被压缩进玻璃内（透镜凸起感），同时提升背景饱和度，
/// 再叠上玻璃底色与左上方向的镜面高光。
///
/// 注意：不要把它包进 `Opacity` / `AnimatedOpacity` —— 那会新建图层，
/// 使 `BackdropFilter` 取不到背景。整体淡入请使用 [opacity]。
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.tint = const Color(0x9EFFFFFF),
    this.refraction = 16,
    this.saturation = 1.7,
    this.highlight = 0.5,
    this.blurSigma = 18,
    this.opacity = 1,
    this.showRim = true,
    this.showShadow = true,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// 玻璃底色，alpha 决定「奶感」强弱
  final Color tint;

  /// 边缘折射强度（逻辑像素）
  final double refraction;

  /// 透过玻璃的背景饱和度提升
  final double saturation;

  /// 镜面高光强度
  final double highlight;

  /// 退回模糊实现时的高斯半径
  final double blurSigma;

  /// 整块玻璃的不透明度（0~1），用于淡入而无需外层 Opacity
  final double opacity;

  /// 是否绘制边缘镜面高光
  final bool showRim;

  /// 是否绘制外投影
  final bool showShadow;

  final EdgeInsetsGeometry padding;

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _shader = LiquidGlassProgram.createShader();
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = widget.borderRadius;
    final double corner = math.max(radius.topLeft.x, radius.topLeft.y);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: widget.showShadow
            ? <BoxShadow>[
                BoxShadow(
                  color: const Color(0xFF1F2D3D).withValues(alpha: 0.10),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.5),
                  blurRadius: 2,
                  offset: const Offset(0, -1),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double logicalWidth = constraints.maxWidth;

            return Stack(
              children: <Widget>[
                Positioned.fill(
                  child: _buildBackdrop(
                    logicalWidth.isFinite ? logicalWidth : 0,
                    corner,
                  ),
                ),
                if (widget.showRim)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GlassRimPainter(
                          radius: corner,
                          strength: widget.opacity.clamp(0.0, 1.0),
                        ),
                      ),
                    ),
                  ),
                Padding(padding: widget.padding, child: widget.child),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBackdrop(double logicalWidth, double corner) {
    final double opacity = widget.opacity.clamp(0.0, 1.0);
    final ui.FragmentShader? shader = _shader;

    // u_size 由引擎写入（输入纹理尺寸），不要覆盖。
    // u_logical 只用于求「逻辑像素 → 纹理像素」的比例且只取 x，
    // 因此只要宽度就够，不必等布局完成再量高度。
    if (shader != null && logicalWidth > 0) {
      shader.getUniformFloat('u_logical', 0).set(logicalWidth);
      shader.getUniformFloat('u_logical', 1).set(logicalWidth);
      shader.getUniformFloat('u_radius').set(corner);
      shader.getUniformFloat('u_refraction').set(widget.refraction);
      shader.getUniformFloat('u_tint', 0).set(widget.tint.r);
      shader.getUniformFloat('u_tint', 1).set(widget.tint.g);
      shader.getUniformFloat('u_tint', 2).set(widget.tint.b);
      shader.getUniformFloat('u_tint', 3).set(widget.tint.a);
      shader.getUniformFloat('u_saturation').set(widget.saturation);
      shader.getUniformFloat('u_highlight').set(widget.highlight);
      shader.getUniformFloat('u_opacity').set(opacity);

      try {
        return BackdropFilter(
          filter: ui.ImageFilter.shader(shader),
          child: const SizedBox.expand(),
        );
      } catch (_) {
        // 运行时不可用（非 Impeller）时退回模糊实现
      }
    }

    return BackdropFilter(
      filter: ui.ImageFilter.blur(
        sigmaX: widget.blurSigma,
        sigmaY: widget.blurSigma,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.tint.withValues(alpha: widget.tint.a * opacity),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// 边缘镜面高光：左上亮、右下暗，模拟玻璃的厚度与受光
class _GlassRimPainter extends CustomPainter {
  _GlassRimPainter({required this.radius, required this.strength});

  final double radius;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || strength <= 0) return;

    final Rect bounds = Offset.zero & size;

    // 外圈：左上亮边
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.deflate(0.5), Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Colors.white.withValues(alpha: 0.85 * strength),
            Colors.white.withValues(alpha: 0.10 * strength),
            Colors.white.withValues(alpha: 0.32 * strength),
          ],
          stops: const <double>[0.0, 0.55, 1.0],
        ).createShader(bounds),
    );

    // 内圈：右下暗边，做出厚度
    if (radius >= 2) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          bounds.deflate(1.8),
          Radius.circular(math.max(radius - 1.8, 0)),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Colors.black.withValues(alpha: 0),
              Colors.black.withValues(alpha: 0.05 * strength),
            ],
          ).createShader(bounds),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.strength != strength;
}
