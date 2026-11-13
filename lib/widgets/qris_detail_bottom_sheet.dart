import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scanned_item.dart';
import '../theme/app_theme.dart';

class QRISDetailBottomSheet extends StatelessWidget {
  final ScannedItem item;

  const QRISDetailBottomSheet({super.key, required this.item});

  static void show(BuildContext context, ScannedItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => QRISDetailBottomSheet(item: item),
    );
  }

  /// Menampilkan gambar secara layar penuh dengan fitur cubit/perbesar (InteractiveViewer)
  void _openFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: const Color(0xFF0A0E0D),
          appBar: AppBar(
            backgroundColor: const Color(0xE60A0E0D),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: const Border(
              bottom: BorderSide(color: Color(0xFF232D29), width: 1),
            ),
            title: Text(
              item.isQRIS
                  ? (item.qrisDetails?.merchantName ?? item.fileName)
                  : item.fileName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'Bagikan Foto',
                icon: const Icon(Icons.share_outlined, color: Colors.white, size: 20),
                onPressed: () {
                  Share.shareXFiles([XFile(item.file.path)], text: item.rawContent);
                },
              ),
            ],
          ),
          body: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.8,
                  maxScale: 5.0,
                  child: Image.file(
                    item.file,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                bottom: 28,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xCC121816),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF232D29)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in_rounded, color: Colors.white70, size: 15),
                        SizedBox(width: 6),
                        Text(
                          'Cubit layar untuk memperbesar gambar',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final details = item.qrisDetails;
    final borderCol = AppTheme.borderColor(isDark);
    final ink = AppTheme.inkColor(isDark);
    final muted = AppTheme.mutedColor(isDark);

    final currencyFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.86,
      ),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        border: Border(
          top: BorderSide(color: borderCol, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle bar
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: borderCol,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Image & File Summary
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _openFullScreenImage(context),
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: borderCol),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(9),
                                child: Image.file(
                                  item.file,
                                  width: 80,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xCC0A0E0D),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Icon(
                                  Icons.open_in_full_rounded,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.fileName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                                color: ink,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Ukuran: ${item.formattedFileSize}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: muted,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => _openFullScreenImage(context),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppTheme.subtleBg(isDark),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: borderCol),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.zoom_out_map_rounded, size: 12, color: ink),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Perbesar Gambar',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: ink,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  if (item.isQRIS && details != null) ...[
                    // QRIS Verification Ledger Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleBg(isDark),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.qrisGreen.withOpacity(0.45),
                          width: 1.2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                    decoration: BoxDecoration(
                                      color: AppTheme.qrisGreenDark,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: const Text(
                                      'QRIS ASPI / BI',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                    decoration: BoxDecoration(
                                      color: details.isDynamic
                                          ? AppTheme.qrAmber.withOpacity(0.15)
                                          : AppTheme.cardColor(isDark),
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(
                                        color: details.isDynamic
                                            ? AppTheme.qrAmber.withOpacity(0.45)
                                            : borderCol,
                                      ),
                                    ),
                                    child: Text(
                                      details.isDynamic ? 'Dinamis (Ada Nominal)' : 'Statis',
                                      style: TextStyle(
                                        color: details.isDynamic ? AppTheme.qrAmber : muted,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (details.isValidCRC)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.qrisGreen.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified_rounded, color: AppTheme.qrisGreen, size: 13),
                                      SizedBox(width: 4),
                                      Text(
                                        'CRC Valid',
                                        style: TextStyle(
                                          color: AppTheme.qrisGreen,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            details.merchantName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 13,
                                color: muted,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  '${details.merchantCity} • Pos ${details.postalCode}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: muted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (details.amount != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.cardColor(isDark),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: borderCol),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Nominal Pembayaran',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: muted,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        currencyFormatter.format(details.amount),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark,
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Detail Items Ledger Box
                    Container(
                      decoration: BoxDecoration(
                        color: AppTheme.cardColor(isDark),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderCol),
                      ),
                      child: Column(
                        children: [
                          _buildInfoRow(
                            'NMID',
                            details.nmid.isNotEmpty ? details.nmid : '-',
                            isDark,
                            context,
                            showBottomBorder: true,
                          ),
                          if (details.acquirer.isNotEmpty)
                            _buildInfoRow(
                              'Penyelenggara',
                              details.acquirer,
                              isDark,
                              context,
                              showBottomBorder: true,
                            ),
                          _buildInfoRow(
                            'Merchant Category (MCC)',
                            details.mcc,
                            isDark,
                            context,
                            showBottomBorder: false,
                          ),
                        ],
                      ),
                    ),
                  ] else if (item.hasQR) ...[
                    // Info QR Biasa
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.qrAmber.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.qrAmber.withOpacity(0.35)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.qr_code_rounded, color: AppTheme.qrAmber, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Gambar ini memiliki kode QR tipe [${item.qrType.toUpperCase()}], namun bukan format QRIS pembayaran resmi.',
                              style: TextStyle(fontSize: 12.5, color: ink, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Bukan QR
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleBg(isDark),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderCol),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.hide_image_outlined, color: muted, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Tidak terdeteksi QR Code atau QRIS pada foto ini.',
                              style: TextStyle(fontSize: 12.5, color: muted),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (item.rawContent != null && item.rawContent!.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Isi Mentah QR (Payload)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: ink,
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: item.rawContent!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Isi QR berhasil disalin!')),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.copy_rounded, size: 13, color: AppTheme.primary),
                                SizedBox(width: 4),
                                Text(
                                  'Salin',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleBg(isDark),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderCol),
                      ),
                      child: SelectableText(
                        item.rawContent!,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          height: 1.45,
                          color: ink,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Share.shareXFiles(
                              [XFile(item.file.path)],
                              text: item.rawContent,
                            );
                          },
                          icon: Icon(Icons.share_outlined, size: 17, color: ink),
                          label: Text(
                            'Bagikan Foto',
                            style: TextStyle(color: ink, fontWeight: FontWeight.w600),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: borderCol),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      if (item.rawContent != null) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: item.rawContent!));
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Teks QR berhasil disalin ke papan klip!')),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 17),
                            label: const Text('Salin Teks'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: item.isQRIS ? AppTheme.qrisGreenDark : AppTheme.textDark,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value,
    bool isDark,
    BuildContext context, {
    bool showBottomBorder = false,
  }) {
    final borderCol = AppTheme.borderColor(isDark);
    final ink = AppTheme.inkColor(isDark);
    final muted = AppTheme.mutedColor(isDark);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: showBottomBorder
            ? Border(bottom: BorderSide(color: borderCol, width: 1))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 135,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: ink,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$label disalin!')),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 13,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
