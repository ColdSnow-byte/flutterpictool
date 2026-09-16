import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 主行动按钮：渐变底色 + 柔光阴影，禁用时退化为灰底。
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.loading = false,
    this.count,
    this.minWidth = 132,
    this.height = 46,
  });

  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final bool loading;

  /// 右上角角标数量，0 或 null 时不显示
  final int? count;
  final double minWidth;
  final double height;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null && !widget.loading;
    final List<Color> colors = enabled
        ? const <Color>[Color(0xFF2B5CFF), Color(0xFF4F7DFF), Color(0xFF8F6BFF)]
        : const <Color>[Color(0xFFC8D3E6), Color(0xFFC8D3E6)];

    final double lift = !enabled ? 0 : (_pressed ? 0 : (_hovered ? -2 : 0));

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedScale(
        scale: (enabled && _pressed) ? 0.975 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: Offset(0, widget.height == 0 ? 0 : lift / widget.height),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: widget.height,
            constraints: BoxConstraints(minWidth: widget.minWidth),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: enabled
                  ? <BoxShadow>[
                      BoxShadow(
                        color: AppColors.primary.withValues(
                          alpha: _hovered && !_pressed ? 0.44 : 0.28,
                        ),
                        blurRadius: _hovered && !_pressed ? 26 : 18,
                        offset: Offset(0, _hovered && !_pressed ? 12 : 8),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: enabled ? widget.onPressed : null,
                onHighlightChanged: (bool pressed) {
                  if (!enabled) return;
                  setState(() => _pressed = pressed);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (widget.loading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      else if (widget.icon != null)
                        Icon(widget.icon, size: 18, color: Colors.white),
                      if (widget.loading || widget.icon != null)
                        const SizedBox(width: 8),
                      Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if ((widget.count ?? 0) > 0) ...<Widget>[
                        const SizedBox(width: 8),
                        Container(
                          constraints: const BoxConstraints(minWidth: 20),
                          height: 20,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.26),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${widget.count}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
