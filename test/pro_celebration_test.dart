import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_check/widgets/pro_celebration_dialog.dart';

void main() {
  testWidgets('perayaan PRO tampil dan bisa ditutup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showProCelebration(ctx),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('buka'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Selamat, kamu PRO!'), findsOneWidget);
    expect(find.text('Kuota tanpa batas'), findsOneWidget);
    expect(find.text('Mantap, mulai pakai!'), findsOneWidget);
    expect(find.text('Aktif permanen di akun ini'), findsOneWidget);

    await tester.ensureVisible(find.text('Mantap, mulai pakai!'));
    await tester.pump();
    await tester.tap(find.text('Mantap, mulai pakai!'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Selamat, kamu PRO!'), findsNothing);
  });

  testWidgets('perayaan PRO muat di layar kecil tanpa overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showProCelebration(ctx),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('buka'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
