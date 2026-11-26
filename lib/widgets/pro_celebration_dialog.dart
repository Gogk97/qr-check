import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Menampilkan perayaan setelah pembelian PRO berhasil.
Future<void> showProCelebration(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Perayaan PRO',
    barrierColor: Colors.black.withOpacity(0.62),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, __, ___) => const _ProCelebrationDialog(),
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _ProCelebrationDialog extends StatefulWidget {
  const _ProCelebrationDialog();

  @override
  State<_ProCelebrationDialog> createState() => _ProCelebrationDialogState();
}

class _ProCelebrationDialogState extends State<_ProCelebrationDialog>
    with TickerProviderStateMixin {
  late final AnimationController _confetti;
  late final AnimationController _badge;
  late final List<_Particle> _particles;

  static const _proFeatures = <(IconData, String, String)>[
    (Icons.all_inclusive_rounded, 'Kuota tanpa batas', 'Pindai & simpan sebanyak apa pun'),
    (Icons.star_rounded, 'Favorit QRIS', 'Simpan QRIS langganan di urutan teratas'),
    (Icons.insights_rounded, 'Laporan & ekspor', 'Chart, filter tanggal/harga, CSV/Excel'),
    (Icons.drive_file_rename_outline_rounded, 'Rapikan nama file', 'Nama otomatis dari isi QRIS'),
    (Icons.backup_rounded, 'Backup .qristal', 'Amankan & pindahkan ke HP baru'),
    (Icons.block_rounded, 'Tanpa iklan', 'Fokus tanpa gangguan'),
  ];

  @override
  void initState() {
    super.initState();
    _confetti = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _badge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _particles = _Particle.spawn(52);
    _confetti.forward();
    _badge.forward();
  }

  @override
  void dispose() {
    _confetti.dispose();
    _badge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final textColor = dark ? AppTheme.textLight : AppTheme.textDark;
    final mutedColor = dark ? AppTheme.textMutedDark : AppTheme.textMuted;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 400,
              maxHeight: MediaQuery.of(context).size.height * 0.88,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: dark ? AppTheme.borderDark : AppTheme.borderLight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(dark ? 0.5 : 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  children: [
                    // Kilau lembut di bagian atas kartu.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: const Alignment(0, -0.9),
                              radius: 0.9,
                              colors: [
                                AppTheme.qrisGreen
                                    .withOpacity(dark ? 0.28 : 0.16),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _confetti,
                          builder: (_, __) => CustomPaint(
                            painter: _ConfettiPainter(
                              progress: _confetti.value,
                              particles: _particles,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildBadge(dark),
                          const SizedBox(height: 18),
                          Text(
                            'Selamat, kamu PRO!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 23,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Pembayaran berhasil. Bayar sekali, semua fitur terbuka selamanya.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: mutedColor,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: dark
                                  ? AppTheme.surfaceSubtleDark
                                  : AppTheme.surfaceSubtleLight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                for (var i = 0; i < _proFeatures.length; i++)
                                  _FeatureRow(
                                    icon: _proFeatures[i].$1,
                                    title: _proFeatures[i].$2,
                                    subtitle: _proFeatures[i].$3,
                                    textColor: textColor,
                                    mutedColor: mutedColor,
                                    showDivider: i != _proFeatures.length - 1,
                                    dark: dark,
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Mantap, mulai pakai!',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.verified_rounded,
                                  size: 13, color: AppTheme.primary),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  'Aktif permanen di akun ini',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: mutedColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(bool dark) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _badge, curve: Curves.elasticOut),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF14B383), AppTheme.qrisGreenDark],
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.qrisGreen.withOpacity(0.38),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.workspace_premium_rounded,
                color: Colors.white, size: 44),
            Positioned(
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.textColor,
    required this.mutedColor,
    required this.showDivider,
    required this.dark,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color textColor;
  final Color mutedColor;
  final bool showDivider;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(dark ? 0.22 : 0.11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 15, color: AppTheme.primary),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 11.5, color: mutedColor),
                    ),
                  ],
                ),
              ),
              Icon(Icons.check_circle_rounded,
                  size: 17, color: AppTheme.primary.withOpacity(0.9)),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: (dark ? AppTheme.borderDark : AppTheme.borderLight)
                .withOpacity(0.55),
          ),
      ],
    );
  }
}

/// Partikel konfeti sederhana: jatuh, berputar, dan memudar.
class _Particle {
  _Particle({
    required this.x,
    required this.delay,
    required this.speed,
    required this.size,
    required this.rotation,
    required this.spin,
    required this.sway,
    required this.color,
  });

  final double x; // 0..1 relatif lebar kartu
  final double delay; // 0..0.35
  final double speed; // 0.9..1.8
  final double size;
  final double rotation;
  final double spin;
  final double sway;
  final Color color;

  static List<_Particle> spawn(int count) {
    final rnd = math.Random(7);
    const palette = [
      AppTheme.qrisGreen,
      Color(0xFF14B383),
      AppTheme.qrAmber,
      Color(0xFF3B82F6),
      Color(0xFFEAB308),
      Color(0xFFF1F5F3),
    ];
    return List.generate(count, (i) {
      return _Particle(
        x: rnd.nextDouble(),
        delay: rnd.nextDouble() * 0.35,
        speed: 0.9 + rnd.nextDouble() * 0.9,
        size: 4 + rnd.nextDouble() * 5.5,
        rotation: rnd.nextDouble() * math.pi * 2,
        spin: (rnd.nextDouble() - 0.5) * 9,
        sway: (rnd.nextDouble() - 0.5) * 26,
        color: palette[i % palette.length],
      );
    });
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.particles});

  final double progress;
  final List<_Particle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final t = ((progress - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final dy = -20 + t * (size.height + 60) * p.speed;
      final dx = p.x * size.width + math.sin(t * math.pi * 2) * p.sway;
      final opacity = t > 0.75 ? (1 - (t - 0.75) / 0.25) : 1.0;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.rotation + t * p.spin);
      paint.color = p.color.withOpacity((opacity * 0.95).clamp(0.0, 1.0));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 1.6,
          ),
          const Radius.circular(1.6),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.progress != progress || old.particles != particles;
}
