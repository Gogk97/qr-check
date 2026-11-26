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

    // 2. Inner Finder Square — kini kristal berfaset (siluet persegi tetap)
    final crystalRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(22 * scale, 22 * scale, 16 * scale, 16 * scale),
      Radius.circular(3.2 * scale),
    );
    canvas.save();
    canvas.clipRRect(crystalRect);
    _paintCrystal(canvas, scale);
    canvas.restore();

    // 3. Center Glint — kilau kecil di tengah meja kristal
    final pipRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(28.2 * scale, 28.2 * scale, 3.6 * scale, 3.6 * scale),
      Radius.circular(0.9 * scale),
    );
    final pipPaint = Paint()
      ..color = Colors.white
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

/// Palet faset kristal (emerald). Terang dari kiri-atas.
class _Crystal {
  // Kontras sengaja lebar: pada ukuran 5-6 px (logo app bar) pola faset
  // melebur, tetapi gradasi terang-kiri-atas ke gelap-kanan-bawah tetap
  // terbaca sebagai kristal, bukan kotak hijau polos.
  static const Color tl = Color(0xFFB7F5DC);
  static const Color tr = Color(0xFF4FD3A6);
  static const Color rt = Color(0xFF2CB98D);
  static const Color rb = Color(0xFF0E9068);
  static const Color br = Color(0xFF086B4E);
  static const Color bl = Color(0xFF077251);
  static const Color lb = Color(0xFF0F9468);
  static const Color lt = Color(0xFF1FA87C);
  static const Color table = Color(0xFF5FE0B4);
}

/// Menggambar persegi kristal berfaset di dalam area 22..38 (skala 64).
///
/// Siluet tetap persegi membulat; bagian dalam dipecah menjadi 8 faset tepi +
/// 1 meja tengah, masing-masing satu warna datar (tanpa gradien).
void _paintCrystal(Canvas canvas, double scale) {
  Offset p(double x, double y) => Offset(x * scale, y * scale);

  void facet(List<Offset> points, Color color) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  // Titik kunci (koordinat 64-space).
  final tlCorner = p(22, 22);
  final trCorner = p(38, 22);
  final brCorner = p(38, 38);
  final blCorner = p(22, 38);
  final topMid = p(30, 22);
  final rightMid = p(38, 30);
  final bottomMid = p(30, 38);
  final leftMid = p(22, 30);
  final n = p(30, 25.6);
  final e = p(34.4, 30);
  final s = p(30, 34.4);
  final w = p(25.6, 30);

  // 8 faset tepi.
  facet([tlCorner, topMid, n, w], _Crystal.tl);
  facet([topMid, trCorner, e, n], _Crystal.tr);
  facet([trCorner, e, rightMid], _Crystal.rt);
  facet([rightMid, brCorner, s, e], _Crystal.rb);
  facet([brCorner, bottomMid, s], _Crystal.br);
  facet([bottomMid, blCorner, w, s], _Crystal.bl);
  facet([blCorner, leftMid, w], _Crystal.lb);
  facet([leftMid, tlCorner, n, w], _Crystal.lt);

  // Meja tengah (diamond).
  facet([n, e, s, w], _Crystal.table);
}
