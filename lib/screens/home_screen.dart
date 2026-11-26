import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scanned_item.dart';
import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/duplicate_service.dart';
import '../services/image_scanner_service.dart';
import '../services/image_storage_service.dart';
import '../services/in_app_update_service.dart';
import '../services/monetization_service.dart';
import '../services/notification_service.dart';
import '../services/qris_audit_service.dart';
import '../services/quota_service.dart';
import '../services/share_intent_service.dart';
import '../services/trash_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ad_banner.dart';
import '../widgets/app_logo.dart';
import '../widgets/scanned_item_card.dart';
import '../widgets/stats_card.dart';
import 'audit_screen.dart';
import 'backup_screen.dart';
import 'favorites_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'report_screen.dart';
import 'trash_screen.dart';
import '../utils/app_log.dart';

enum FilterMode {
  qrisOnly,
  allQr,
  regularQrOnly,
  all,
}

/// Urutan daftar di Beranda.
enum SortMode { newest, oldest, amountHigh, amountLow, nameAz }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final ImageScannerService _scannerService = ImageScannerService();

  final List<ScannedItem> _items = [];
  bool _isBatchProcessing = false;
  StreamSubscription<List<File>>? _shareSub;
  bool _isCancelRequested = false;
  int _processedCount = 0;
  int _totalToProcess = 0;
  int _alreadyScannedCount = 0;
  int _totalGalleryCount = 0;
  double _scanSpeed = 0.0;
  final Stopwatch _scanStopwatch = Stopwatch();

  FilterMode _filterMode =
      FilterMode.qrisOnly; // Default: Hanya QRIS sesuai permintaan user
  SortMode _sortMode = SortMode.newest;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool get shouldShowDeleteToolbar => _items.isNotEmpty;

  String _selectedAcquirerFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadItemsFromStorage();
    _syncUserToCloudOnStartup();
    _initShareIntent();
    // Bersihkan tempat sampah kedaluwarsa & sinkronkan kuota offline.
    TrashService.purgeExpired();
    QuotaService.syncPending();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await OnboardingScreen.showIfNeeded(context);
      if (!mounted) return;
      await MonetizationService.maybeCelebratePro(context);
      if (!mounted) return;
      // Pembaruan aplikasi lewat Play (flexible by default).
      InAppUpdateService.attachContext(context);
      await InAppUpdateService.checkAndPrompt(context);
    });
  }

  /// Terima gambar dari share sheet (WhatsApp, Telegram, Galeri, Files).
  void _initShareIntent() {
    if (!ShareIntentService.isSupported) return;
    ShareIntentService.init();
    _shareSub = ShareIntentService.stream.listen(_handleSharedImages);
    // Cold start: aplikasi dibuka langsung dari share sheet.
    ShareIntentService.drainPending().then((files) {
      if (files.isNotEmpty) _handleSharedImages(files);
    });
  }

  /// Pindai gambar yang dibagikan dari aplikasi lain.
  Future<void> _handleSharedImages(List<File> files) async {
    if (files.isEmpty || _isBatchProcessing || !mounted) return;

    setState(() => _isBatchProcessing = true);
    var added = 0;
    for (final file in files) {
      try {
        final item = await _processScanTarget(
          file: file,
          originalName: file.uri.pathSegments.last,
          assetId: null,
          fileSize: await file.length(),
          photoDate: await file.lastModified(),
        );
        if (item != null) {
          _items.insert(0, item);
          added++;
        }
      } catch (e) {
        AppLog.d('⚠️ Gagal memproses gambar share: $e');
      }
    }

    if (added > 0) await _saveItemsToStorage();
    if (!mounted) return;
    setState(() => _isBatchProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          added > 0
              ? '📥 $added gambar dari aplikasi lain ditambahkan'
              : 'Tidak ada QR ditemukan pada gambar yang dibagikan.',
        ),
      ),
    );
  }

  Future<void> _syncUserToCloudOnStartup() async {
    try {
      final user = await AuthService.getCurrentUser();
      if (user != null) {
        await QuotaService.getRemainingQuota();
        await MonetizationService.isProUser();
        AuthService.syncDeviceInfoToServer().ignore();
      }
    } catch (e) {
      AppLog.d('Profile sync on startup skipped: $e');
    }
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Map<String, int> get acquirerCounts {
    final Map<String, int> counts = {};
    for (final item in _items) {
      if (item.isQRIS && item.qrisDetails != null) {
        final acq = item.qrisDetails!.displayAcquirer;
        counts[acq] = (counts[acq] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<void> _loadItemsFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? rawData = prefs.getString('saved_scanned_items_v1');
      if (rawData != null && rawData.isNotEmpty) {
        final List list = jsonDecode(rawData);
        final loaded = list
            .map((json) => ScannedItem.fromJson(json))
            // Buang entri lama yang bukan QR: mulai sekarang hanya QR/QRIS disimpan.
            .where((item) => item.hasQR || item.isQRIS)
            .where((item) =>
                (item.assetId != null && item.assetId!.isNotEmpty) ||
                item.file.existsSync())
            .toList();
        if (mounted && loaded.isNotEmpty) {
          setState(() {
            _items.clear();
            _items.addAll(loaded);
          });
          // Bersihkan item kedaluwarsa + file yatim saat aplikasi dibuka.
          await _applyRetention(notify: true);
          await ImageStorageService.purgeOrphanFiles(
            _items.map((e) => e.file.path).toSet(),
          );
          // Isi tanggal foto untuk item lama yang belum punya (background).
          _backfillPhotoDates();
        }
      }
    } catch (e) {
      AppLog.d('Error loading items from storage: $e');
    }
  }

  Future<void> _saveItemsToStorage() async {
    try {
      // Terapkan retensi lebih dulu agar item kedaluwarsa tidak ikut tersimpan.
      await _applyRetention(notify: false);
      final prefs = await SharedPreferences.getInstance();
      final data = _items.map((item) => item.toJson()).toList();
      await prefs.setString('saved_scanned_items_v1', jsonEncode(data));
    } catch (e) {
      AppLog.d('Error saving items to storage: $e');
    }
  }

  // Counts
  int get qrisCount => _items.where((i) => i.isQRIS).length;
  int get regularQrCount => _items.where((i) => i.hasQR && !i.isQRIS).length;
  int get allQrCount => _items.where((i) => i.hasQR).length;
  int get selectedCount => _items.where((i) => i.isSelected).length;

  List<ScannedItem> get filteredItems {
    List<ScannedItem> list;
    switch (_filterMode) {
      case FilterMode.qrisOnly:
        list = _items.where((i) => i.isQRIS).toList();
        break;
      case FilterMode.allQr:
        list = _items.where((i) => i.hasQR).toList();
        break;
      case FilterMode.regularQrOnly:
        list = _items.where((i) => i.hasQR && !i.isQRIS).toList();
        break;
      case FilterMode.all:
        list = List.from(_items);
        break;
    }

    if (_selectedAcquirerFilter != 'ALL') {
      if (_selectedAcquirerFilter == 'NON_QRIS') {
        list = list.where((i) => i.hasQR && !i.isQRIS).toList();
      } else {
        list = list
            .where((i) =>
                i.isQRIS &&
                i.qrisDetails?.displayAcquirer == _selectedAcquirerFilter)
            .toList();
      }
    }

    // Pencarian: merchant, kota, nama file, atau isi payload QR.
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((i) {
        final merchant = (i.qrisDetails?.merchantName ?? '').toLowerCase();
        final city = (i.qrisDetails?.merchantCity ?? '').toLowerCase();
        final name = i.fileName.toLowerCase();
        final raw = (i.rawContent ?? '').toLowerCase();
        return merchant.contains(q) ||
            city.contains(q) ||
            name.contains(q) ||
            raw.contains(q);
      }).toList();
    }

    // Urutan
    switch (_sortMode) {
      case SortMode.newest:
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
        break;
      case SortMode.oldest:
        list.sort((a, b) => a.addedAt.compareTo(b.addedAt));
        break;
      case SortMode.amountHigh:
        list.sort((a, b) =>
            (b.qrisDetails?.amount ?? 0).compareTo(a.qrisDetails?.amount ?? 0));
        break;
      case SortMode.amountLow:
        list.sort((a, b) =>
            (a.qrisDetails?.amount ?? 0).compareTo(b.qrisDetails?.amount ?? 0));
        break;
      case SortMode.nameAz:
        list.sort((a, b) => (a.qrisDetails?.merchantName ?? a.fileName)
            .toLowerCase()
            .compareTo(
                (b.qrisDetails?.merchantName ?? b.fileName).toLowerCase()));
        break;
    }

    return list;
  }

  Future<void> _scanAllGalleryPhotos() async {
    try {
      final PermissionState ps = await PhotoManager.requestPermissionExtend(
        requestOption: const PermissionRequestOption(
          androidPermission: AndroidPermission(
            type: RequestType.image,
            mediaLocation: false,
          ),
        ),
      );

      if (!ps.hasAccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Izin galeri diperlukan untuk membaca dan memindai foto QR/QRIS.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Tampilkan indikator proses langsung aktif agar UI memberikan umpan balik instan ke pengguna!
      setState(() {
        _isBatchProcessing = true;
        _isCancelRequested = false;
        _processedCount = 0;
        _totalToProcess = 0;
      });

      final List<AssetPathEntity> paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );

      if (paths.isEmpty) {
        if (mounted) {
          setState(() => _isBatchProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Tidak ada album foto yang ditemukan di galeri HP Anda.')),
          );
        }
        return;
      }

      final AssetPathEntity album = paths.first;
      final int totalCount = await album.assetCountAsync;

      if (totalCount == 0) {
        if (mounted) {
          setState(() => _isBatchProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Galeri HP Anda belum memiliki foto.')),
          );
        }
        return;
      }

      final List<AssetEntity> entities = await album.getAssetListRange(
        start: 0,
        end: totalCount,
      );

      // ID Asset foto yang sudah pernah dipindai
      final existingAssetIds = _items
          .map((i) => i.assetId)
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();

      // Streaming filtering: eliminasi instan foto yang sudah pernah dipindai
      final List<AssetEntity> unscannedEntities = entities
          .where((entity) => !existingAssetIds.contains(entity.id))
          .toList();

      if (unscannedEntities.isEmpty) {
        if (mounted) {
          setState(() => _isBatchProcessing = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Semua foto di galeri HP Anda sudah selesai dipindai! Tidak ada foto baru.'),
              backgroundColor: AppTheme.qrisGreenDark,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final alreadyScannedCount = totalCount - unscannedEntities.length;

      setState(() {
        _alreadyScannedCount = alreadyScannedCount;
        _totalGalleryCount = totalCount;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(alreadyScannedCount > 0
                ? 'Melanjutkan pemindaian: Memproses foto ke-${alreadyScannedCount + 1} dari $totalCount...'
                : 'Memulai analisis AI untuk ${unscannedEntities.length} foto dari galeri...'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      await _processEntities(unscannedEntities);
    } catch (e) {
      if (mounted) {
        setState(() => _isBatchProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menganalisis galeri: $e')),
        );
      }
    }
  }

  Future<void> _pickImagesFromGallery() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage();
      if (pickedFiles.isEmpty) return;

      await _processFiles(pickedFiles.map((x) => File(x.path)).toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka galeri: $e')),
        );
      }
    }
  }

  Future<void> _takePhotoWithCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null) return;

      await _processFiles([File(photo.path)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membuka kamera: $e')),
        );
      }
    }
  }

  /// Menyalin foto ke storage aplikasi dalam versi **teroptimasi**
  /// (maks. 1280 px, JPEG q88). QR sudah diparse menjadi teks, jadi foto penuh
  /// tidak perlu diduplikasi — hemat 70–85% ruang penyimpanan.
  Future<File> _saveFileToPermanentStorage(File sourceFile) async {
    return ImageStorageService.saveOptimized(sourceFile);
  }

  /// Terapkan kebijakan retensi penyimpanan (30 hari / maks. 300 item).
  /// File dari item yang dibuang ikut dihapus agar ruang benar-benar kembali.
  Future<void> _applyRetention({bool notify = true}) async {
    if (_items.isEmpty) return;
    try {
      final result = await ImageStorageService.applyRetention(_items);
      if (!result.didRemove) return;

      if (mounted) {
        setState(() {
          _items
            ..clear()
            ..addAll(result.items);
        });
        if (notify) {
          final mb = (result.bytesFreed / (1024 * 1024)).toStringAsFixed(1);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '🧹 ${result.removed} item lama dibersihkan otomatis (hemat $mb MB).',
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        _items
          ..clear()
          ..addAll(result.items);
      }
    } catch (e) {
      AppLog.d('⚠️ Retensi penyimpanan gagal: $e');
    }
  }

  // ------------------------------------------------------------------ Audit

  /// Jumlah QRIS yang perlu dicek (skor audit di bawah ambang aman).
  int get _needsReviewCount => QrisAuditService.countNeedsReview(_items);

  Future<void> _openAudit() async {
    await AuditScreen.open(context, _items);
    if (mounted) setState(() {});
  }

  Future<void> _openTrash() async {
    final restored = await TrashScreen.open(context);
    if (restored.isEmpty || !mounted) return;
    setState(() => _items.insertAll(0, restored));
    await _saveItemsToStorage();
  }

  // --------------------------------------------------------- Backup & pulih

  Future<void> _openBackup() async {
    await BackupScreen.open(
      context,
      items: _items,
      onRestored: (restored) async {
        _items.insertAll(0, restored);
        await _saveItemsToStorage();
        if (mounted) setState(() {});
      },
    );
  }

  // --------------------------------------------------------------- Duplikat

  /// Jumlah foto yang berlebih karena QRIS difoto lebih dari sekali.
  int get _duplicateExtraCount =>
      DuplicateService.totalExtras(DuplicateService.groups(_items));

  /// Tawarkan pembersihan foto duplikat (simpan yang terbaru).
  Future<void> _openDuplicateCleaner() async {
    final groups = DuplicateService.groups(_items);
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Tidak ada foto duplikat — semua QRIS unik.'),
        ),
      );
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DuplicateCleanerSheet(groups: groups),
    );
    if (confirmed != true || !mounted) return;

    final extras = DuplicateService.extraPhotos(groups);
    final trashed = await TrashService.moveAll(extras);
    var removed = 0;
    for (final item in extras) {
      _items.removeWhere((e) => e.id == item.id);
      removed++;
    }

    await _saveItemsToStorage();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        content: Text(
          '🧹 $removed foto duplikat dihapus · ${groups.length} QRIS dipertahankan.',
        ),
        action: trashed.isEmpty
            ? null
            : SnackBarAction(
                label: 'Urungkan',
                onPressed: () => _undoTrash(trashed),
              ),
      ),
    );
  }

  // ------------------------------------------------------------------ Favorit

  /// Lengkapi `photoDate` item lama dari metadata galeri (sekali jalan).
  ///
  /// Item yang dipindai sebelum fitur tanggal-foto ada hanya punya waktu pindai.
  /// Dengan `assetId` kita bisa mengambil tanggal asli dari MediaStore.
  Future<void> _backfillPhotoDates() async {
    final targets = _items
        .where((e) => e.photoDate == null && (e.assetId ?? '').isNotEmpty)
        .toList();
    if (targets.isEmpty) return;

    var updated = 0;
    for (final item in targets) {
      try {
        final asset = await AssetEntity.fromId(item.assetId!);
        final created = asset?.createDateTime;
        if (created != null) {
          item.photoDate = created;
          updated++;
        }
      } catch (_) {
        // Asset mungkin sudah dihapus dari galeri — biarkan fallback ke addedAt.
      }
    }

    if (updated > 0) {
      AppLog.d('📅 Backfill tanggal foto: $updated item');
      await _saveItemsToStorage();
      if (mounted) setState(() {});
    }
  }

  int get _favoriteCount => _items.where((e) => e.isFavorite).length;

  /// Tandai / lepas favorit. Khusus PRO; pengguna gratis diarahkan ke upsell.
  Future<void> _toggleFavorite(ScannedItem item) async {
    final isPro = await MonetizationService.isProUser();
    if (!isPro) {
      if (mounted) await _showFavoritesProSheet();
      return;
    }

    item.isFavorite = !item.isFavorite;
    HapticFeedback.selectionClick();
    if (mounted) setState(() {});
    await _saveItemsToStorage();
  }

  Future<void> _openFavorites() async {
    final isPro = await MonetizationService.isProUser();
    if (!isPro) {
      if (mounted) await _showFavoritesProSheet();
      return;
    }
    if (!mounted) return;

    await FavoritesScreen.open(
      context,
      items: _items,
      onToggleFavorite: _toggleFavorite,
    );
    if (mounted) setState(() {});
  }

  /// Upsell khusus fitur Favorit.
  Future<void> _showFavoritesProSheet() => _showProSheet(
        title: 'Favorit khusus PRO',
        subtitle: 'Simpan QRIS & QR penting dalam satu halaman',
        features: const [
          (Icons.star_rounded, 'Tandai QRIS & QR favorit'),
          (
            Icons.folder_special_rounded,
            'Halaman Favorit terpisah + pencarian'
          ),
          (Icons.bolt_rounded, 'Hapus massal tanpa batas & bebas iklan'),
        ],
      );

  /// Upsell generik untuk fitur PRO (dipakai Favorit, Laporan, Rename).
  Future<void> _showProSheet({
    required String title,
    required String subtitle,
    required List<(IconData, String)> features,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bought = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border:
                Border(top: BorderSide(color: AppTheme.borderColor(isDark))),
          ),
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 18,
            bottom: 22 + MediaQuery.of(ctx).viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: AppTheme.borderColor(isDark),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppTheme.qrAmber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.workspace_premium_rounded,
                        color: AppTheme.qrAmber, size: 24),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                            color: AppTheme.inkColor(isDark),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.mutedColor(isDark)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    icon: Icon(Icons.close_rounded,
                        size: 19, color: AppTheme.mutedColor(isDark)),
                    tooltip: 'Tutup',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.subtleBg(isDark),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.borderColor(isDark)),
                ),
                child: Column(
                  children: [
                    for (final f in features) _buildProFeatureRow(f.$1, f.$2),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.qrisGreenDark,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  'Upgrade ke PRO',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  'Nanti saja',
                  style: TextStyle(
                      color: AppTheme.mutedColor(isDark),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (bought == true && mounted) {
      final purchased = await MonetizationService.openProPurchase(context);
      if (purchased && mounted) setState(() {});
    }
  }

  /// Buka halaman Laporan QRIS (PRO).
  Future<void> _openReport() async {
    final isPro = await MonetizationService.isProUser();
    if (!isPro) {
      if (mounted) {
        await _showProSheet(
          title: 'Laporan khusus PRO',
          subtitle: 'Grafik nominal, filter tanggal & harga, ekspor CSV/Excel',
          features: const [
            (Icons.insights_rounded, 'Grafik nominal per hari & minggu'),
            (Icons.filter_alt_rounded, 'Filter tanggal dan rentang harga'),
            (Icons.download_rounded, 'Ekspor CSV & Excel siap pakai'),
          ],
        );
      }
      return;
    }
    if (!mounted) return;
    await ReportScreen.open(context, items: _items);
  }

  /// Rapikan nama file QRIS menjadi mudah dibaca (PRO).
  Future<void> _autoRenameAll() async {
    final isPro = await MonetizationService.isProUser();
    if (!isPro) {
      if (mounted) {
        await _showProSheet(
          title: 'Rapikan nama file (PRO)',
          subtitle: 'Ubah nama file menjadi mudah dicari',
          features: const [
            (
              Icons.drive_file_rename_outline_rounded,
              'Nama dari merchant + nominal + tanggal'
            ),
            (Icons.search_rounded, 'Mudah ditemukan di galeri & file manager'),
            (Icons.bolt_rounded, 'Sekali tekan untuk semua QRIS'),
          ],
        );
      }
      return;
    }

    final targets = _items.where((e) => e.isQRIS).toList();
    if (targets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Belum ada QRIS untuk dirapikan.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    var renamed = 0;
    for (final item in targets) {
      final before = item.file.path;
      final after = await ImageStorageService.autoRename(item);
      if (after.path != before) {
        item.file = after;
        item.fileName = after.uri.pathSegments.last;
        renamed++;
      }
    }

    if (renamed > 0) {
      await _saveItemsToStorage();
      if (mounted) setState(() {});
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            renamed > 0
                ? '🏷️ $renamed file dirapikan berdasarkan isi QRIS.'
                : 'Semua nama file sudah rapi.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildProFeatureRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 17, color: AppTheme.qrisGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style:
                  const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper pemindaian satu gambar & penyimpanan permanen jika terdeteksi QR/QRIS
  /// Memindai satu file. Mengembalikan `null` bila foto tidak berisi QR/QRIS,
  /// sehingga daftar hanya berisi QR yang relevan (foto biasa tidak disimpan).
  Future<ScannedItem?> _processScanTarget({
    required File file,
    required String originalName,
    required String? assetId,
    required int fileSize,
    DateTime? photoDate,
  }) async {
    final id =
        'scan_${DateTime.now().microsecondsSinceEpoch}_${file.path.hashCode}';
    var result = await _scannerService.scanImage(file, id: id);

    if (result.hasQR || result.isQRIS) {
      final permanentFile = await _saveFileToPermanentStorage(file);
      return ScannedItem(
        id: result.id,
        file: permanentFile,
        fileName: permanentFile.uri.pathSegments.last,
        originalFileName: originalName,
        assetId: assetId,
        fileSize: result.fileSize,
        addedAt: result.addedAt,
        photoDate: photoDate,
        isProcessing: false,
        hasQR: result.hasQR,
        isQRIS: result.isQRIS,
        rawContent: result.rawContent,
        qrType: result.qrType,
        qrisDetails: result.qrisDetails,
        errorMessage: result.errorMessage,
        isSelected: result.isSelected,
      );
    }

    return null;
  }

  /// Pemrosesan concurrent streaming untuk entitas galeri (3 concurrent workers)
  Future<void> _processEntities(List<AssetEntity> entities) async {
    setState(() {
      _isBatchProcessing = true;
      _isCancelRequested = false;
      _processedCount = 0;
      _totalToProcess = entities.length;
      _scanSpeed = 0.0;
    });

    _scanStopwatch.reset();
    _scanStopwatch.start();

    final notificationService = NotificationService();
    await notificationService.init();

    int cursor = 0;
    const int concurrency = 3;
    DateTime lastSaveTime = DateTime.now();
    int itemsSinceLastSave = 0;
    DateTime lastNotificationTime = DateTime.now();
    DateTime lastUiUpdateTime = DateTime.now();

    Future<void> worker() async {
      while (cursor < entities.length && !_isCancelRequested) {
        final index = cursor++;
        final entity = entities[index];

        try {
          final file = await entity.file;
          if (file != null) {
            final originalName = entity.title ?? file.uri.pathSegments.last;
            final fileSize = await file.length();

            final item = await _processScanTarget(
              file: file,
              originalName: originalName,
              assetId: entity.id,
              fileSize: fileSize,
              photoDate: entity.createDateTime,
            );

            if (item != null) _items.insert(0, item);
          }
        } catch (e) {
          AppLog.d('Error scanning entity ${entity.id}: $e');
        }

        _processedCount++;
        itemsSinceLastSave++;

        final elapsedSec = _scanStopwatch.elapsedMilliseconds / 1000.0;
        if (elapsedSec > 0.4) {
          _scanSpeed = _processedCount / elapsedSec;
        }

        final now = DateTime.now();
        if (now.difference(lastUiUpdateTime).inMilliseconds >= 150 ||
            _processedCount >= entities.length) {
          lastUiUpdateTime = now;
          if (mounted) setState(() {});
        }

        if (itemsSinceLastSave >= 12 ||
            now.difference(lastSaveTime).inMilliseconds >= 2500) {
          lastSaveTime = now;
          itemsSinceLastSave = 0;
          await _saveItemsToStorage();
        }

        if (now.difference(lastNotificationTime).inMilliseconds >= 600 ||
            _processedCount >= entities.length) {
          lastNotificationTime = now;
          notificationService.showScanProgress(
            processedCount: _alreadyScannedCount + _processedCount,
            totalToProcess:
                _totalGalleryCount > 0 ? _totalGalleryCount : _totalToProcess,
            qrisFoundCount: qrisCount,
          );
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));

    _scanStopwatch.stop();
    await _saveItemsToStorage();

    final wasCancelled = _isCancelRequested;
    if (!wasCancelled) {
      await notificationService.showScanComplete(
        totalProcessed: _totalToProcess,
        qrisFoundCount: qrisCount,
      );
    }

    if (mounted) {
      setState(() {
        _isBatchProcessing = false;
        _isCancelRequested = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: wasCancelled
              ? Colors.orange.shade800
              : (qrisCount > 0 ? AppTheme.qrisGreenDark : null),
          content: Text(
            wasCancelled
                ? 'Pemindaian dihentikan ($_processedCount/$_totalToProcess foto selesai). Data yang selesai tetap tersimpan!'
                : 'Selesai memindai $_totalToProcess foto (${_scanSpeed > 0 ? '${_scanSpeed.toStringAsFixed(1)} foto/dtk' : ''}). Ditemukan $qrisCount QRIS!',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Pemrosesan concurrent untuk list file (kamera & picker manual)
  Future<void> _processFiles(List<File> files,
      {Map<File, String>? fileAssetMap}) async {
    setState(() {
      _isBatchProcessing = true;
      _isCancelRequested = false;
      _processedCount = 0;
      _totalToProcess = files.length;
      _scanSpeed = 0.0;
    });

    _scanStopwatch.reset();
    _scanStopwatch.start();

    final notificationService = NotificationService();
    await notificationService.init();

    int cursor = 0;
    const int concurrency = 3;
    DateTime lastSaveTime = DateTime.now();
    int itemsSinceLastSave = 0;
    DateTime lastNotificationTime = DateTime.now();
    DateTime lastUiUpdateTime = DateTime.now();

    Future<void> worker() async {
      while (cursor < files.length && !_isCancelRequested) {
        final index = cursor++;
        final file = files[index];

        try {
          final originalName = file.uri.pathSegments.last;
          final fileSize = await file.length();
          final assetId = fileAssetMap?[file];

          final item = await _processScanTarget(
            file: file,
            originalName: originalName,
            assetId: assetId,
            fileSize: fileSize,
            photoDate: await file.lastModified(),
          );

          if (item != null) _items.insert(0, item);
        } catch (e) {
          AppLog.d('Error scanning file ${file.path}: $e');
        }

        _processedCount++;
        itemsSinceLastSave++;

        final elapsedSec = _scanStopwatch.elapsedMilliseconds / 1000.0;
        if (elapsedSec > 0.4) {
          _scanSpeed = _processedCount / elapsedSec;
        }

        final now = DateTime.now();
        if (now.difference(lastUiUpdateTime).inMilliseconds >= 150 ||
            _processedCount >= files.length) {
          lastUiUpdateTime = now;
          if (mounted) setState(() {});
        }

        if (itemsSinceLastSave >= 10 ||
            now.difference(lastSaveTime).inMilliseconds >= 2500) {
          lastSaveTime = now;
          itemsSinceLastSave = 0;
          await _saveItemsToStorage();
        }

        if (now.difference(lastNotificationTime).inMilliseconds >= 600 ||
            _processedCount >= files.length) {
          lastNotificationTime = now;
          notificationService.showScanProgress(
            processedCount: _processedCount,
            totalToProcess: _totalToProcess,
            qrisFoundCount: qrisCount,
          );
        }
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));

    _scanStopwatch.stop();
    await _saveItemsToStorage();

    final wasCancelled = _isCancelRequested;
    if (!wasCancelled) {
      await notificationService.showScanComplete(
        totalProcessed: _totalToProcess,
        qrisFoundCount: qrisCount,
      );
    }

    if (mounted) {
      setState(() {
        _isBatchProcessing = false;
        _isCancelRequested = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: wasCancelled
              ? Colors.orange.shade800
              : (qrisCount > 0 ? AppTheme.qrisGreenDark : null),
          content: Text(
            wasCancelled
                ? 'Pemindaian dihentikan ($_processedCount/$_totalToProcess foto selesai). Data yang selesai tetap tersimpan!'
                : 'Selesai memindai $_totalToProcess foto (${_scanSpeed > 0 ? '${_scanSpeed.toStringAsFixed(1)} foto/dtk' : ''}). Ditemukan $qrisCount QRIS!',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAccountModal() async {
    final user = await AuthService.getCurrentUser();
    final isPro = await MonetizationService.isProUser();
    final remainingQuota = await QuotaService.getRemainingQuota();
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      // Lima tombol aksi: layar kecil bisa overflow, jadi dibuat scrollable.
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(
                top: BorderSide(color: AppTheme.borderColor(isDark), width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.borderColor(isDark),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.subtleBg(isDark),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: AppTheme.borderColor(isDark)),
                        ),
                        child: Icon(
                          user?.isGuest == false
                              ? Icons.verified_user_outlined
                              : Icons.person_outline_rounded,
                          color: user?.isGuest == false
                              ? AppTheme.primary
                              : AppTheme.mutedColor(isDark),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user?.name ?? 'Pengguna',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -0.3,
                                      color: AppTheme.inkColor(isDark),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: user?.isGuest == false
                                        ? AppTheme.primary.withOpacity(0.12)
                                        : AppTheme.subtleBg(isDark),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: user?.isGuest == false
                                          ? AppTheme.primary.withOpacity(0.35)
                                          : AppTheme.borderColor(isDark),
                                    ),
                                  ),
                                  child: Text(
                                    user?.isGuest == false ? 'Google' : 'Tamu',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: user?.isGuest == false
                                          ? AppTheme.primary
                                          : AppTheme.mutedColor(isDark),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.email ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.mutedColor(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Quota Card in Profile
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.subtleBg(isDark),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isPro
                            ? AppTheme.qrAmber.withOpacity(0.45)
                            : AppTheme.borderColor(isDark),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isPro
                                  ? Icons.star_rounded
                                  : Icons.confirmation_number_outlined,
                              color:
                                  isPro ? AppTheme.qrAmber : AppTheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Sisa Kuota Hapus',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.mutedColor(isDark)),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  isPro
                                      ? 'UNLIMITED (PRO)'
                                      : '$remainingQuota Foto',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isPro
                                        ? AppTheme.qrAmber
                                        : AppTheme.inkColor(isDark),
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (!isPro)
                          TextButton.icon(
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              await QuotaService.watchRewardedAdForQuota(
                                  context);
                              setState(() {});
                            },
                            icon: const Icon(Icons.ondemand_video_rounded,
                                size: 15, color: AppTheme.primary),
                            label: const Text(
                              '+1 Kuota',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!isPro) ...[
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await MonetizationService.openProPurchase(context);
                      },
                      icon: const Icon(Icons.workspace_premium_rounded,
                          color: Colors.white, size: 19),
                      label: const Text(
                        'Beli PRO (Sekali Bayar)',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.qrAmber,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _openTrash();
                    },
                    icon: Icon(Icons.delete_outline_rounded,
                        color: AppTheme.inkColor(isDark), size: 18),
                    label: Text(
                      'Tempat Sampah',
                      style: TextStyle(
                          color: AppTheme.inkColor(isDark),
                          fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.borderColor(isDark)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _openBackup();
                    },
                    icon: Icon(Icons.cloud_sync_outlined,
                        color: AppTheme.inkColor(isDark), size: 18),
                    label: Text(
                      'Backup & Pulihkan',
                      style: TextStyle(
                          color: AppTheme.inkColor(isDark),
                          fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.borderColor(isDark)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      Navigator.of(ctx).pop();
                      final msg = await InAppUpdateService.checkManually();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: Icon(Icons.system_update_alt_rounded,
                        color: AppTheme.inkColor(isDark), size: 18),
                    label: Text(
                      'Periksa Pembaruan',
                      style: TextStyle(
                          color: AppTheme.inkColor(isDark),
                          fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.borderColor(isDark)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _autoRenameAll();
                    },
                    icon: Icon(Icons.drive_file_rename_outline_rounded,
                        color: AppTheme.inkColor(isDark), size: 18),
                    label: Text(
                      'Rapikan Nama File (PRO)',
                      style: TextStyle(
                          color: AppTheme.inkColor(isDark),
                          fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppTheme.borderColor(isDark)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      Navigator.of(ctx).pop();
                      await AuthService.logout();
                      if (!mounted) return;
                      navigator.pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.logout_rounded,
                        color: AppTheme.dangerRed, size: 17),
                    label: const Text(
                      'Ganti Akun / Keluar',
                      style: TextStyle(
                          color: AppTheme.dangerRed,
                          fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AppTheme.dangerRed.withOpacity(0.35)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _toggleSelectAll() {
    final currentFiltered = filteredItems;
    final allSelected = currentFiltered.isNotEmpty &&
        currentFiltered.every((i) => i.isSelected);
    setState(() {
      for (var item in currentFiltered) {
        item.isSelected = !allSelected;
      }
    });
  }

  void _shareSelected() {
    final selected = _items.where((i) => i.isSelected).toList();
    if (selected.isEmpty) return;

    final xFiles = selected.map((i) => XFile(i.file.path)).toList();
    Share.shareXFiles(
      xFiles,
      text: 'Foto QRIS terdeteksi (${selected.length} gambar)',
    );
  }

  Future<bool> _showConfirmDeleteModal({
    required List<ScannedItem> items,
    required String title,
    String? subtitle,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final int count = items.length;
    final int totalBytes = items.fold<int>(0, (sum, i) => sum + i.fileSize);
    String formattedSize = '';
    if (totalBytes < 1024) {
      formattedSize = '$totalBytes B';
    } else if (totalBytes < 1024 * 1024) {
      formattedSize = '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      formattedSize = '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    final int qrisCount = items.where((i) => i.isQRIS).length;
    final int regQrCount = items.where((i) => i.hasQR && !i.isQRIS).length;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(
              top: BorderSide(color: AppTheme.borderColor(isDark), width: 1),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.borderColor(isDark),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.dangerRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppTheme.dangerRed.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.delete_sweep_rounded,
                          color: AppTheme.dangerRed, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: AppTheme.inkColor(isDark),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle ??
                                'File akan dihapus secara permanen dari galeri ponsel.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.mutedColor(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleBg(isDark),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: AppTheme.borderColor(isDark)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.storage_rounded,
                                size: 14, color: AppTheme.primary),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Hemat $formattedSize',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleBg(isDark),
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: AppTheme.borderColor(isDark)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_2_rounded,
                                size: 14, color: AppTheme.qrisGreen),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                qrisCount > 0
                                    ? '$qrisCount QRIS'
                                    : '$regQrCount QR',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: count > 8 ? 8 : count,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      if (idx == 7 && count > 8) {
                        return Container(
                          width: 64,
                          decoration: BoxDecoration(
                            color: AppTheme.subtleBg(isDark),
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: AppTheme.borderColor(isDark)),
                          ),
                          child: Center(
                            child: Text(
                              '+${count - 7}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        );
                      }
                      final it = items[idx];
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            Image.file(
                              it.file,
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              cacheWidth: 150,
                              errorBuilder: (_, __, ___) => Container(
                                width: 64,
                                height: 64,
                                color: AppTheme.subtleBg(isDark),
                                child: Icon(Icons.broken_image_outlined,
                                    size: 18,
                                    color: AppTheme.mutedColor(isDark)),
                              ),
                            ),
                            if (it.isQRIS)
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppTheme.qrisGreenDark,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('QRIS',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.qrAmber.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppTheme.qrAmber.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined,
                          size: 15, color: AppTheme.qrAmber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sistem Android akan meminta konfirmasi izin untuk menghapus file dari memori ponsel.',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.inkColor(isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          side: BorderSide(color: AppTheme.borderColor(isDark)),
                        ),
                        child: Text(
                          'Batal',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppTheme.inkColor(isDark)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 6,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        icon: const Icon(Icons.delete_rounded,
                            size: 17, color: Colors.white),
                        label: Text(
                          'Hapus $count Foto',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.dangerRed,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  Future<void> _deleteSelected() async {
    final selected = _items.where((i) => i.isSelected).toList();
    if (selected.isEmpty) return;

    final confirmed = await _showConfirmDeleteModal(
      items: selected,
      title: 'Hapus ${selected.length} Foto Terpilih?',
      subtitle: 'Foto akan dibersihkan permanen dari galeri ponsel.',
    );
    if (!confirmed) return;

    final isPro = await MonetizationService.isProUser();

    if (!isPro) {
      final currentQuota = await QuotaService.getRemainingQuota();
      if (currentQuota < selected.length) {
        if (!mounted) return;
        await QuotaService.showQuotaExhaustedDialog(
          context,
          needed: selected.length,
          current: currentQuota,
        );
        setState(() {});
        return;
      }

      if (selected.length <= 3) {
        if (!mounted) return;
        await MonetizationService.showInterstitialAd(context);
      } else {
        if (!mounted) return;
        final allowed = await MonetizationService.showMassDeleteDialog(
          context,
          itemCount: selected.length,
        );
        if (!allowed) return;
      }
    }

    // Potong kuota di server SEBELUM foto dihapus (server-authoritative).
    // Kalau gagal (offline / kuota habis), tidak ada foto yang dihapus.
    String? quotaRef;
    var quotaConsumed = 0;
    if (!isPro) {
      quotaRef = 'del_${DateTime.now().microsecondsSinceEpoch}';
      quotaConsumed = selected.length;
      final quotaOk =
          await QuotaService.consumeQuota(quotaConsumed, refId: quotaRef);
      if (!quotaOk) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(QuotaService.lastError ?? 'Kuota tidak cukup.'),
            backgroundColor: AppTheme.dangerRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    // Hapus foto asli dari Galeri Sistem HP (MediaStore)
    final systemAssetIds = selected
        .map((i) => i.assetId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    List<String> successfullyDeletedAssetIds = [];
    if (systemAssetIds.isNotEmpty) {
      try {
        successfullyDeletedAssetIds =
            await PhotoManager.editor.deleteWithIds(systemAssetIds);
      } catch (e) {
        AppLog.d('Error deleting from system gallery: $e');
      }
    }

    // Jika pengguna membatalkan izin pada prompt sistem Android OS
    if (systemAssetIds.isNotEmpty && successfullyDeletedAssetIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Penghapusan dibatalkan (izin sistem tidak diberikan).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      // Penghapusan tidak terjadi → kembalikan kuota yang sudah terpotong.
      if (quotaRef != null && quotaConsumed > 0) {
        await QuotaService.refundQuota(quotaRef, quotaConsumed);
      }
      return;
    }

    final deletedAssetSet = successfullyDeletedAssetIds.toSet();
    final itemsToRemove = selected.where((item) {
      if (item.assetId != null && item.assetId!.isNotEmpty) {
        return deletedAssetSet.contains(item.assetId);
      }
      return true;
    }).toList();

    // Salinan lokal dipindah ke tempat sampah (bisa dipulihkan 24 jam).
    final trashed = <TrashEntry>[];
    for (final item in itemsToRemove) {
      final entry = await TrashService.move(
        item,
        galleryDeleted: (item.assetId ?? '').isNotEmpty,
      );
      if (entry != null) trashed.add(entry);
    }

    if (mounted) {
      final remaining = await QuotaService.getRemainingQuota();
      setState(() {
        final removeIds = itemsToRemove.map((i) => i.id).toSet();
        _items.removeWhere((i) => removeIds.contains(i.id));
      });
      await _saveItemsToStorage();
      // Gating interstitial AdMob: hanya dihitung dari aksi hapus yang berhasil.
      AdService.noteUserAction();

      if (!mounted) return;
      final offlineNote = QuotaService.usedOffline
          ? ' · kuota tersinkron otomatis saat online'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            isPro
                ? '✅ ${itemsToRemove.length} foto dibersihkan!'
                : '✅ ${itemsToRemove.length} foto dibersihkan! '
                    '(Sisa kuota: $remaining)$offlineNote',
          ),
          backgroundColor: AppTheme.qrisGreenDark,
          behavior: SnackBarBehavior.floating,
          action: trashed.isEmpty
              ? null
              : SnackBarAction(
                  label: 'Urungkan',
                  textColor: Colors.white,
                  onPressed: () => _undoTrash(trashed),
                ),
        ),
      );
    }
  }

  /// Batalkan penghapusan terakhir dengan memulihkan dari tempat sampah.
  Future<void> _undoTrash(List<TrashEntry> entries) async {
    final restored = await TrashService.restore(entries);
    if (restored.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item sudah tidak bisa dipulihkan.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _items.insertAll(0, restored));
    await _saveItemsToStorage();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('↩️ ${restored.length} item dipulihkan ke daftar.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 32),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Qristal',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Laporan QRIS (fitur PRO)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _openReport,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.subtleBg(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderColor(isDark)),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  size: 19,
                  color: AppTheme.inkColor(isDark),
                ),
              ),
            ),
          ),
          // Favorit (fitur PRO)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _openFavorites,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.subtleBg(isDark),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderColor(isDark)),
                    ),
                    child: Icon(
                      _favoriteCount > 0
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      size: 20,
                      color: _favoriteCount > 0
                          ? AppTheme.qrAmber
                          : AppTheme.inkColor(isDark),
                    ),
                  ),
                  if (_favoriteCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        constraints: const BoxConstraints(minWidth: 17),
                        decoration: BoxDecoration(
                          color: AppTheme.qrAmber,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppTheme.cardColor(isDark),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          '$_favoriteCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 9.5,
                            height: 1.3,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _showAccountModal,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.subtleBg(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderColor(isDark)),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 20,
                  color: AppTheme.inkColor(isDark),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Dashboard & Stats
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: StatsCard(
                      title: 'QRIS',
                      count: qrisCount,
                      icon: Icons.verified,
                      color: AppTheme.qrisGreen,
                      isSelected: _filterMode == FilterMode.qrisOnly,
                      onTap: () {
                        setState(() {
                          if (_filterMode == FilterMode.qrisOnly) {
                            _filterMode = FilterMode.all;
                            _selectedAcquirerFilter = 'ALL';
                          } else {
                            _filterMode = FilterMode.qrisOnly;
                            if (_selectedAcquirerFilter == 'NON_QRIS') {
                              _selectedAcquirerFilter = 'ALL';
                            }
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatsCard(
                      title: 'Semua QR',
                      count: allQrCount,
                      icon: Icons.qr_code_2,
                      color: AppTheme.qrAmber,
                      isSelected: _filterMode == FilterMode.allQr,
                      onTap: () {
                        setState(() {
                          if (_filterMode == FilterMode.allQr) {
                            _filterMode = FilterMode.all;
                            _selectedAcquirerFilter = 'ALL';
                          } else {
                            _filterMode = FilterMode.allQr;
                            _selectedAcquirerFilter = 'ALL';
                          }
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Scanning progress indicator
            if (_isBatchProcessing)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.35)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _isCancelRequested
                                    ? 'Menghentikan pemindaian...'
                                    : (_totalGalleryCount > 0
                                        ? 'Memindai galeri... (${_alreadyScannedCount + _processedCount} / $_totalGalleryCount)'
                                        : 'Memindai galeri... ($_processedCount / $_totalToProcess)'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                              if (_scanSpeed > 0 && !_isCancelRequested)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '${_scanSpeed.toStringAsFixed(1)} foto/dtk • $qrisCount QRIS terdeteksi',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? const Color(0xFF34D399)
                                          : AppTheme.qrisGreenDark,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _totalGalleryCount > 0
                              ? '${(((_alreadyScannedCount + _processedCount) / (_totalGalleryCount == 0 ? 1 : _totalGalleryCount)) * 100).toInt()}%'
                              : '${((_processedCount / (_totalToProcess == 0 ? 1 : _totalToProcess)) * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Tombol Jeda / Hentikan Pemindaian
                        InkWell(
                          onTap: _isCancelRequested
                              ? null
                              : () {
                                  setState(() {
                                    _isCancelRequested = true;
                                  });
                                },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: AppTheme.dangerRed.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isCancelRequested
                                      ? Icons.hourglass_top
                                      : Icons.pause_circle_filled,
                                  size: 14,
                                  color: AppTheme.dangerRed,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isCancelRequested
                                      ? 'Menghentikan...'
                                      : 'Jeda',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.dangerRed),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: _totalGalleryCount > 0
                            ? (_alreadyScannedCount + _processedCount) /
                                _totalGalleryCount
                            : (_totalToProcess > 0
                                ? _processedCount / _totalToProcess
                                : null),
                        minHeight: 5,
                        backgroundColor: AppTheme.subtleBg(isDark),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isCancelRequested
                              ? AppTheme.qrAmber
                              : AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Filter Penyelenggara (Acquirer) Chips Bar
            if (acquirerCounts.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined,
                            size: 13, color: AppTheme.qrisGreen),
                        const SizedBox(width: 5),
                        Text(
                          _filterMode == FilterMode.allQr
                              ? 'Filter Jenis & Penyelenggara:'
                              : 'Penyelenggara / Bank QRIS:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.mutedColor(isDark),
                          ),
                        ),
                        if (_selectedAcquirerFilter != 'ALL') ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _selectedAcquirerFilter = 'ALL'),
                            child: const Text(
                              'Reset Filter',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.dangerRed),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text(
                              _filterMode == FilterMode.allQr
                                  ? 'Semua QR ($allQrCount)'
                                  : 'Semua QRIS ($qrisCount)',
                            ),
                            selected: _selectedAcquirerFilter == 'ALL',
                            onSelected: (selected) {
                              if (selected) {
                                setState(
                                    () => _selectedAcquirerFilter = 'ALL');
                              }
                            },
                            backgroundColor: AppTheme.cardColor(isDark),
                            selectedColor: AppTheme.primary.withOpacity(0.15),
                            side: BorderSide(
                              color: _selectedAcquirerFilter == 'ALL'
                                  ? AppTheme.primary
                                  : AppTheme.borderColor(isDark),
                              width:
                                  _selectedAcquirerFilter == 'ALL' ? 1.4 : 1.0,
                            ),
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: _selectedAcquirerFilter == 'ALL'
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: _selectedAcquirerFilter == 'ALL'
                                  ? (isDark
                                      ? const Color(0xFF34D399)
                                      : AppTheme.qrisGreenDark)
                                  : AppTheme.inkColor(isDark),
                            ),
                            showCheckmark: false,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          if (_filterMode == FilterMode.allQr &&
                              regularQrCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: ChoiceChip(
                                label: Text('Non-QRIS ($regularQrCount)'),
                                selected: _selectedAcquirerFilter == 'NON_QRIS',
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedAcquirerFilter =
                                        selected ? 'NON_QRIS' : 'ALL';
                                  });
                                },
                                backgroundColor: AppTheme.cardColor(isDark),
                                selectedColor:
                                    AppTheme.qrAmber.withOpacity(0.18),
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight:
                                      _selectedAcquirerFilter == 'NON_QRIS'
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                  color: _selectedAcquirerFilter == 'NON_QRIS'
                                      ? AppTheme.qrAmber
                                      : AppTheme.inkColor(isDark),
                                ),
                                side: BorderSide(
                                  color: _selectedAcquirerFilter == 'NON_QRIS'
                                      ? AppTheme.qrAmber
                                      : AppTheme.borderColor(isDark),
                                  width: _selectedAcquirerFilter == 'NON_QRIS'
                                      ? 1.4
                                      : 1.0,
                                ),
                                showCheckmark: false,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ...acquirerCounts.entries.map((entry) {
                            final acqName = entry.key;
                            final count = entry.value;
                            final isSel = _selectedAcquirerFilter == acqName;
                            return Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: ChoiceChip(
                                label: Text('$acqName ($count)'),
                                selected: isSel,
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedAcquirerFilter =
                                        selected ? acqName : 'ALL';
                                    if (selected &&
                                        _filterMode != FilterMode.qrisOnly) {
                                      _filterMode = FilterMode.qrisOnly;
                                    }
                                  });
                                },
                                backgroundColor: AppTheme.cardColor(isDark),
                                selectedColor:
                                    AppTheme.qrisGreen.withOpacity(0.15),
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight:
                                      isSel ? FontWeight.w700 : FontWeight.w500,
                                  color: isSel
                                      ? (isDark
                                          ? const Color(0xFF34D399)
                                          : AppTheme.qrisGreenDark)
                                      : AppTheme.inkColor(isDark),
                                ),
                                side: BorderSide(
                                  color: isSel
                                      ? AppTheme.qrisGreen
                                      : AppTheme.borderColor(isDark),
                                  width: isSel ? 1.4 : 1.0,
                                ),
                                showCheckmark: false,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Pencarian & urutan (gratis)
            if (_items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => setState(() => _searchQuery = v),
                        textInputAction: TextInputAction.search,
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.inkColor(isDark)),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Cari merchant, kota, atau nama file',
                          hintStyle: TextStyle(
                              fontSize: 12.5,
                              color: AppTheme.mutedColor(isDark)),
                          prefixIcon: Icon(Icons.search_rounded,
                              size: 18, color: AppTheme.mutedColor(isDark)),
                          suffixIcon: _searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(Icons.close_rounded,
                                      size: 16,
                                      color: AppTheme.mutedColor(isDark)),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                ),
                          filled: true,
                          fillColor: AppTheme.subtleBg(isDark),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(11),
                            borderSide:
                                BorderSide(color: AppTheme.borderColor(isDark)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(11),
                            borderSide:
                                BorderSide(color: AppTheme.borderColor(isDark)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(11),
                            borderSide: const BorderSide(
                                color: AppTheme.qrisGreen, width: 1.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<SortMode>(
                      tooltip: 'Urutkan',
                      initialValue: _sortMode,
                      onSelected: (v) => setState(() => _sortMode = v),
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                            value: SortMode.newest, child: Text('Terbaru')),
                        PopupMenuItem(
                            value: SortMode.oldest, child: Text('Terlama')),
                        PopupMenuItem(
                            value: SortMode.amountHigh,
                            child: Text('Nominal tertinggi')),
                        PopupMenuItem(
                            value: SortMode.amountLow,
                            child: Text('Nominal terendah')),
                        PopupMenuItem(
                            value: SortMode.nameAz, child: Text('Nama A–Z')),
                      ],
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppTheme.subtleBg(isDark),
                          borderRadius: BorderRadius.circular(11),
                          border:
                              Border.all(color: AppTheme.borderColor(isDark)),
                        ),
                        child: Icon(
                          Icons.sort_rounded,
                          size: 19,
                          color: _sortMode == SortMode.newest
                              ? AppTheme.mutedColor(isDark)
                              : AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Batch selection toolbar if filter mode is QRIS or QR
            if (shouldShowDeleteToolbar)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.cardColor(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.borderColor(isDark)),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: _toggleSelectAll,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 2, horizontal: 2),
                        child: Row(
                          children: [
                            Icon(
                              filteredItems.isNotEmpty &&
                                      filteredItems.every((i) => i.isSelected)
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              selectedCount > 0
                                  ? '$selectedCount dipilih'
                                  : 'Pilih Semua',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (selectedCount > 0) ...[
                      TextButton.icon(
                        onPressed: _shareSelected,
                        icon: const Icon(Icons.share_outlined, size: 15),
                        label: const Text('Bagikan',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      TextButton.icon(
                        onPressed: _deleteSelected,
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 15, color: AppTheme.dangerRed),
                        label: const Text(
                          'Hapus',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.dangerRed),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // Responsive Image Grid / Empty State
            Expanded(
              child: filteredItems.isEmpty
                  ? _buildEmptyState(isDark)
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        // Responsive column count based on width
                        int crossAxisCount = 2;
                        if (constraints.maxWidth > 900) {
                          crossAxisCount = 5;
                        } else if (constraints.maxWidth > 650) {
                          crossAxisCount = 4;
                        } else if (constraints.maxWidth > 480) {
                          crossAxisCount = 3;
                        }

                        return GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: 0.78,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            return ScannedItemCard(
                              key: ValueKey(item.id),
                              item: item,
                              showSelection: true,
                              onFavoriteTap: () => _toggleFavorite(item),
                              onSelectChanged: (val) {
                                setState(() {
                                  item.isSelected = val ?? false;
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      // Banner AdMob: tidak tampil untuk PRO, dan tidak memakan ruang bila gagal dimuat.
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AdBanner(),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: AppTheme.cardColor(isDark),
              border: Border(
                top: BorderSide(color: AppTheme.borderColor(isDark), width: 1),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  // Gallery Scanner Action Button
                  Expanded(
                    flex: 4,
                    child: ElevatedButton.icon(
                      onPressed:
                          _isBatchProcessing ? null : _scanAllGalleryPhotos,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _items.isNotEmpty
                              ? 'Pindai / Lanjutkan Galeri (AI)'
                              : 'Pindai Semua Galeri (AI)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.qrisGreenDark,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Popup Option: Manual Multi-select Picker or Camera
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'picker') {
                        _pickImagesFromGallery();
                      } else if (value == 'camera') {
                        _takePhotoWithCamera();
                      } else if (value == 'duplicates') {
                        _openDuplicateCleaner();
                      } else if (value == 'audit') {
                        _openAudit();
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'picker',
                        child: Row(
                          children: [
                            Icon(Icons.photo_library_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Pilih Beberapa Foto Manual'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'camera',
                        child: Row(
                          children: [
                            Icon(Icons.camera_alt_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Ambil Foto Kamera'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'audit',
                        child: Row(
                          children: [
                            const Icon(Icons.verified_user_outlined, size: 18),
                            const SizedBox(width: 10),
                            const Text('Audit Semua QRIS'),
                            if (_needsReviewCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.qrAmber.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$_needsReviewCount',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? const Color(0xFFFBBF24)
                                        : const Color(0xFF8A5A00),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'duplicates',
                        child: Row(
                          children: [
                            const Icon(Icons.filter_none_rounded, size: 18),
                            const SizedBox(width: 10),
                            const Text('Bersihkan Duplikat'),
                            if (_duplicateExtraCount > 0) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppTheme.qrAmber.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '$_duplicateExtraCount',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? const Color(0xFFFBBF24)
                                        : const Color(0xFF8A5A00),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.subtleBg(isDark),
                        border: Border.all(
                          color: AppTheme.borderColor(isDark),
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.more_horiz_rounded,
                          size: 20, color: AppTheme.inkColor(isDark)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    String message =
        'Belum ada foto yang dipindai.\nTekan tombol di bawah untuk memindai dan memverifikasi kode QRIS di galeri perangkat Anda.';
    IconData icon = Icons.qr_code_scanner_rounded;
    Color iconColor = AppTheme.qrisGreen;

    if (_items.isNotEmpty) {
      if (_filterMode == FilterMode.qrisOnly) {
        message =
            'Tidak ada foto QRIS yang ditemukan dari ${_items.length} foto yang dipindai.\nCoba picu pemindaian ulang galeri.';
        icon = Icons.verified_outlined;
        iconColor = AppTheme.qrisGreen;
      } else if (_filterMode == FilterMode.allQr) {
        message = 'Tidak ada foto dengan QR Code yang ditemukan.';
        icon = Icons.qr_code_2_rounded;
        iconColor = AppTheme.qrAmber;
      }
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.borderColor(isDark)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_items.isEmpty)
                const AppLogo(size: 56)
              else
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.subtleBg(isDark),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: iconColor.withOpacity(0.4)),
                  ),
                  child: Icon(icon, size: 28, color: iconColor),
                ),
              const SizedBox(height: 18),
              Text(
                _items.isEmpty
                    ? 'Pindai Galeri Perangkat'
                    : 'Tidak Ada Hasil Filter',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AppTheme.inkColor(isDark),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.mutedColor(isDark),
                  height: 1.5,
                ),
              ),
              if (_items.isEmpty) ...[
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _scanAllGalleryPhotos,
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Mulai Pindai Galeri'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.qrisGreenDark,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lembar konfirmasi pembersihan foto duplikat.
class _DuplicateCleanerSheet extends StatelessWidget {
  const _DuplicateCleanerSheet({required this.groups});

  final List<DuplicateGroup> groups;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final money = NumberFormat('#,##0', 'id_ID');
    final extras = DuplicateService.totalExtras(groups);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppTheme.borderColor(isDark))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 14),
            decoration: BoxDecoration(
              color: AppTheme.borderColor(isDark),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: AppTheme.qrAmber.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.filter_none_rounded,
                      size: 20, color: AppTheme.qrAmber),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bersihkan Duplikat',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: AppTheme.inkColor(isDark),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${groups.length} QRIS difoto lebih dari sekali · '
                        '$extras foto berlebih',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.mutedColor(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final g = groups[i];
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.subtleBg(isDark),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: AppTheme.borderColor(isDark)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              g.merchantName,
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
                              '${g.count} foto · simpan yang terbaru · ${g.acquirer}',
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
                      Text(
                        g.amount > 0 ? 'Rp ${money.format(g.amount)}' : '-',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? const Color(0xFF34D399)
                              : AppTheme.qrisGreenDark,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 14, 20, 18 + MediaQuery.of(context).viewPadding.bottom),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                    label: Text(
                      'Hapus $extras foto duplikat',
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.qrisGreenDark,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'Batal',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.mutedColor(isDark),
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
