import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
    );

    await _notifications.initialize(initSettings);

    final androidImplementation = _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
    }

    _isInitialized = true;
  }

  Future<void> showScanProgress({
    required int processedCount,
    required int totalToProcess,
    required int qrisFoundCount,
  }) async {
    await init();

    final int percent = totalToProcess > 0
        ? ((processedCount / totalToProcess) * 100).toInt()
        : 0;

    final androidDetails = AndroidNotificationDetails(
      'scan_progress_channel_v2',
      'Progress Pemindaian QRIS',
      channelDescription: 'Menampilkan status pemindaian foto galeri secara real-time',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showProgress: true,
      maxProgress: totalToProcess,
      progress: processedCount,
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      888,
      'Memindai Galeri ($percent%)',
      'Diproses: $processedCount / $totalToProcess foto • Ditemukan $qrisFoundCount QRIS',
      notificationDetails,
    );
  }

  Future<void> showScanComplete({
    required int totalProcessed,
    required int qrisFoundCount,
  }) async {
    await init();

    // Clear progress notification
    await _notifications.cancel(888);

    const androidDetails = AndroidNotificationDetails(
      'scan_complete_channel_v2',
      'Hasil Pemindaian QRIS',
      channelDescription: 'Notifikasi saat pemindaian foto selesai',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      889,
      'Pemindaian Selesai! 🎉',
      'Selesai memindai $totalProcessed foto. Ditemukan $qrisFoundCount QRIS!',
      notificationDetails,
    );
  }

  Future<void> cancelProgress() async {
    await _notifications.cancel(888);
  }
}
