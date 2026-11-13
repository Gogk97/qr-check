import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
      if (user != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal login Google: $e'),
          backgroundColor: AppTheme.dangerRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingGoogle = false);
      }
    }
  }

  Future<void> _handleGuestLogin() async {
    setState(() => _isLoadingGuest = true);
    try {
      await AuthService.loginAsGuest();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal masuk sebagai tamu: $e'),
          backgroundColor: AppTheme.dangerRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoadingGuest = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 3-Tone Carbon & Alabaster Fintech Palette
    const bgCanvas = AppTheme.backgroundDark; // #0A0E0D Carbon Obsidian
    const cardSurface = AppTheme.surfaceDark; // #121816 Matte Graphite
    const subtleSurface = AppTheme.surfaceSubtleDark; // #18201D
    const borderHairline = AppTheme.borderDark; // #232D29
    const inkPrimary = AppTheme.textLight; // #F1F5F3 Crisp Chalk
    const inkMuted = AppTheme.textMutedDark; // #8E9993 Mineral Slate
    const accentEmerald = AppTheme.qrisGreen; // #0B8760 Verification Emerald

    return Scaffold(
      backgroundColor: bgCanvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Top Technical Status Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: cardSurface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: borderHairline),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: accentEmerald,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'EMVCo / BI QRIS INSPECTOR',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'v1.0',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: inkMuted,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Main Identity & Optical Scanner Card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: cardSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderHairline, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Tactile Optical Viewfinder Emblem
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: subtleSurface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: accentEmerald.withOpacity(0.55),
                                  width: 1.2,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.qr_code_scanner_rounded,
                                  size: 26,
                                  color: Color(0xFF34D399),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'QRIS Detector',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: inkPrimary,
                                      letterSpacing: -0.6,
                                      height: 1.15,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Gallery Audit & CRC16 Validator',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF34D399),
                                      letterSpacing: -0.1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(height: 1, color: borderHairline),
                        const SizedBox(height: 16),
                        Text(
                          'Deteksi, verifikasi keaslian payload QRIS, dan bersihkan tumpukan gambar QR di galeri perangkat secara presisi.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13.5,
                            color: inkMuted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3-Column Specification Ledger (Preserves exact test labels)
                  Container(
                    decoration: BoxDecoration(
                      color: cardSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderHairline, width: 1),
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildLedgerSpec(
                              icon: Icons.verified_user_outlined,
                              value: 'GOOGLE',
                              label: '10 Kuota Hapus',
                              accent: const Color(0xFF34D399),
                            ),
                          ),
                          Container(width: 1, color: borderHairline),
                          Expanded(
                            child: _buildLedgerSpec(
                              icon: Icons.person_outline_rounded,
                              value: 'TAMU',
                              label: '5 Kuota / Hari',
                              accent: AppTheme.qrAmber,
                            ),
                          ),
                          Container(width: 1, color: borderHairline),
                          Expanded(
                            child: _buildLedgerSpec(
                              icon: Icons.sync_lock_rounded,
                              value: 'BACKUP',
                              label: 'Cloud Sync',
                              accent: inkPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Authentication Action Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderHairline, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Primary Action: Google Sign In (High-Contrast Alabaster on Carbon)
                        SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: (_isLoadingGoogle || _isLoadingGuest)
                                ? null
                                : _handleGoogleSignIn,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: inkPrimary,
                              foregroundColor: AppTheme.textDark,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              disabledBackgroundColor: inkPrimary.withOpacity(0.5),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _isLoadingGoogle
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      color: AppTheme.textDark,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: AppTheme.textDark,
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          'G',
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: inkPrimary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          'Lanjutkan dengan Google',
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.textDark,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Secondary Action: Guest Mode
                        SizedBox(
                          height: 48,
                          child: OutlinedButton(
                            onPressed: (_isLoadingGoogle || _isLoadingGuest)
                                ? null
                                : _handleGuestLogin,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: subtleSurface,
                              foregroundColor: inkPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              side: const BorderSide(color: borderHairline, width: 1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: _isLoadingGuest
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: inkPrimary,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.person_outline_rounded,
                                        size: 18,
                                        color: inkMuted,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Masuk sebagai Tamu (Guest)',
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: inkPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),

                        const SizedBox(height: 14),
                        Text(
                          'Login Google memberikan 10 kuota hapus awal & sinkronisasi otomatis.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: inkMuted,
                            height: 1.4,
                          ),
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
    );
  }

  Widget _buildLedgerSpec({
    required IconData icon,
    required String value,
    required String label,
    required Color accent,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 17),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: AppTheme.textMutedDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }
}
