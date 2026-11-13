import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoadingGoogle = false;
  bool _isLoadingGuest = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoadingGoogle = true);
    try {
      final user = await AuthService.loginWithGoogle();
      if (!mounted) return;
      if (user == null) {
        // User membatalkan pemilihan akun Google
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selamat datang, ${user.name}!'),
          backgroundColor: AppTheme.qrisGreenDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      // Tangani error konfigurasi Google Cloud / OAuth pada mode debug
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Google Sign-In: Perlu konfigurasi SHA-1 / OAuth Client ID.\nError: $e',
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Mode Dev',
            textColor: Colors.amber,
            onPressed: () async {
              final devUser = await AuthService.loginWithGoogleDevFallback();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Masuk via Mode Dev: ${devUser.name}'),
                  backgroundColor: AppTheme.qrisGreenDark,
                ),
              );
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
              );
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingGoogle = false);
    }
  }

  Future<void> _handleGuestSignIn() async {
    setState(() => _isLoadingGuest = true);
    try {
      await AuthService.loginAsGuest();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Masuk dalam Mode Tamu (Akses Penuh).'),
          backgroundColor: AppTheme.primary,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal masuk sebagai tamu: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingGuest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Hero Icon Container with Glow & Gradient
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppTheme.primary,
                            AppTheme.primary.withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withOpacity(0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.qr_code_scanner_rounded,
                          color: Colors.white,
                          size: 46,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // App Title & Tagline
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'QRIS Detector',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.qrisGreen.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.qrisGreen.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'AI',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.qrisGreenDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Kelola, validasi, dan bersihkan bukti transaksi QRIS galeri ponsel Anda dengan cepat dan aman.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Feature Benefit Badges
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildFeatureRow(
                          icon: Icons.bolt_rounded,
                          iconColor: Colors.amber,
                          title: 'Pemindaian Paralel AI',
                          subtitle: 'Pindai ratusan foto galeri dalam hitungan detik.',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildFeatureRow(
                          icon: Icons.security_rounded,
                          iconColor: AppTheme.qrisGreen,
                          title: 'Privasi Terjaga 100%',
                          subtitle: 'Pemrosesan on-device tanpa unggah ke server.',
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildFeatureRow(
                          icon: Icons.delete_sweep_rounded,
                          iconColor: AppTheme.primary,
                          title: 'Pembersihan Massal Hemat Ruang',
                          subtitle: 'Hapus bukti transfer usang untuk melegakan memori.',
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Button 1: Login with Google
                  ElevatedButton(
                    onPressed: (_isLoadingGoogle || _isLoadingGuest) ? null : _handleGoogleSignIn,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                      foregroundColor: isDark ? Colors.white : const Color(0xFF1F2937),
                      elevation: 1,
                      shadowColor: Colors.black.withOpacity(0.1),
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                    child: _isLoadingGoogle
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildGoogleIcon(),
                              const SizedBox(width: 12),
                              const Text(
                                'Lanjutkan dengan Google',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),

                  // Button 2: Guest User Login
                  OutlinedButton(
                    onPressed: (_isLoadingGoogle || _isLoadingGuest) ? null : _handleGuestSignIn,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isDark
                          ? AppTheme.primary.withOpacity(0.12)
                          : const Color(0xFFF1F5F9),
                      foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      side: BorderSide(
                        color: isDark ? AppTheme.primary.withOpacity(0.4) : const Color(0xFFCBD5E1),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoadingGuest
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: 20,
                                color: AppTheme.primary,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'Masuk sebagai Tamu (Guest)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),

                  // Privacy / Terms Note
                  Text(
                    'Dengan masuk, Anda menyetujui Ketentuan Layanan & Kebijakan Privasi QRIS Detector.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Custom Google 'G' Multi-Color Icon
  Widget _buildGoogleIcon() {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(
        painter: _GoogleLogoPainter(),
      ),
    );
  }
}

/// Custom Painter for Google 'G' Logo (Blue, Red, Yellow, Green)
class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    final bluePaint = Paint()..color = const Color(0xFF4285F4);

    final rect = Rect.fromCircle(center: center, radius: radius);

    // Blue horizontal bar
    final barRect = Rect.fromLTWH(w * 0.45, h * 0.38, w * 0.55, h * 0.24);
    canvas.drawRRect(RRect.fromRectAndRadius(barRect, const Radius.circular(2)), bluePaint);

    // Draw Google Circular arcs
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.22
      ..strokeCap = StrokeCap.butt;

    // Blue arc (right)
    strokePaint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect.deflate(w * 0.11), -0.7, 1.4, false, strokePaint);

    // Green arc (bottom)
    strokePaint.color = const Color(0xFF34A853);
    canvas.drawArc(rect.deflate(w * 0.11), 0.7, 1.6, false, strokePaint);

    // Yellow arc (left)
    strokePaint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect.deflate(w * 0.11), 2.3, 1.6, false, strokePaint);

    // Red arc (top)
    strokePaint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect.deflate(w * 0.11), 3.9, 1.5, false, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
