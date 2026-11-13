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

    // Border and accent color based on classification
    final Color accentColor = item.isQRIS
        ? AppTheme.qrisGreen
        : (item.hasQR ? AppTheme.qrAmber : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)));

    final double borderWidth = (item.isQRIS || item.hasQR || item.isSelected) ? 2.0 : 1.0;

    return InkWell(
      onTap: () => QRISDetailBottomSheet.show(context, item),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: item.isSelected ? AppTheme.primary : accentColor,
            width: borderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: item.isQRIS
                  ? AppTheme.qrisGreen.withOpacity(0.12)
                  : Colors.black.withOpacity(isDark ? 0.25 : 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
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
                      color: Colors.grey.shade300,
                      child: const Center(
                        child: Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  ),

                  // Overlay gradient for badge legibility
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.4),
                            Colors.transparent,
                            Colors.black.withOpacity(0.5),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // Top Left: Selection Checkbox
                  if (showSelection)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: InkWell(
                        onTap: () => onSelectChanged(!item.isSelected),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: item.isSelected
                                ? AppTheme.primary
                                : Colors.black.withOpacity(0.4),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            item.isSelected ? Icons.check : Icons.circle_outlined,
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                  // Top Right: Status Badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildBadge(context),
                  ),

                  // Bottom Overlay on Image: Dynamic Amount or QR type
                  if (item.isQRIS && item.qrisDetails?.amount != null)
                    Positioned(
                      bottom: 6,
                      left: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          currencyFormatter.format(item.qrisDetails!.amount),
                          style: const TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
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
                        color: Colors.black45,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bottom Info Section
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.isQRIS
                        ? (item.qrisDetails?.merchantName ?? 'QRIS Terdeteksi')
                        : (item.hasQR ? 'QR Code [${item.qrType.toUpperCase()}]' : item.fileName),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: item.isQRIS
                          ? (isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark)
                          : (isDark ? Colors.white : const Color(0xFF0F172A)),
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
                            fontSize: 11,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
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
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
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
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Scanning...',
          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (item.isQRIS) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.qrisGreen,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: AppTheme.qrisGreen.withOpacity(0.5),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified, size: 11, color: Colors.white),
            SizedBox(width: 3),
            Text(
              'QRIS',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
    }

    if (item.hasQR) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.qrAmber,
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code, size: 11, color: Colors.white),
            SizedBox(width: 3),
            Text(
              'QR',
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'Bukan QR',
        style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w500),
      ),
    );
  }
}
