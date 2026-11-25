import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scanned_item.dart';
import '../services/backup_service.dart';
import '../services/monetization_service.dart';
import '../theme/app_theme.dart';
import '../utils/app_log.dart';

/// Halaman backup & pemulihan data QRIS.
///
/// Backup (PRO) membuat satu file `.qristal` yang bisa disimpan di Drive,
/// WhatsApp, atau penyimpanan eksternal. Pemulihan gratis — supaya pengguna
/// selalu bisa menyelamatkan datanya.
class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    required this.items,
    required this.onRestored,
  });

  final List<ScannedItem> items;

  /// Dipanggil setelah pemulihan berhasil; item baru sudah ditambahkan ke sini.
  final Future<void> Function(List<ScannedItem> restored) onRestored;

  static Future<void> open(
    BuildContext context, {
    required List<ScannedItem> items,
    required Future<void> Function(List<ScannedItem> restored) onRestored,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BackupScreen(items: items, onRestored: onRestored),
      ),
    );
  }

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  static final DateFormat _dateFmt = DateFormat('d MMM yyyy · HH:mm', 'id_ID');

  bool _busy = false;

  Future<void> _createBackup() async {
    final isPro = await MonetizationService.isProUser();
    if (!isPro) {
      if (!mounted) return;
      await MonetizationService.openProPurchase(context);
      return;
    }
    if (widget.items.isEmpty) {
      _snack('Belum ada QRIS untuk dibackup.');
      return;
    }

    setState(() => _busy = true);
    try {
      final file = await BackupService.createBackup(widget.items);
      final size = await file.length();
      await Share.shareXFiles(
        [XFile(file.path, mimeType: BackupService.mimeType)],
        subject: 'Backup Qristal (${widget.items.length} QRIS)',
      );
      _snack('Backup siap: ${widget.items.length} QRIS · '
          '${_prettySize(size)}');
    } catch (e) {
      AppLog.d('⚠️ Backup gagal: $e');
      _snack('Backup gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      // `.qristal` tidak punya MIME resmi, jadi memakai filter ekstensi akan
      // menyembunyikan file di DocumentsUI. Pilih bebas, lalu validasi sendiri.
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      final path = picked?.files.single.path;
      if (path == null) {
        setState(() => _busy = false);
        return;
      }

      final file = File(path);
      final summary = await BackupService.inspect(file);
      if (!mounted) return;
      setState(() => _busy = false);

      final confirmed = await _confirmRestore(summary);
      if (confirmed != true || !mounted) return;

      setState(() => _busy = true);
      final result = await BackupService.restoreItems(
        file,
        existingIds: widget.items.map((e) => e.id).toSet(),
        existingFileNames: widget.items.map((e) => e.fileName).toSet(),
      );

      if (result.items.isNotEmpty) {
        await widget.onRestored(result.items);
      }

      if (!mounted) return;
      setState(() => _busy = false);
      await _showRestoreSummary(result.result);
    } on BackupException catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack(e.message);
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('Pemulihan gagal: $e');
    }
  }

  Future<bool?> _confirmRestore(BackupSummary summary) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          'Pulihkan backup?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.inkColor(isDark),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv(isDark, 'Jumlah QRIS', '${summary.itemCount}'),
            _kv(isDark, 'Gambar', '${summary.imageCount}'),
            if (summary.exportedAt != null)
              _kv(isDark, 'Dibuat', _dateFmt.format(summary.exportedAt!)),
            const SizedBox(height: 10),
            Text(
              'Item yang sudah ada tidak akan diduplikasi. Gambar lama tidak '
              'dihapus.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppTheme.mutedColor(isDark),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Batal',
              style: TextStyle(color: AppTheme.mutedColor(isDark)),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.qrisGreenDark,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Pulihkan'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRestoreSummary(RestoreResult result) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardColor(isDark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          result.hasAnything ? 'Pemulihan selesai' : 'Tidak ada item baru',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppTheme.inkColor(isDark),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _kv(isDark, 'Dipulihkan', '${result.added}'),
            _kv(isDark, 'Dilewati (sudah ada)', '${result.skipped}'),
            if (result.missingImages > 0)
              _kv(isDark, 'Gambar tidak ditemukan', '${result.missingImages}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  }

  Widget _kv(bool isDark, String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              key,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.mutedColor(isDark),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkColor(isDark),
            ),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  static String _prettySize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.qrisGreen.withOpacity(isDark ? 0.20 : 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.cloud_sync_rounded,
                  size: 18, color: AppTheme.qrisGreen),
            ),
            const SizedBox(width: 10),
            Text(
              'Backup & Pulihkan',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppTheme.inkColor(isDark),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            _card(
              isDark,
              icon: Icons.download_rounded,
              title: 'Buat file backup',
              description:
                  'Menyimpan seluruh QRIS, favorit, dan gambar ke satu file '
                  '.qristal. Simpan di Google Drive atau kirim ke diri sendiri.',
              actionLabel: 'Buat & bagikan',
              pro: true,
              onPressed: _busy ? null : _createBackup,
            ),
            const SizedBox(height: 12),
            _card(
              isDark,
              icon: Icons.upload_rounded,
              title: 'Pulihkan dari file',
              description:
                  'Mengembalikan QRIS dari file .qristal. Item yang sudah ada '
                  'tidak diduplikasi — aman dijalankan berulang.',
              actionLabel: 'Pilih file backup',
              pro: false,
              onPressed: _busy ? null : _restore,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppTheme.subtleBg(isDark),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor(isDark)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 15, color: AppTheme.mutedColor(isDark)),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Backup dibuat dan dibaca sepenuhnya di perangkat Anda. '
                      'Tidak ada data yang diunggah ke server Qristal. File '
                      'hanya keluar bila Anda sendiri membagikannya.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: AppTheme.mutedColor(isDark),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card(
    bool isDark, {
    required IconData icon,
    required String title,
    required String description,
    required String actionLabel,
    required bool pro,
    required VoidCallback? onPressed,
  }) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderColor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.qrisGreen.withOpacity(isDark ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: AppTheme.qrisGreen),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: AppTheme.inkColor(isDark),
                  ),
                ),
              ),
              if (pro)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.qrAmber.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'PRO',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: isDark
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF8A5A00),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            description,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: AppTheme.mutedColor(isDark),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.inkColor(isDark),
                side: BorderSide(color: AppTheme.borderColor(isDark)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
