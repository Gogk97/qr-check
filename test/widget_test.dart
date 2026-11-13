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
    expect(find.text('QRIS Detector'), findsOneWidget);
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

  test('QuotaService correctly initializes and manages quota', () async {
    // 1. Initial Google Quota = 10
    final googleQuota = await QuotaService.initQuotaForLogin(isGoogle: true, userId: 'test_google_1');
    expect(googleQuota, equals(10));
    expect(await QuotaService.getRemainingQuota(), equals(10));

    // 2. Consume 3 quota
    final consumed = await QuotaService.consumeQuota(3);
    expect(consumed, isTrue);
    expect(await QuotaService.getRemainingQuota(), equals(7));

    // 3. Add 1 quota via watching ad
    final added = await QuotaService.addQuota(1);
    expect(added, equals(8));
    expect(await QuotaService.getRemainingQuota(), equals(8));

    // 4. Initial Guest Quota for new user = 5
    final guestQuota = await QuotaService.initQuotaForLogin(isGoogle: false, userId: 'test_guest_1');
    expect(guestQuota, equals(5));
    expect(await QuotaService.getRemainingQuota(), equals(5));

    // 5. Guest consumes 2 quotas -> remaining 3
    await QuotaService.consumeQuota(2);
    expect(await QuotaService.getRemainingQuota(), equals(3));

    // 6. Guest logs in again with same userId -> MUST restore 3, NOT reset to 5
    final restoredGuestQuota = await QuotaService.initQuotaForLogin(isGoogle: false, userId: 'test_guest_1');
    expect(restoredGuestQuota, equals(3));
    expect(await QuotaService.getRemainingQuota(), equals(3));
  });

  test('SupabaseConfig has valid project URL and anon key', () {
    expect(SupabaseConfig.projectUrl, contains('https://oljiqzttttxjrbwtfzze.supabase.co'));
    expect(SupabaseConfig.anonKey, isNotEmpty);
    expect(SupabaseConfig.googleWebClientId, isNotEmpty);
  });
}
