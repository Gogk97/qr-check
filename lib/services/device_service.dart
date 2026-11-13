import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service untuk identifikasi unik perangkat fisik secara persisten.
///
/// Digunakan sebagai Primary Key untuk pengguna Tamu (Guest) agar
/// kuota tidak dapat di-reset dengan cara login ulang atau logout.
class DeviceService {
  static const String _persistentDeviceIdKey = 'persistent_device_id_v1';
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static String? _cachedDeviceId;
  static String? _cachedDeviceSummary;

  /// Mengambil ID Unik Perangkat (Hardware / Android ID)
  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null && _cachedDeviceId!.isNotEmpty) {
      return _cachedDeviceId!;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_persistentDeviceIdKey);
    if (savedId != null && savedId.isNotEmpty) {
      _cachedDeviceId = savedId;
      return savedId;
    }

    String deviceId = '';

    try {
      if (kIsWeb) {
        final webInfo = await _deviceInfo.webBrowserInfo;
        deviceId = 'web_${webInfo.userAgent.hashCode.abs().toRadixString(16)}';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        // androidInfo.id pada Android adalah Settings.Secure.ANDROID_ID
        deviceId = androidInfo.id.isNotEmpty
            ? androidInfo.id.toLowerCase()
            : '${androidInfo.brand}_${androidInfo.model}_${androidInfo.fingerprint.hashCode.abs()}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'ios_${iosInfo.model}_${iosInfo.utsname.machine}';
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        deviceId = macInfo.systemGUID ?? 'mac_${macInfo.computerName}';
      } else {
        deviceId = 'dev_${DateTime.now().millisecondsSinceEpoch}';
      }
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
    }

    // Bersihkan karakter non-alphanumeric agar aman sebagai ID
    deviceId = deviceId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    if (deviceId.isEmpty) {
      deviceId = 'device_${DateTime.now().millisecondsSinceEpoch}';
    }

    // Simpan permanen di SharedPreferences
    await prefs.setString(_persistentDeviceIdKey, deviceId);
    _cachedDeviceId = deviceId;
    return deviceId;
  }

  /// Mengambil ringkasan spesifikasi perangkat secara detail
  /// Contoh: "Infinix Infinix X6815D (Android 13, SDK 33)"
  static Future<String> getDeviceSummary() async {
    if (_cachedDeviceSummary != null && _cachedDeviceSummary!.isNotEmpty) {
      return _cachedDeviceSummary!;
    }

    try {
      if (kIsWeb) {
        final webInfo = await _deviceInfo.webBrowserInfo;
        final summary = '${webInfo.browserName.name} (Web Browser)';
        _cachedDeviceSummary = summary;
        return summary;
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        final brand = androidInfo.brand;
        final model = androidInfo.model;
        final release = androidInfo.version.release;
        final sdk = androidInfo.version.sdkInt;
        final summary = '$brand $model (Android $release, SDK $sdk)';
        _cachedDeviceSummary = summary;
        return summary;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        final summary = '${iosInfo.name} ${iosInfo.model} (iOS ${iosInfo.systemVersion})';
        _cachedDeviceSummary = summary;
        return summary;
      } else if (Platform.isMacOS) {
        final macInfo = await _deviceInfo.macOsInfo;
        final summary = '${macInfo.computerName} (macOS ${macInfo.osRelease})';
        _cachedDeviceSummary = summary;
        return summary;
      }
    } catch (e) {
      debugPrint('Error getting device summary: $e');
    }

    final fallback = Platform.operatingSystem;
    _cachedDeviceSummary = fallback;
    return fallback;
  }

  /// Mengambil informasi spesifikasi lengkap perangkat terstruktur
  static Future<Map<String, String?>> getDeviceDetails() async {
    String? platformName;
    String? brand;
    String? model;
    String? osVersion;
    final deviceId = await getDeviceId();
    final summary = await getDeviceSummary();

    try {
      if (kIsWeb) {
        final web = await _deviceInfo.webBrowserInfo;
        platformName = 'web';
        brand = web.browserName.name;
        model = web.userAgent;
        osVersion = web.platform;
      } else if (Platform.isAndroid) {
        final android = await _deviceInfo.androidInfo;
        platformName = 'android';
        brand = android.brand;
        model = android.model;
        osVersion = 'Android ${android.version.release} (SDK ${android.version.sdkInt})';
      } else if (Platform.isIOS) {
        final ios = await _deviceInfo.iosInfo;
        platformName = 'ios';
        brand = 'Apple';
        model = ios.utsname.machine;
        osVersion = 'iOS ${ios.systemVersion}';
      } else if (Platform.isMacOS) {
        final mac = await _deviceInfo.macOsInfo;
        platformName = 'macos';
        brand = 'Apple';
        model = mac.model;
        osVersion = 'macOS ${mac.osRelease}';
      } else {
        platformName = Platform.operatingSystem;
      }
    } catch (e) {
      debugPrint('Error getting device details: $e');
    }

    return {
      'device_id': deviceId,
      'device_brand': brand,
      'device_model': model,
      'os_version': osVersion,
      'device_platform': platformName,
      'device_summary': summary,
    };
  }
}
