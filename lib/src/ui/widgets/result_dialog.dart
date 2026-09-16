import 'dart:async';
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../../models/picked_image.dart';
import '../../rust/api/assets.dart';
import '../../theme/app_theme.dart';
import 'fade_slide_in.dart';
import 'liquid_glass.dart';

/// 替换结果弹窗：成功时只展示写入清单并自动关闭，失败时逐条列出原因。
Future<void> showApplyResultDialog(BuildContext context, ApplyResult result) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    // 遮罩调淡一些，让玻璃弹窗还能透出底下的页面
    barrierColor: const Color(0x42101828),
    builder: (BuildContext context) => _ApplyResultDialog(result: result),
  );
}

class _ApplyResultDialog extends StatefulWidget {
  const _ApplyResultDialog({required this.result});

  final ApplyResult result;

  @override
  State<_ApplyResultDialog> createState() => _ApplyResultDialogState();
}

class _ApplyResultDialogState extends State<_ApplyResultDialog> {
  /// 成功后的自动关闭倒计时（秒）
  static const int _autoCloseSeconds = 2;

  int _countdown = _autoCloseSeconds;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    if (!widget.result.success) return;

    _tickTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) return;
      if (_countdown <= 1) {
        timer.cancel();
        Navigator.of(context).maybePop();
        return;
      }
      setState(() => _countdown -= 1);
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool success = widget.result.success;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: success ? 460 : 760,
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: LiquidGlass(
          borderRadius: BorderRadius.circular(20),
          tint: const Color(0xB4FFFFFF),
          refraction: 20,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Header(success: success),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
                  child: success ? _successBody() : _failureBody(),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 16, 14),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        success ? '$_countdown 秒后自动关闭' : '请根据下方说明修正后重试',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(success ? '立即关闭' : '知道了'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _successBody() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 6),
        const Center(child: _AnimatedCheck()),
        const SizedBox(height: 12),
        FadeSlideIn(
          delay: const Duration(milliseconds: 120),
          offset: 10,
          child: Center(
            child: Text(
              '替换成功',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.success,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        FadeSlideIn(
          delay: const Duration(milliseconds: 180),
          offset: 10,
          child: Center(
            child: Text(
              widget.result.message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        if (widget.result.items.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Flexible(
            child: Scrollbar(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: widget.result.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (BuildContext context, int index) {
                  final ApplyResultItem item = widget.result.items[index];
                  return FadeSlideIn(
                    key: ValueKey<String>(item.slot),
                    delay: Duration(milliseconds: 220 + index * 55),
                    offset: 12,
                    child: _SuccessRow(item: item),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _failureBody() {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FadeSlideIn(
          offset: 10,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF2D9A8)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Color(0xFFB7791F),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.result.message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8A5A12),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Flexible(
          child: FadeSlideIn(
            delay: const Duration(milliseconds: 100),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowHeight: 38,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 56,
                  columnSpacing: 20,
                  headingTextStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  dataTextStyle: const TextStyle(fontSize: 12),
                  columns: const <DataColumn>[
                    DataColumn(label: Text('位置')),
                    DataColumn(label: Text('写入路径')),
                    DataColumn(label: Text('状态')),
                    DataColumn(label: Text('说明')),
                  ],
                  rows: widget.result.items.map((ApplyResultItem item) {
                    return DataRow(
                      cells: <DataCell>[
                        DataCell(Text(item.slotLabel)),
                        DataCell(
                          Tooltip(
                            message: item.targetPath,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Text(
                                item.targetPath.isEmpty
                                    ? '—'
                                    : baseNameOf(item.targetPath),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Icon(
                            item.ok
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            size: 16,
                            color: item.ok
                                ? AppColors.success
                                : theme.colorScheme.error,
                          ),
                        ),
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(
                              item.message,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: success
              ? const <Color>[
                  Color(0xFF1F9D63),
                  Color(0xFF38C98B),
                  Color(0xFF1F9D63),
                ]
              : const <Color>[
                  Color(0xFF2B5CFF),
                  Color(0xFF8F6BFF),
                  Color(0xFF2FD3C8),
                ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }
}

class _SuccessRow extends StatelessWidget {
  const _SuccessRow({required this.item});

  final ApplyResultItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              item.slotLabel,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.arrow_right_alt_rounded,
              size: 16,
              color: Color(0xFF9AA7BC),
            ),
          ),
          Flexible(
            child: Tooltip(
              message: item.targetPath,
              child: Text(
                baseNameOf(item.targetPath),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 描边逐段绘制出来的对勾
class _AnimatedCheck extends StatelessWidget {
  const _AnimatedCheck();

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 620),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, Widget? child) {
        return SizedBox(
          width: 62,
          height: 62,
          child: CustomPaint(
            painter: _CheckPainter(progress: value),
            child: child,
          ),
        );
      },
      child: const SizedBox.expand(),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.shortestSide / 2 - 3;

    final Paint stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.success;

    // 圆环：前 60% 的进度内画完
    final double circleProgress = (progress / 0.6).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5707963267948966,
      6.283185307179586 * circleProgress,
      false,
      stroke,
    );

    // 对勾：后 40% 的进度内画完
    final double checkProgress = ((progress - 0.55) / 0.45).clamp(0.0, 1.0);
    if (checkProgress <= 0) return;

    final Path path = Path()
      ..moveTo(size.width * 0.29, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.67)
      ..lineTo(size.width * 0.73, size.height * 0.35);

    for (final PathMetric metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * checkProgress),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
