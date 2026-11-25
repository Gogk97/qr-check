import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/scanned_item.dart';
import '../theme/app_theme.dart';
import '../widgets/scanned_item_card.dart';

enum _FavFilter { all, qris, qr }

/// Halaman khusus pengguna PRO: kumpulan QRIS & QR yang ditandai favorit.
///
/// Menerima referensi langsung ke daftar item milik [HomeScreen] sehingga
/// perubahan favorit langsung konsisten di kedua layar tanpa sinkronisasi
/// tambahan. Penyimpanan ke disk ditangani lewat [onToggleFavorite].
class FavoritesScreen extends StatefulWidget {
  final List<ScannedItem> items;
  final Future<void> Function(ScannedItem item) onToggleFavorite;

  const FavoritesScreen({
    super.key,
    required this.items,
    required this.onToggleFavorite,
  });

  static Future<void> open(
    BuildContext context, {
    required List<ScannedItem> items,
    required Future<void> Function(ScannedItem item) onToggleFavorite,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavoritesScreen(
          items: items,
          onToggleFavorite: onToggleFavorite,
        ),
      ),
    );
  }

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  _FavFilter _filter = _FavFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ScannedItem> get _favorites =>
      widget.items.where((e) => e.isFavorite).toList();

  List<ScannedItem> get _visible {
    var list = _favorites;
    switch (_filter) {
      case _FavFilter.qris:
        list = list.where((e) => e.isQRIS).toList();
        break;
      case _FavFilter.qr:
        list = list.where((e) => e.hasQR && !e.isQRIS).toList();
        break;
      case _FavFilter.all:
        break;
    }

    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((e) {
        final merchant = (e.qrisDetails?.merchantName ?? '').toLowerCase();
        final city = (e.qrisDetails?.merchantCity ?? '').toLowerCase();
        final name = e.fileName.toLowerCase();
        final raw = (e.rawContent ?? '').toLowerCase();
        return merchant.contains(q) || city.contains(q) || name.contains(q) || raw.contains(q);
      }).toList();
    }

    list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  Future<void> _removeFavorite(ScannedItem item) async {
    HapticFeedback.mediumImpact();
    await widget.onToggleFavorite(item);
    if (!mounted) return;
    setState(() {});

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Dihapus dari favorit'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Urungkan',
            onPressed: () async {
              await widget.onToggleFavorite(item);
              if (mounted) setState(() {});
            },
          ),
        ),
      );
  }

  Future<void> _confirmRemove(ScannedItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: AppTheme.cardColor(isDark),
          title: Text(
            'Hapus dari favorit?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: AppTheme.inkColor(isDark),
            ),
          ),
          content: Text(
            item.isQRIS
                ? (item.qrisDetails?.merchantName ?? 'QRIS ini')
                : 'QR code ini',
            style: TextStyle(fontSize: 13.5, color: AppTheme.mutedColor(isDark)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Batal',
                style: TextStyle(
                  color: AppTheme.mutedColor(isDark),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text(
                'Hapus',
                style: TextStyle(
                  color: AppTheme.dangerRed,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed == true) await _removeFavorite(item);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final all = _favorites;
    final visible = _visible;

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
                color: AppTheme.qrAmber.withOpacity(isDark ? 0.18 : 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.star_rounded, size: 19, color: AppTheme.qrAmber),
            ),
            const SizedBox(width: 10),
            Text(
              'Favorit',
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
          if (all.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.subtleBg(isDark),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.borderColor(isDark)),
                  ),
                  child: Text(
                    '${all.length} item',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mutedColor(isDark),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: all.isEmpty
            ? _EmptyFavorites(onExplore: () => Navigator.of(context).pop())
            : Column(
                children: [
                  _buildHeader(isDark, all),
                  if (all.length >= 4) _buildSearch(isDark),
                  _buildFilters(isDark, all),
                  Expanded(
                    child: visible.isEmpty
                        ? _NoResults(
                            hasQuery: _query.trim().isNotEmpty,
                            onReset: () {
                              setState(() {
                                _query = '';
                                _searchController.clear();
                                _filter = _FavFilter.all;
                              });
                            },
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                            physics: const BouncingScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.70,
                            ),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final item = visible[index];
                              return ScannedItemCard(
                                key: ValueKey('fav_${item.id}'),
                                item: item,
                                showSelection: false,
                                onSelectChanged: (_) {},
                                onFavoriteTap: () => _confirmRemove(item),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, List<ScannedItem> all) {
    final qrisCount = all.where((e) => e.isQRIS).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0F2A22), const Color(0xFF0B1D18)]
                : [const Color(0xFFE9F5F0), const Color(0xFFF7FAF9)],
          ),
          border: Border.all(
            color: AppTheme.qrisGreen.withOpacity(isDark ? 0.30 : 0.18),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.qrisGreen.withOpacity(isDark ? 0.22 : 0.14),
              ),
              child: const Icon(Icons.star_rounded, color: AppTheme.qrisGreen, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Koleksi QR pilihan Anda',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: AppTheme.inkColor(isDark),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$qrisCount QRIS · ${all.length - qrisCount} QR code tersimpan',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.mutedColor(isDark),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.qrAmber.withOpacity(0.16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppTheme.qrAmber.withOpacity(0.42)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.workspace_premium_rounded, size: 12, color: AppTheme.qrAmber),
                  SizedBox(width: 4),
                  Text(
                    'PRO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: AppTheme.qrAmber,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        style: TextStyle(fontSize: 13.5, color: AppTheme.inkColor(isDark)),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Cari merchant, kota, atau nama file',
          hintStyle: TextStyle(fontSize: 13, color: AppTheme.mutedColor(isDark)),
          prefixIcon: Icon(Icons.search_rounded, size: 19, color: AppTheme.mutedColor(isDark)),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.close_rounded, size: 17, color: AppTheme.mutedColor(isDark)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: AppTheme.subtleBg(isDark),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.borderColor(isDark)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppTheme.borderColor(isDark)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.qrisGreen, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters(bool isDark, List<ScannedItem> all) {
    final qrisCount = all.where((e) => e.isQRIS).length;
    final qrCount = all.where((e) => e.hasQR && !e.isQRIS).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          _FilterChip(
            label: 'Semua',
            count: all.length,
            active: _filter == _FavFilter.all,
            onTap: () => setState(() => _filter = _FavFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'QRIS',
            count: qrisCount,
            active: _filter == _FavFilter.qris,
            onTap: () => setState(() => _filter = _FavFilter.qris),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'QR Code',
            count: qrCount,
            active: _filter == _FavFilter.qr,
            onTap: () => setState(() => _filter = _FavFilter.qr),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.qrisGreen.withOpacity(isDark ? 0.22 : 0.12)
              : AppTheme.subtleBg(isDark),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? AppTheme.qrisGreen.withOpacity(0.55)
                : AppTheme.borderColor(isDark),
            width: active ? 1.3 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                color: active
                    ? (isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark)
                    : AppTheme.mutedColor(isDark),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: active
                    ? (isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark)
                    : AppTheme.mutedColor(isDark),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFavorites extends StatelessWidget {
  final VoidCallback onExplore;

  const _EmptyFavorites({required this.onExplore});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.qrAmber.withOpacity(isDark ? 0.13 : 0.10),
                border: Border.all(color: AppTheme.qrAmber.withOpacity(0.28)),
              ),
              child: const Icon(Icons.star_outline_rounded, size: 44, color: AppTheme.qrAmber),
            ),
            const SizedBox(height: 22),
            Text(
              'Belum ada favorit',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppTheme.inkColor(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ketuk ikon bintang pada kartu QRIS atau QR code di Beranda untuk menyimpannya di sini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppTheme.mutedColor(isDark),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onExplore,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text(
                'Jelajahi Beranda',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.qrisGreenDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.subtleBg(isDark),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.borderColor(isDark)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.workspace_premium_rounded, size: 15, color: AppTheme.qrAmber),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'Favorit adalah fitur khusus PRO',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mutedColor(isDark),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  final bool hasQuery;
  final VoidCallback onReset;

  const _NoResults({required this.hasQuery, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 40, color: AppTheme.mutedColor(isDark)),
          const SizedBox(height: 12),
          Text(
            hasQuery ? 'Tidak ada yang cocok' : 'Belum ada item di filter ini',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.inkColor(isDark),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onReset,
            child: const Text(
              'Reset filter',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }
}
