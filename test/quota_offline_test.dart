import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/services/quota_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Kuota offline', () {
    test('tanpa login, potongan kuota masuk antrean dan tetap diizinkan',
        () async {
      final ok = await QuotaService.consumeQuota(3, refId: 'ref-offline-1');

      expect(ok, isTrue, reason: 'tidak boleh memblokir saat sinyal buruk');
      expect(QuotaService.usedOffline, isTrue);
      expect(await QuotaService.pendingOfflineItems(), 3);
    });

    test('beberapa operasi offline dijumlahkan di antrean', () async {
      await QuotaService.consumeQuota(2, refId: 'r1');
      await QuotaService.consumeQuota(5, refId: 'r2');

      expect(await QuotaService.pendingOfflineItems(), 7);
    });

    test('jatah offline dibatasi per hari', () async {
      // Pakai seluruh jatah harian.
      final first = await QuotaService.consumeQuota(
        QuotaService.offlineDailyAllowance,
        refId: 'big',
      );
      expect(first, isTrue);

      final second = await QuotaService.consumeQuota(1, refId: 'extra');
      expect(second, isFalse, reason: 'melebihi jatah offline harian');
      expect(QuotaService.lastError, contains('Kuota offline habis'));
      expect(await QuotaService.pendingOfflineItems(),
          QuotaService.offlineDailyAllowance);
    });

    test('refund membatalkan potongan yang masih di antrean', () async {
      await QuotaService.consumeQuota(4, refId: 'refund-me');
      expect(await QuotaService.pendingOfflineItems(), 4);

      await QuotaService.refundQuota('refund-me', 4);

      expect(await QuotaService.pendingOfflineItems(), 0);
    });

    test('syncPending tanpa sesi login tidak mengubah apa pun', () async {
      await QuotaService.consumeQuota(2, refId: 'pending-x');
      final synced = await QuotaService.syncPending();

      expect(synced, 0);
      expect(await QuotaService.pendingOfflineItems(), 2,
          reason: 'antrean tetap tersimpan untuk dicoba lagi');
    });
  });
}
