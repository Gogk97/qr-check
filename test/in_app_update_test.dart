import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/services/in_app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.qrcheck.app/in_app_update');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockUpdate(Map<String, dynamic> info, {List<String>? calls}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls?.add(call.method);
      if (call.method == 'checkUpdate') return info;
      return true;
    });
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    InAppUpdateService.debugForceSupported = null;
  });

  test('platform non-Android tidak melakukan pemeriksaan', () async {
    InAppUpdateService.debugForceSupported = false;
    final msg = await InAppUpdateService.checkManually();
    expect(msg, contains('Android'));
  });

  test('aplikasi sudah versi terbaru', () async {
    InAppUpdateService.debugForceSupported = true;
    mockUpdate({
      'available': false,
      'immediateAllowed': true,
      'flexibleAllowed': true,
      'priority': 0,
      'availableVersionCode': 5,
      'installStatus': 0,
      'fromPlayStore': true,
      'inProgress': false,
    });

    final msg = await InAppUpdateService.checkManually();
    expect(msg, contains('versi terbaru'));
  });

  test('pembaruan tersedia memakai alur flexible', () async {
    InAppUpdateService.debugForceSupported = true;
    final calls = <String>[];
    mockUpdate({
      'available': true,
      'immediateAllowed': true,
      'flexibleAllowed': true,
      'priority': 0,
      'availableVersionCode': 6,
      'installStatus': 0,
      'fromPlayStore': true,
      'inProgress': false,
    }, calls: calls);

    final msg = await InAppUpdateService.checkManually();
    expect(calls, contains('startFlexible'));
    expect(calls, isNot(contains('startImmediate')));
    expect(msg, contains('latar belakang'));
  });

  test('priority tinggi memakai alur immediate', () async {
    InAppUpdateService.debugForceSupported = true;
    final calls = <String>[];
    mockUpdate({
      'available': true,
      'immediateAllowed': true,
      'flexibleAllowed': true,
      'priority': 5,
      'availableVersionCode': 6,
      'installStatus': 0,
      'fromPlayStore': true,
      'inProgress': false,
    }, calls: calls);

    await InAppUpdateService.checkManually();
    expect(calls, contains('startImmediate'));
    expect(calls, isNot(contains('startFlexible')));
  });

  test('aplikasi hasil sideload tidak ditawari pembaruan', () async {
    InAppUpdateService.debugForceSupported = true;
    mockUpdate({
      'available': true,
      'immediateAllowed': true,
      'flexibleAllowed': true,
      'priority': 0,
      'availableVersionCode': 6,
      'installStatus': 0,
      'fromPlayStore': false,
      'inProgress': false,
    });

    final msg = await InAppUpdateService.checkManually();
    expect(msg, contains('Play Store'));
  });
}
