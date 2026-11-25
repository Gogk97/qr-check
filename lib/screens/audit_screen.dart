import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/scanned_item.dart';
import '../services/qris_audit_service.dart';
import '../theme/app_theme.dart';
import '../widgets/qris_detail_bottom_sheet.dart';

/// Halaman audit seluruh QRIS tersimpan.
///
/// Menampilkan skor keamanan tiap payload, diurutkan dari yang paling
/// mencurigakan. Pemeriksaan dilakukan lokal, tanpa jaringan.
class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key, required this.items});

  final List<ScannedItem> items;

  static Future<void> open(BuildContext context, List<ScannedItem> items) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AuditScreen(items: items)),
    );
  }

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

enum _AuditFilter { all, safe, review, suspicious }

class _AuditScreenState extends State<AuditScreen> {
  static final DateFormat _dateFmt = DateFormat('d MMM yyyy', 'id_ID');
  static final NumberFormat _money = NumberFormat('#,##0', 'id_ID');

  late final Map<String, QrisAuditResult> _results;
  late final List<ScannedItem> _sorted;
  _AuditFilter _filter = _AuditFilter.all;

  @override
  void initState() {
    super.initState();
    final qrisItems = widget.items.where((e) => e.isQRIS).toList();
    _results = QrisAuditService.auditAll(qrisItems);
    _sorted = qrisItems.toList()
      ..sort((a, b) {
        final sa = _results[a.id]?.score ?? 100;
        final sb = _results[b.id]?.score ?? 100;
        return sa.compareTo(sb);
      });
  }

  List<ScannedItem> get _filtered {
    return _sorted.where((item) {
      final verdict = _results[item.id]?.verdict ?? AuditVerdict.safe;
      return switch (_filter) {
        _AuditFilter.all => true,
        _AuditFilter.safe => verdict == AuditVerdict.safe,
        _AuditFilter.review => verdict == AuditVerdict.review,
        _AuditFilter.suspicious => verdict == AuditVerdict.suspicious,
      };
    }).toList();
  }

  int _count(AuditVerdict verdict) => _results.values
      .where((r) => r.verdict == verdict)
      .length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;
    final safe = _count(AuditVerdict.safe);
    final review = _count(AuditVerdict.review);
    final suspicious = _count(AuditVerdict.suspicious);

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
                color: AppTheme.qrisGreen.withOpacity(isDark ? 0.20 : 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.verified_user_rounded,
                  size: 18, color: AppTheme.qrisGreen),
            ),
            const SizedBox(width: 10),
            Text(
              'Audit QRIS',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppTheme.inkColor(isDark),
              ),
            ),
          ],
        ),
      ),
      body: _sorted.isEmpty
          ? _buildEmpty(isDark)
          : SafeArea(
              top: false,
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  Text(
                    'Setiap QRIS diperiksa strukturnya, checksum CRC, format '
                    'NMID, mata uang, dan konsistensi merchant. Semua diproses '
                    'di perangkat Anda.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: AppTheme.mutedColor(isDark),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _stat(isDark, 'Aman', safe, AppTheme.qrisGreen,
                            _AuditFilter.safe),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _stat(isDark, 'Perlu dicek', review,
                            AppTheme.qrAmber, _AuditFilter.review),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _stat(
                          isDark,
                          'Mencurigakan',
                          suspicious,
                          isDark
                              ? const Color(0xFFF87171)
                              : const Color(0xFFB91C1C),
                          _AuditFilter.suspicious,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        '${filtered.length} QRIS',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.inkColor(isDark),
                        ),
                      ),
                      const Spacer(),
                      if (_filter != _AuditFilter.all)
                        TextButton(
                          onPressed: () =>
                              setState(() => _filter = _AuditFilter.all),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, 30),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('Tampilkan semua',
                              style: TextStyle(fontSize: 11.5)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...filtered.map((item) => _row(isDark, item)),
                ],
              ),
            ),
    );
  }

  Widget _stat(bool isDark, String label, int count, Color accent,
      _AuditFilter filter) {
    final selected = _filter == filter;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(
          () => _filter = selected ? _AuditFilter.all : filter),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? accent.withOpacity(isDark ? 0.18 : 0.12)
              : AppTheme.cardColor(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent.withOpacity(0.55) : AppTheme.borderColor(isDark),
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.mutedColor(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(bool isDark, ScannedItem item) {
    final result = _results[item.id]!;
    final accent = switch (result.verdict) {
      AuditVerdict.safe => AppTheme.qrisGreen,
      AuditVerdict.review => AppTheme.qrAmber,
      AuditVerdict.suspicious =>
        isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C),
    };
    final merchant = item.qrisDetails?.merchantName ?? '';
    final amount = item.qrisDetails?.amount ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => QRISDetailBottomSheet.show(context, item),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.borderColor(isDark)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${result.score}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      merchant.isEmpty ? 'QRIS Tanpa Nama' : merchant,
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
                      '${_dateFmt.format(item.reportDate)} · '
                      '${result.findings.isEmpty ? 'tanpa temuan' : '${result.findings.length} temuan'}',
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
                amount > 0 ? 'Rp ${_money.format(amount)}' : '-',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isDark
                      ? const Color(0xFF34D399)
                      : AppTheme.qrisGreenDark,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppTheme.qrisGreen.withOpacity(isDark ? 0.16 : 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_user_outlined,
                  size: 34, color: AppTheme.qrisGreen),
            ),
            const SizedBox(height: 16),
            Text(
              'Belum ada QRIS untuk diaudit',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkColor(isDark),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pindai QRIS dari galeri terlebih dahulu, lalu buka halaman ini '
              'untuk memeriksa keaslian payload-nya.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppTheme.mutedColor(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
