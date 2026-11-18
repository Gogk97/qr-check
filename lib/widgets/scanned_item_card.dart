import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/scanned_item.dart';
import '../theme/app_theme.dart';
import 'qris_detail_bottom_sheet.dart';

class ScannedItemCard extends StatelessWidget {
  final ScannedItem item;
  final ValueChanged<bool?> onSelectChanged;
  final bool showSelection;

  const ScannedItemCard({
    super.key,
    required this.item,
    required this.onSelectChanged,
    this.showSelection = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    final baseBorder = AppTheme.borderColor(isDark);
    final Color borderColor = item.isSelected
        ? AppTheme.primary
        : (item.isQRIS
            ? AppTheme.qrisGreen.withOpacity(isDark ? 0.65 : 0.5)
            : (item.hasQR ? AppTheme.qrAmber.withOpacity(0.55) : baseBorder));

    final double borderWidth = (item.isSelected || item.isQRIS) ? 1.5 : 1.0;

    return InkWell(
      onTap: () => QRISDetailBottomSheet.show(context, item),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: AppTheme.cardColor(isDark),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Image Thumbnail Section
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    item.file,
                    fit: BoxFit.cover,
                    cacheWidth: 350,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppTheme.subtleBg(isDark),
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: AppTheme.mutedColor(isDark),
                          size: 22,
                        ),
                      ),
                    ),
                  ),

                  // Subtle top scrim for legibility
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.48),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Top Left: Tactile Selection Checkbox
                  if (showSelection)
                    Positioned(
                      top: 7,
                      left: 7,
                      child: GestureDetector(
                        onTap: () => onSelectChanged(!item.isSelected),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: item.isSelected
                                ? AppTheme.primary
                                : const Color(0xB30A0E0D),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: item.isSelected
                                  ? AppTheme.primary
                                  : Colors.white.withOpacity(0.55),
                              width: 1.2,
                            ),
                          ),
                          child: item.isSelected
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 15,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                      ),
                    ),

                  // Top Right: Crisp Classification Badge
                  Positioned(
                    top: 7,
                    right: 7,
                    child: _buildBadge(context),
                  ),

                  // Bottom Overlay on Image: Dynamic Amount
                  if (item.isQRIS && item.qrisDetails?.amount != null)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xE60A0E0D),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: AppTheme.qrisGreen.withOpacity(0.5),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          currencyFormatter.format(item.qrisDetails!.amount),
                          style: const TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),

                  // Processing Spinner
                  if (item.isProcessing)
                    Positioned.fill(
                      child: Container(
                        color: const Color(0x990A0E0D),
                        child: const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Structural Hairline Divider
            Container(
              height: 1,
              color: baseBorder,
            ),

            // Bottom Metadata Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.isQRIS
                        ? (item.qrisDetails?.merchantName ?? 'QRIS Terdeteksi')
                        : (item.hasQR ? 'QR Code [${item.qrType.toUpperCase()}]' : item.fileName),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: item.isQRIS
                          ? (isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark)
                          : AppTheme.inkColor(isDark),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.isQRIS
                              ? (item.qrisDetails?.merchantCity ?? 'Indonesia')
                              : (item.hasQR ? 'Berisi data' : 'Tanpa QR'),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.mutedColor(isDark),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.formattedFileSize,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.mutedColor(isDark),
                          fontFeatures: const [FontFeature.tabularFigures()],
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
    );
  }

  Widget _buildBadge(BuildContext context) {
    if (item.isProcessing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xCC0A0E0D),
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Text(
          'SCANNING',
          style: TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    if (item.isQRIS) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: AppTheme.qrisGreenDark,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: Colors.white.withOpacity(0.22),
            width: 0.8,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 10, color: Colors.white),
            SizedBox(width: 3),
            Text(
              'QRIS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    if (item.hasQR) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: AppTheme.qrAmber,
          borderRadius: BorderRadius.circular(5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_rounded, size: 10, color: Colors.white),
            SizedBox(width: 3),
            Text(
              'QR',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: const Color(0xB30A0E0D),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Text(
        'Bukan QR',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
