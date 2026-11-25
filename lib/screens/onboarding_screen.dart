import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Panduan singkat saat aplikasi pertama kali dibuka.
///
/// Ditampilkan sekali saja — penanda disimpan di SharedPreferences.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  /// Kunci penyimpanan status "sudah pernah melihat onboarding".
  static const String prefsKey = 'onboarding_v1_done';

  /// Tampilkan onboarding bila belum pernah dilihat.
  static Future<void> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(prefsKey) ?? false) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, animation, __) => FadeTransition(
          opacity: animation,
          child: const OnboardingScreen(),
        ),
      ),
    );
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_Slide> _slides = [
    _Slide(
      icon: Icons.photo_library_rounded,
      title: 'Pindai galeri sekali jalan',
      body:
          'AI memeriksa seluruh foto sekaligus dan hanya menyimpan QRIS yang '
          'punya nominal. Foto biasa tidak ikut tersimpan, jadi daftar tetap bersih.',
      accent: AppTheme.qrisGreen,
    ),
    _Slide(
      icon: Icons.share_rounded,
      title: 'Dari WhatsApp langsung ke sini',
      body:
          'Ketuk Bagikan di WhatsApp atau Telegram, pilih Qristal — gambar '
          'langsung dipindai. Tidak perlu screenshot lalu mencari di galeri.',
      accent: AppTheme.qrAmber,
    ),
    _Slide(
      icon: Icons.insights_rounded,
      title: 'Laporan rapi untuk PRO',
      body:
          'Grafik nominal, filter tanggal & harga, ekspor CSV/Excel, favorit, '
          'dan rapikan nama file. Bayar sekali, pakai selamanya.',
      accent: AppTheme.primary,
    ),
  ];

  bool get _isLast => _page == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingScreen.prefsKey, true);
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 12, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Lewati',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mutedColor(isDark),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _buildSlide(isDark, _slides[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active
                        ? AppTheme.qrisGreenDark
                        : AppTheme.borderColor(isDark),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.qrisGreenDark,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _isLast ? 'Mulai Sekarang' : 'Lanjut',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(bool isDark, _Slide slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              color: slide.accent.withOpacity(isDark ? 0.18 : 0.10),
              shape: BoxShape.circle,
              border: Border.all(
                color: slide.accent.withOpacity(0.28),
                width: 1.4,
              ),
            ),
            child: Icon(slide.icon, size: 60, color: slide.accent),
          ),
          const SizedBox(height: 34),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 23,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: AppTheme.inkColor(isDark),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: AppTheme.mutedColor(isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _Slide {
  const _Slide({
    required this.icon,
    required this.title,
    required this.body,
    required this.accent,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color accent;
}
