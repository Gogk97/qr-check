import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/constants/supabase_config.dart';
import 'package:qr_check/main.dart';
import 'package:qr_check/screens/home_screen.dart';
import 'package:qr_check/screens/login_screen.dart';
import 'package:qr_check/screens/qris_payment_screen.dart';
import 'package:qr_check/services/quota_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App smoke test for HomeScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const QRCheckApp(home: HomeScreen()));
    expect(find.text('Qristal'), findsOneWidget);
    expect(find.text('Pindai Semua Galeri (AI)'), findsOneWidget);
  });

  testWidgets('LoginScreen displays Google and Guest buttons', (WidgetTester tester) async {
    await tester.pumpWidget(const QRCheckApp(home: LoginScreen()));
    expect(find.text('Lanjutkan dengan Google'), findsOneWidget);
    expect(find.text('Masuk sebagai Tamu (Guest)'), findsOneWidget);
  });

  testWidgets('QrisPaymentScreen displays QRIS payment elements', (WidgetTester tester) async {
    await tester.pumpWidget(const QRCheckApp(home: QrisPaymentScreen()));
    expect(find.text('Pembayaran QRIS PRO'), findsOneWidget);
    expect(find.text('QRIS Standar Nasional'), findsOneWidget);
    expect(find.text('Kirim Konfirmasi Pembayaran'), findsOneWidget);
  });

  test('QuotaService memakai jatah offline terbatas, bukan bypass bebas', () async {
    // 1. Kuota awal Google = 10 (cache lokal untuk tampilan)
    final googleQuota = await QuotaService.initQuotaForLogin(isGoogle: true, userId: 'test_google_1');
    expect(googleQuota, equals(10));
    expect(await QuotaService.getRemainingQuota(), equals(10));

    // 2. Tanpa sesi Supabase: operasi tetap diizinkan, TETAPI dicatat sebagai
    //    antrean yang harus disinkronkan ke server saat online.
    final consumed = await QuotaService.consumeQuota(3, refId: 'test-offline-1');
    expect(consumed, isTrue, reason: 'sinyal buruk tidak boleh memblokir hapus');
    expect(QuotaService.usedOffline, isTrue);
    expect(await QuotaService.pendingOfflineItems(), equals(3),
        reason: 'potongan tetap ditagihkan ke server nanti');

    // 3. Jatah offline per hari dibatasi, jadi tidak bisa dipakai gratis terus.
    final overLimit = await QuotaService.consumeQuota(
      QuotaService.offlineDailyAllowance,
      refId: 'test-offline-over',
    );
    expect(overLimit, isFalse);
    expect(QuotaService.lastError, contains('Kuota offline habis'));

    // 3. Reward iklan juga tidak boleh menambah kuota secara lokal.
    final added = await QuotaService.addQuota(1);
    expect(added, equals(10));

    // 4. Kuota awal Guest = 5
    final guestQuota = await QuotaService.initQuotaForLogin(isGoogle: false, userId: 'test_guest_1');
    expect(guestQuota, equals(5));
    expect(await QuotaService.getRemainingQuota(), equals(5));

    // 5. Login ulang dengan userId yang sama tidak me-reset kuota
    final restoredGuestQuota = await QuotaService.initQuotaForLogin(isGoogle: false, userId: 'test_guest_1');
    expect(restoredGuestQuota, equals(5));
  });

  test('SupabaseConfig has valid project URL and anon key', () {
    expect(SupabaseConfig.projectUrl, contains('https://oljiqzttttxjrbwtfzze.supabase.co'));
    expect(SupabaseConfig.anonKey, isNotEmpty);
    expect(SupabaseConfig.googleWebClientId, isNotEmpty);
  });
}
