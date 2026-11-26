import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/scanned_item.dart';
import '../services/trash_service.dart';
import '../theme/app_theme.dart';

/// Tempat sampah sementara: item yang baru dihapus bisa dipulihkan.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  /// Mengembalikan item yang dipulihkan saat halaman ditutup.
  static Future<List<ScannedItem>> open(BuildContext context) async {
    final result = await Navigator.of(context).push<List<ScannedItem>>(
      MaterialPageRoute(builder: (_) => const TrashScreen()),
    );
    return result ?? const [];
  }

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  static final NumberFormat _money = NumberFormat('#,##0', 'id_ID');

  List<TrashEntry> _entries = const [];
  Directory? _trashDir;
  bool _loading = true;

  /// Item yang sudah dipulihkan selama halaman ini terbuka — dikirim balik
  /// ke Beranda saat halaman ditutup.
  final List<ScannedItem> _restoredItems = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await TrashService.purgeExpired();
    final dir = await TrashService.dir();
    final entries = await TrashService.list();
    if (!mounted) return;
    setState(() {
      _trashDir = dir;
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _restoreAll() async {
    if (_entries.isEmpty) return;
    final restored = await TrashService.restore(_entries);
    if (!mounted) return;
    _restoredItems.addAll(restored);
    setState(() {
      _entries = _entries
          .where((e) => !restored.any((i) => i.id == e.item.id))
          .toList();
    });
    Navigator.of(context).pop(_restoredItems);
  }

  Future<void> _restoreOne(TrashEntry entry) async {
    final restored = await TrashService.restore([entry]);
    if (!mounted) return;
    setState(() => _entries =
        _entries.where((e) => e.id != entry.id).toList());
    if (restored.isNotEmpty) {
      _restoredItems.addAll(restored);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${entry.merchantName} dipulihkan — kembali ke Beranda saat '
            'halaman ini ditutup.',
          ),
        ),
      );
    }
  }

  Future<void> _deleteOne(TrashEntry entry) async {
    await TrashService.deletePermanently(entry);
    if (!mounted) return;
    setState(() => _entries =
        _entries.where((e) => e.id != entry.id).toList());
  }

  Future<void> _emptyAll() async {
    if (_entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: AppTheme.cardColor(isDark),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            'Kosongkan tempat sampah?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppTheme.inkColor(isDark),
            ),
          ),
          content: Text(
            '${_entries.length} item akan dihapus permanen dan tidak bisa '
            'dipulihkan lagi.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppTheme.mutedColor(isDark),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('Batal',
                  style: TextStyle(color: AppTheme.mutedColor(isDark))),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.dangerRed,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Hapus permanen'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    await TrashService.empty();
    if (!mounted) return;
    setState(() => _entries = const []);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_restoredItems);
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          titleSpacing: 8,
          leading: IconButton(
            tooltip: 'Kembali',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(_restoredItems),
          ),
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.qrisGreen.withOpacity(isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    size: 18, color: AppTheme.qrisGreen),
              ),
              const SizedBox(width: 10),
              Text(
                'Tempat Sampah',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppTheme.inkColor(isDark),
                ),
              ),
            ],
          ),
          actions: [
            if (_entries.isNotEmpty)
              TextButton(
                onPressed: _emptyAll,
                child: const Text(
                  'Kosongkan',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        body: _loading
            ? const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              )
            : _entries.isEmpty
                ? _buildEmpty(isDark)
                : SafeArea(
                    top: false,
                    child: ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.qrAmber.withOpacity(isDark ? 0.12 : 0.10),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                                color: AppTheme.qrAmber.withOpacity(0.35)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.schedule_rounded,
                                  size: 15, color: AppTheme.qrAmber),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  '${_entries.length} item · otomatis dibersihkan '
                                  'setelah 24 jam.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.inkColor(isDark),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _restoreAll,
                            icon: const Icon(Icons.restore_rounded, size: 18),
                            label: Text(
                              'Pulihkan semua (${_entries.length})',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.inkColor(isDark),
                              side: BorderSide(color: AppTheme.borderColor(isDark)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(11)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ..._entries.map((e) => _row(isDark, e)),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _row(bool isDark, TrashEntry entry) {
    final imagePath =
        _trashDir == null ? '' : '${_trashDir!.path}/${entry.trashFileName}';
    final file = File(imagePath);
    final exists = imagePath.isNotEmpty && file.existsSync();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor(isDark)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 42,
              height: 42,
              color: AppTheme.subtleBg(isDark),
              child: exists
                  ? Image.file(file,
                      fit: BoxFit.cover,
                      cacheWidth: 120,
                      errorBuilder: (_, __, ___) => Icon(
                          Icons.broken_image_outlined,
                          size: 18,
                          color: AppTheme.mutedColor(isDark)))
                  : Icon(Icons.image_not_supported_outlined,
                      size: 18, color: AppTheme.mutedColor(isDark)),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.merchantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkColor(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_age(entry.age)} lalu'
                  '${entry.galleryDeleted ? ' · galeri sudah terhapus' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.mutedColor(isDark),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (entry.amount > 0)
            Text(
              'Rp ${_money.format(entry.amount)}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? const Color(0xFF34D399)
                    : AppTheme.qrisGreenDark,
              ),
            ),
          IconButton(
            tooltip: 'Pulihkan',
            onPressed: () => _restoreOne(entry),
            icon: const Icon(Icons.restore_rounded, size: 18),
            color: AppTheme.qrisGreenDark,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            tooltip: 'Hapus permanen',
            onPressed: () => _deleteOne(entry),
            icon: const Icon(Icons.close_rounded, size: 17),
            color: AppTheme.mutedColor(isDark),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  static String _age(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} menit';
    if (d.inHours < 24) return '${d.inHours} jam';
    return '${d.inDays} hari';
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppTheme.qrisGreen.withOpacity(isDark ? 0.16 : 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  size: 34, color: AppTheme.qrisGreen),
            ),
            const SizedBox(height: 16),
            Text(
              'Tempat sampah kosong',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkColor(isDark),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Item yang Anda hapus akan muncul di sini selama 24 jam dan '
              'bisa dipulihkan.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppTheme.mutedColor(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
