import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Widget Logo Resmi QRIS Detector — Opsi 03: The Q-Fiducial Monogram (Swiss Design).
///
/// Menggabungkan bingkai huruf 'Q' dari finder pattern QR, inti Verification Emerald (#0B8760),
/// titik tengah fiducial, dan ekor diagonal Warm Brass (#C67D15).
class AppLogo extends StatelessWidget {
  final double size;
  final bool? forceDark;
  final bool showContainer;

  const AppLogo({
    super.key,
    this.size = 36,
    this.forceDark,
    this.showContainer = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = forceDark ?? (Theme.of(context).brightness == Brightness.dark);

    final glyph = CustomPaint(
      size: Size(size * (showContainer ? 0.68 : 1.0), size * (showContainer ? 0.68 : 1.0)),
      painter: _QFiducialLogoPainter(isDark: isDark),
    );

    if (!showContainer) return glyph;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(size * 0.22),
        border: Border.all(
          color: isDark ? AppTheme.borderDark : AppTheme.borderLight,
          width: 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: glyph,
    );
  }
}

class _QFiducialLogoPainter extends CustomPainter {
  final bool isDark;

  const _QFiducialLogoPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 64.0;

    final frameColor = isDark ? AppTheme.textLight : AppTheme.textDark;
    const emeraldColor = AppTheme.qrisGreen;
    const brassColor = AppTheme.qrAmber;

    // 1. Outer Q Frame (x=11, y=11, w=38, h=38, rx=9, strokeWidth=5.5)
    final outerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(11 * scale, 11 * scale, 38 * scale, 38 * scale),
      Radius.circular(9 * scale),
    );
    final framePaint = Paint()
      ..color = frameColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(outerRect, framePaint);

    // 2. Inner Finder Square in Verification Emerald (x=22, y=22, w=16, h=16, rx=3)
    final innerRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(22 * scale, 22 * scale, 16 * scale, 16 * scale),
      Radius.circular(3.2 * scale),
    );
    final emeraldPaint = Paint()
      ..color = emeraldColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(innerRect, emeraldPaint);

    // 3. Center Fiducial Pip (x=27, y=27, w=6, h=6, rx=1.2)
    final pipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(27 * scale, 27 * scale, 6 * scale, 6 * scale),
      Radius.circular(1.2 * scale),
    );
    final pipPaint = Paint()
      ..color = isDark ? AppTheme.textLight : Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRRect(pipRect, pipPaint);

    // 4. Q Tail Slash in Warm Brass (39,39 -> 53,53, strokeWidth=6.5)
    final tailPaint = Paint()
      ..color = brassColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5 * scale
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(39 * scale, 39 * scale),
      Offset(53 * scale, 53 * scale),
      tailPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _QFiducialLogoPainter oldDelegate) {
    return oldDelegate.isDark != isDark;
  }
}
