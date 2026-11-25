import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Tombol bintang favorit dengan umpan balik haptik + animasi tekan.
///
/// Dipakai di kartu item (grid beranda & halaman favorit). Ukuran area sentuh
/// selalu ≥ 32 px agar nyaman disentuh, terlepas dari ukuran ikon.
class FavoriteStarButton extends StatefulWidget {
  final bool active;
  final VoidCallback onTap;

  /// Ukuran ikon (bukan ukuran area sentuh).
  final double size;

  const FavoriteStarButton({
    super.key,
    required this.active,
    required this.onTap,
    this.size = 20,
  });

  @override
  State<FavoriteStarButton> createState() => _FavoriteStarButtonState();
}

class _FavoriteStarButtonState extends State<FavoriteStarButton> {
  bool _pressed = false;

  void _handleTap() {
    HapticFeedback.selectionClick();
    setState(() => _pressed = true);
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _pressed = false);
    });
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final touchSize = widget.size + 12;

    return Semantics(
      button: true,
      label: widget.active ? 'Hapus dari favorit' : 'Simpan ke favorit',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: AnimatedScale(
          scale: _pressed ? 0.82 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          child: Container(
            width: touchSize,
            height: touchSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.active
                  ? AppTheme.qrAmber.withOpacity(isDark ? 0.20 : 0.14)
                  : Colors.transparent,
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  widget.active ? Icons.star_rounded : Icons.star_outline_rounded,
                  key: ValueKey(widget.active),
                  size: widget.size,
                  color: widget.active
                      ? AppTheme.qrAmber
                      : AppTheme.mutedColor(isDark),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
