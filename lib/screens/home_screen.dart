import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/scanned_item.dart';
import '../services/auth_service.dart';
import '../services/image_scanner_service.dart';
import '../services/monetization_service.dart';
import '../services/notification_service.dart';
import '../services/quota_service.dart';
import '../theme/app_theme.dart';
import '../widgets/scanned_item_card.dart';
import '../widgets/stats_card.dart';
import 'login_screen.dart';
import 'qris_payment_screen.dart';

enum FilterMode {
  qrisOnly,
  allQr,
  regularQrOnly,
  all,
  noQrOnly,
}

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
  bool _isCancelRequested = false;
  int _processedCount = 0;
  int _totalToProcess = 0;
  int _alreadyScannedCount = 0;
  int _totalGalleryCount = 0;
  double _scanSpeed = 0.0;
  final Stopwatch _scanStopwatch = Stopwatch();

  FilterMode _filterMode = FilterMode.qrisOnly; // Default: Hanya QRIS sesuai permintaan user

  bool get shouldShowDeleteToolbar =>
      _items.isNotEmpty && _filterMode != FilterMode.noQrOnly;

  String _selectedAcquirerFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadItemsFromStorage();
    _syncUserToCloudOnStartup();
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
      debugPrint('Profile sync on startup skipped: $e');
    }
  }

  @override
  void dispose() {
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
            .where((item) =>
                (item.assetId != null && item.assetId!.isNotEmpty) ||
                item.file.existsSync())
            .toList();
        if (mounted && loaded.isNotEmpty) {
          setState(() {
            _items.clear();
            _items.addAll(loaded);
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading items from storage: $e');
    }
  }

  Future<void> _saveItemsToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = _items.map((item) => item.toJson()).toList();
      await prefs.setString('saved_scanned_items_v1', jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving items to storage: $e');
    }
  }

  // Counts
  int get qrisCount => _items.where((i) => i.isQRIS).length;
  int get regularQrCount => _items.where((i) => i.hasQR && !i.isQRIS).length;
  int get allQrCount => _items.where((i) => i.hasQR).length;
  int get noQrCount => _items.where((i) => !i.hasQR && !i.isProcessing).length;
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
      case FilterMode.noQrOnly:
        list = _items.where((i) => !i.hasQR && !i.isProcessing).toList();
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
            .where((i) => i.isQRIS && i.qrisDetails?.displayAcquirer == _selectedAcquirerFilter)
            .toList();
      }
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
              content: Text('Izin galeri diperlukan untuk membaca dan memindai foto QR/QRIS.'),
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
            const SnackBar(content: Text('Tidak ada album foto yang ditemukan di galeri HP Anda.')),
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
            const SnackBar(content: Text('Galeri HP Anda belum memiliki foto.')),
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
              content: Text('Semua foto di galeri HP Anda sudah selesai dipindai! Tidak ada foto baru.'),
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

  Future<File> _saveFileToPermanentStorage(File sourceFile) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/qris_permanently_saved_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      if (sourceFile.path.startsWith(imagesDir.path)) {
        return sourceFile;
      }
      final fileName = '${DateTime.now().microsecondsSinceEpoch}_${sourceFile.uri.pathSegments.last.replaceAll(RegExp(r'[^a-zA-Z0-9_\.]'), '_')}';
      final targetPath = '${imagesDir.path}/$fileName';
      final savedFile = await sourceFile.copy(targetPath);
      return savedFile;
    } catch (e) {
      debugPrint('Error copying file to permanent storage: $e');
      return sourceFile;
    }
  }

  /// Helper pemindaian satu gambar & penyimpanan permanen jika terdeteksi QR/QRIS
  Future<ScannedItem> _processScanTarget({
    required File file,
    required String originalName,
    required String? assetId,
    required int fileSize,
  }) async {
    final id = 'scan_${DateTime.now().microsecondsSinceEpoch}_${file.path.hashCode}';
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
        isProcessing: false,
        hasQR: result.hasQR,
        isQRIS: result.isQRIS,
        rawContent: result.rawContent,
        qrType: result.qrType,
        qrisDetails: result.qrisDetails,
        errorMessage: result.errorMessage,
        isSelected: result.isSelected,
      );
    } else {
      return ScannedItem(
        id: result.id,
        file: file,
        fileName: originalName,
        originalFileName: originalName,
        assetId: assetId,
        fileSize: fileSize,
        addedAt: result.addedAt,
        isProcessing: false,
        hasQR: false,
        isQRIS: false,
        rawContent: result.rawContent,
        qrType: result.qrType,
        qrisDetails: null,
        errorMessage: result.errorMessage,
        isSelected: result.isSelected,
      );
    }
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
            );

            _items.insert(0, item);
          }
        } catch (e) {
          debugPrint('Error scanning entity ${entity.id}: $e');
        }

        _processedCount++;
        itemsSinceLastSave++;

        final elapsedSec = _scanStopwatch.elapsedMilliseconds / 1000.0;
        if (elapsedSec > 0.4) {
          _scanSpeed = _processedCount / elapsedSec;
        }

        final now = DateTime.now();
        if (now.difference(lastUiUpdateTime).inMilliseconds >= 150 || _processedCount >= entities.length) {
          lastUiUpdateTime = now;
          if (mounted) setState(() {});
        }

        if (itemsSinceLastSave >= 12 || now.difference(lastSaveTime).inMilliseconds >= 2500) {
          lastSaveTime = now;
          itemsSinceLastSave = 0;
          await _saveItemsToStorage();
        }

        if (now.difference(lastNotificationTime).inMilliseconds >= 600 || _processedCount >= entities.length) {
          lastNotificationTime = now;
          notificationService.showScanProgress(
            processedCount: _alreadyScannedCount + _processedCount,
            totalToProcess: _totalGalleryCount > 0 ? _totalGalleryCount : _totalToProcess,
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
          backgroundColor: wasCancelled ? Colors.orange.shade800 : (qrisCount > 0 ? AppTheme.qrisGreenDark : null),
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
  Future<void> _processFiles(List<File> files, {Map<File, String>? fileAssetMap}) async {
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
          );

          _items.insert(0, item);
        } catch (e) {
          debugPrint('Error scanning file ${file.path}: $e');
        }

        _processedCount++;
        itemsSinceLastSave++;

        final elapsedSec = _scanStopwatch.elapsedMilliseconds / 1000.0;
        if (elapsedSec > 0.4) {
          _scanSpeed = _processedCount / elapsedSec;
        }

        final now = DateTime.now();
        if (now.difference(lastUiUpdateTime).inMilliseconds >= 150 || _processedCount >= files.length) {
          lastUiUpdateTime = now;
          if (mounted) setState(() {});
        }

        if (itemsSinceLastSave >= 10 || now.difference(lastSaveTime).inMilliseconds >= 2500) {
          lastSaveTime = now;
          itemsSinceLastSave = 0;
          await _saveItemsToStorage();
        }

        if (now.difference(lastNotificationTime).inMilliseconds >= 600 || _processedCount >= files.length) {
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
          backgroundColor: wasCancelled ? Colors.orange.shade800 : (qrisCount > 0 ? AppTheme.qrisGreenDark : null),
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
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(top: BorderSide(color: AppTheme.borderColor(isDark), width: 1)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppTheme.subtleBg(isDark),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.borderColor(isDark)),
                      ),
                      child: Icon(
                        user?.isGuest == false ? Icons.verified_user_outlined : Icons.person_outline_rounded,
                        color: user?.isGuest == false ? AppTheme.primary : AppTheme.mutedColor(isDark),
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
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
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
                                    color: user?.isGuest == false ? AppTheme.primary : AppTheme.mutedColor(isDark),
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
                      color: isPro ? AppTheme.qrAmber.withOpacity(0.45) : AppTheme.borderColor(isDark),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isPro ? Icons.star_rounded : Icons.confirmation_number_outlined,
                            color: isPro ? AppTheme.qrAmber : AppTheme.primary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sisa Kuota Hapus',
                                style: TextStyle(fontSize: 11, color: AppTheme.mutedColor(isDark)),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                isPro ? 'UNLIMITED (PRO)' : '$remainingQuota Foto',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: isPro ? AppTheme.qrAmber : AppTheme.inkColor(isDark),
                                  fontFeatures: const [FontFeature.tabularFigures()],
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
                            await QuotaService.watchRewardedAdForQuota(context);
                            setState(() {});
                          },
                          icon: const Icon(Icons.ondemand_video_rounded, size: 15, color: AppTheme.primary),
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
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const QrisPaymentScreen()),
                    );
                  },
                  icon: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 19),
                  label: const Text(
                    'Pembayaran & Beli PRO (QRIS)',
                    style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.qrAmber,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                  icon: const Icon(Icons.logout_rounded, color: AppTheme.dangerRed, size: 17),
                  label: const Text(
                    'Ganti Akun / Keluar',
                    style: TextStyle(color: AppTheme.dangerRed, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.dangerRed.withOpacity(0.35)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleSelectAll() {
    final currentFiltered = filteredItems;
    final allSelected = currentFiltered.isNotEmpty && currentFiltered.every((i) => i.isSelected);
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
                        border: Border.all(color: AppTheme.dangerRed.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.delete_sweep_rounded, color: AppTheme.dangerRed, size: 24),
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
                            subtitle ?? 'File akan dihapus secara permanen dari galeri ponsel.',
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleBg(isDark),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderColor(isDark)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.storage_rounded, size: 14, color: AppTheme.primary),
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
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleBg(isDark),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderColor(isDark)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_2_rounded, size: 14, color: AppTheme.qrisGreen),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                qrisCount > 0 ? '$qrisCount QRIS' : '$regQrCount QR',
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
                            border: Border.all(color: AppTheme.borderColor(isDark)),
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
                                child: Icon(Icons.broken_image_outlined, size: 18, color: AppTheme.mutedColor(isDark)),
                              ),
                            ),
                            if (it.isQRIS)
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppTheme.qrisGreenDark,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('QRIS', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.qrAmber.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.qrAmber.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, size: 15, color: AppTheme.qrAmber),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          side: BorderSide(color: AppTheme.borderColor(isDark)),
                        ),
                        child: Text(
                          'Batal',
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.inkColor(isDark)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 6,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        icon: const Icon(Icons.delete_rounded, size: 17, color: Colors.white),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

    // Hapus foto asli dari Galeri Sistem HP (MediaStore)
    final systemAssetIds = selected
        .map((i) => i.assetId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    List<String> successfullyDeletedAssetIds = [];
    if (systemAssetIds.isNotEmpty) {
      try {
        successfullyDeletedAssetIds = await PhotoManager.editor.deleteWithIds(systemAssetIds);
      } catch (e) {
        debugPrint('Error deleting from system gallery: $e');
      }
    }

    // Jika pengguna membatalkan izin pada prompt sistem Android OS
    if (systemAssetIds.isNotEmpty && successfullyDeletedAssetIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Penghapusan dibatalkan (izin sistem tidak diberikan).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
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

    for (var item in itemsToRemove) {
      try {
        if (item.file.existsSync()) {
          item.file.deleteSync();
        }
      } catch (e) {
        debugPrint('Error deleting file: $e');
      }
    }

    if (mounted) {
      if (!isPro && itemsToRemove.isNotEmpty) {
        await QuotaService.consumeQuota(itemsToRemove.length);
      }
      final remaining = await QuotaService.getRemainingQuota();
      setState(() {
        final removeIds = itemsToRemove.map((i) => i.id).toSet();
        _items.removeWhere((i) => removeIds.contains(i.id));
      });
      await _saveItemsToStorage();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPro
                ? '✅ ${itemsToRemove.length} foto berhasil dibersihkan dari galeri!'
                : '✅ ${itemsToRemove.length} foto dibersihkan! (Sisa kuota: $remaining)',
          ),
          backgroundColor: AppTheme.qrisGreenDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty) return;

    final confirmed = await _showConfirmDeleteModal(
      items: _items,
      title: 'Bersihkan Semua Riwayat?',
      subtitle: 'Semua (${_items.length}) foto QR/QRIS akan dibersihkan dari riwayat dan galeri.',
    );
    if (!confirmed) return;

    final isPro = await MonetizationService.isProUser();
    final itemCount = _items.length;

    if (!isPro) {
      final currentQuota = await QuotaService.getRemainingQuota();
      if (currentQuota < itemCount) {
        if (!mounted) return;
        await QuotaService.showQuotaExhaustedDialog(
          context,
          needed: itemCount,
          current: currentQuota,
        );
        setState(() {});
        return;
      }

      if (itemCount > 3) {
        if (!mounted) return;
        final allowed = await MonetizationService.showMassDeleteDialog(
          context,
          itemCount: itemCount,
        );
        if (!allowed) return;
      } else if (itemCount <= 3) {
        if (!mounted) return;
        await MonetizationService.showInterstitialAd(context);
      }
    }

    final systemAssetIds = _items
        .map((i) => i.assetId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();

    List<String> successfullyDeletedAssetIds = [];
    if (systemAssetIds.isNotEmpty) {
      try {
        successfullyDeletedAssetIds = await PhotoManager.editor.deleteWithIds(systemAssetIds);
      } catch (e) {
        debugPrint('Error deleting from system gallery: $e');
      }
    }

    if (systemAssetIds.isNotEmpty && successfullyDeletedAssetIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Penghapusan dibatalkan (izin sistem tidak diberikan).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final deletedAssetSet = successfullyDeletedAssetIds.toSet();
    final itemsToRemove = _items.where((item) {
      if (item.assetId != null && item.assetId!.isNotEmpty) {
        return deletedAssetSet.contains(item.assetId);
      }
      return true;
    }).toList();

    for (var item in itemsToRemove) {
      try {
        if (item.file.existsSync()) {
          item.file.deleteSync();
        }
      } catch (e) {
        debugPrint('Error deleting file: $e');
      }
    }

    if (mounted) {
      if (!isPro && itemsToRemove.isNotEmpty) {
        await QuotaService.consumeQuota(itemsToRemove.length);
      }
      final remaining = await QuotaService.getRemainingQuota();
      setState(() {
        final removeIds = itemsToRemove.map((i) => i.id).toSet();
        _items.removeWhere((i) => removeIds.contains(i.id));
      });
      await _saveItemsToStorage();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPro
                ? '✅ ${itemsToRemove.length} foto berhasil dibersihkan!'
                : '✅ ${itemsToRemove.length} foto dibersihkan! (Sisa kuota: $remaining)',
          ),
          backgroundColor: AppTheme.qrisGreenDark,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppTheme.qrisGreenDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'QRIS Detector',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Kuota Hapus Chip Minimalis (Bisa diklik untuk info / tambah kuota lewat iklan)
          FutureBuilder<int>(
            future: QuotaService.getRemainingQuota(),
            builder: (context, quotaSnap) {
              final quota = quotaSnap.data ?? 5;
              return Container(
                margin: const EdgeInsets.only(right: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    await QuotaService.showQuotaManagementDialog(context);
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.subtleBg(isDark),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.borderColor(isDark)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.confirmation_number_outlined, color: AppTheme.primary, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          '$quota',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.inkColor(isDark),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          // PRO Badge & Modal Upgrade Trigger Minimalis
          FutureBuilder<bool>(
            future: MonetizationService.isProUser(),
            builder: (context, snapshot) {
              final isPro = snapshot.data ?? false;
              return Container(
                margin: const EdgeInsets.only(right: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () async {
                    await MonetizationService.showProUpgradeModal(context);
                    setState(() {});
                  },
                  onLongPress: isPro
                      ? () async {
                          // Secret Dev Reset PRO Status
                          await MonetizationService.setProUser(false);
                          setState(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('[Dev Mode] Reset status ke FREE User.')),
                            );
                          }
                        }
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: isPro ? AppTheme.qrAmber.withOpacity(0.16) : AppTheme.subtleBg(isDark),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isPro ? AppTheme.qrAmber : AppTheme.borderColor(isDark),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPro ? Icons.star_rounded : Icons.workspace_premium_outlined,
                          color: isPro ? AppTheme.qrAmber : AppTheme.mutedColor(isDark),
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'PRO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: isPro ? AppTheme.qrAmber : AppTheme.mutedColor(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (_items.isNotEmpty)
            IconButton(
              tooltip: 'Bersihkan Daftar',
              icon: const Icon(Icons.delete_sweep_outlined, size: 20),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: const EdgeInsets.all(4),
              onPressed: _clearAll,
            ),
          IconButton(
            tooltip: 'Akun & Profil',
            icon: const Icon(Icons.account_circle_outlined, size: 22),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            onPressed: _showAccountModal,
          ),
          const SizedBox(width: 4),
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatsCard(
                      title: 'Bukan QR',
                      count: noQrCount,
                      icon: Icons.hide_image_outlined,
                      color: AppTheme.nonQrGrey,
                      isSelected: _filterMode == FilterMode.noQrOnly,
                      onTap: () {
                        setState(() {
                          if (_filterMode == FilterMode.noQrOnly) {
                            _filterMode = FilterMode.all;
                            _selectedAcquirerFilter = 'ALL';
                          } else {
                            _filterMode = FilterMode.noQrOnly;
                            _selectedAcquirerFilter = 'ALL';
                            for (var i in _items) {
                              i.isSelected = false;
                            }
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
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
                                      color: isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark,
                                      fontFeatures: const [FontFeature.tabularFigures()],
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.dangerRed.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.dangerRed.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isCancelRequested ? Icons.hourglass_top : Icons.pause_circle_filled,
                                  size: 14,
                                  color: AppTheme.dangerRed,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isCancelRequested ? 'Menghentikan...' : 'Jeda',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.dangerRed),
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
                            ? (_alreadyScannedCount + _processedCount) / _totalGalleryCount
                            : (_totalToProcess > 0 ? _processedCount / _totalToProcess : null),
                        minHeight: 5,
                        backgroundColor: AppTheme.subtleBg(isDark),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _isCancelRequested ? AppTheme.qrAmber : AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Filter Penyelenggara (Acquirer) Chips Bar
            if (acquirerCounts.isNotEmpty && _filterMode != FilterMode.noQrOnly)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined, size: 13, color: AppTheme.qrisGreen),
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
                            onTap: () => setState(() => _selectedAcquirerFilter = 'ALL'),
                            child: const Text(
                              'Reset Filter',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.dangerRed),
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
                              if (selected) setState(() => _selectedAcquirerFilter = 'ALL');
                            },
                            backgroundColor: AppTheme.cardColor(isDark),
                            selectedColor: AppTheme.primary.withOpacity(0.15),
                            side: BorderSide(
                              color: _selectedAcquirerFilter == 'ALL'
                                  ? AppTheme.primary
                                  : AppTheme.borderColor(isDark),
                              width: _selectedAcquirerFilter == 'ALL' ? 1.4 : 1.0,
                            ),
                            labelStyle: TextStyle(
                              fontSize: 11,
                              fontWeight: _selectedAcquirerFilter == 'ALL' ? FontWeight.w700 : FontWeight.w500,
                              color: _selectedAcquirerFilter == 'ALL'
                                  ? (isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark)
                                  : AppTheme.inkColor(isDark),
                            ),
                            showCheckmark: false,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          if (_filterMode == FilterMode.allQr && regularQrCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: ChoiceChip(
                                label: Text('Non-QRIS ($regularQrCount)'),
                                selected: _selectedAcquirerFilter == 'NON_QRIS',
                                onSelected: (selected) {
                                  setState(() {
                                    _selectedAcquirerFilter = selected ? 'NON_QRIS' : 'ALL';
                                  });
                                },
                                backgroundColor: AppTheme.cardColor(isDark),
                                selectedColor: AppTheme.qrAmber.withOpacity(0.18),
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: _selectedAcquirerFilter == 'NON_QRIS' ? FontWeight.w700 : FontWeight.w500,
                                  color: _selectedAcquirerFilter == 'NON_QRIS'
                                      ? AppTheme.qrAmber
                                      : AppTheme.inkColor(isDark),
                                ),
                                side: BorderSide(
                                  color: _selectedAcquirerFilter == 'NON_QRIS'
                                      ? AppTheme.qrAmber
                                      : AppTheme.borderColor(isDark),
                                  width: _selectedAcquirerFilter == 'NON_QRIS' ? 1.4 : 1.0,
                                ),
                                showCheckmark: false,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                                    _selectedAcquirerFilter = selected ? acqName : 'ALL';
                                    if (selected && _filterMode != FilterMode.qrisOnly) {
                                      _filterMode = FilterMode.qrisOnly;
                                    }
                                  });
                                },
                                backgroundColor: AppTheme.cardColor(isDark),
                                selectedColor: AppTheme.qrisGreen.withOpacity(0.15),
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                  color: isSel
                                      ? (isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark)
                                      : AppTheme.inkColor(isDark),
                                ),
                                side: BorderSide(
                                  color: isSel ? AppTheme.qrisGreen : AppTheme.borderColor(isDark),
                                  width: isSel ? 1.4 : 1.0,
                                ),
                                showCheckmark: false,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            // Batch selection toolbar if filter mode is QRIS or QR
            if (shouldShowDeleteToolbar)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                        child: Row(
                          children: [
                            Icon(
                              filteredItems.isNotEmpty && filteredItems.every((i) => i.isSelected)
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 18,
                              color: AppTheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              selectedCount > 0 ? '$selectedCount dipilih' : 'Pilih Semua',
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
                        label: const Text('Bagikan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                      TextButton.icon(
                        onPressed: _deleteSelected,
                        icon: const Icon(Icons.delete_outline_rounded, size: 15, color: AppTheme.dangerRed),
                        label: const Text(
                          'Hapus',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.dangerRed),
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
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
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
                              showSelection: _filterMode != FilterMode.noQrOnly,
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
      bottomNavigationBar: Container(
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
                  onPressed: _isBatchProcessing ? null : _scanAllGalleryPhotos,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _items.isNotEmpty ? 'Pindai / Lanjutkan Galeri (AI)' : 'Pindai Semua Galeri (AI)',
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
                  child: Icon(Icons.more_horiz_rounded, size: 20, color: AppTheme.inkColor(isDark)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    String message = 'Belum ada foto yang dipindai.\nTekan tombol di bawah untuk memindai dan memverifikasi kode QRIS di galeri perangkat Anda.';
    IconData icon = Icons.qr_code_scanner_rounded;
    Color iconColor = AppTheme.qrisGreen;

    if (_items.isNotEmpty) {
      if (_filterMode == FilterMode.qrisOnly) {
        message = 'Tidak ada foto QRIS yang ditemukan dari ${_items.length} foto yang dipindai.\nCoba picu pemindaian ulang galeri.';
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
                _items.isEmpty ? 'Pindai Galeri Perangkat' : 'Tidak Ada Hasil Filter',
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
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
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
