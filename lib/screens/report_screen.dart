import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/scanned_item.dart';
import '../services/export_service.dart';
import '../theme/app_theme.dart';

enum _RangePreset { d7, d30, d90, all, custom }

/// Laporan QRIS (khusus PRO): chart nominal per tanggal, filter tanggal &
/// rentang harga, ringkasan, daftar transaksi, dan ekspor CSV/Excel.
class ReportScreen extends StatefulWidget {
  final List<ScannedItem> items;

  const ReportScreen({super.key, required this.items});

  static Future<void> open(BuildContext context, {required List<ScannedItem> items}) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReportScreen(items: items)),
    );
  }

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static final NumberFormat _money =
      NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  static final DateFormat _dayFmt = DateFormat('d MMM', 'id_ID');
  static final DateFormat _fullFmt = DateFormat('d MMM yyyy', 'id_ID');

  late final List<ScannedItem> _all;
  _RangePreset _preset = _RangePreset.d30;
  DateTimeRange? _customRange;
  RangeValues? _priceRange;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _all = ExportService.reportable(widget.items);
  }

  double get _maxAmount {
    if (_all.isEmpty) return 0;
    return _all
        .map((e) => e.qrisDetails?.amount ?? 0)
        .reduce((a, b) => a > b ? a : b);
  }

  RangeValues get _effectivePriceRange =>
      _priceRange ?? RangeValues(0, _maxAmount == 0 ? 1 : _maxAmount);

  DateTimeRange? get _effectiveDateRange {
    final now = DateTime.now();
    switch (_preset) {
      case _RangePreset.d7:
        return DateTimeRange(
            start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
            end: now);
      case _RangePreset.d30:
        return DateTimeRange(
            start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29)),
            end: now);
      case _RangePreset.d90:
        return DateTimeRange(
            start: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 89)),
            end: now);
      case _RangePreset.custom:
        return _customRange;
      case _RangePreset.all:
        return null;
    }
  }

  List<ScannedItem> get _filtered {
    final range = _effectiveDateRange;
    final price = _effectivePriceRange;

    return _all.where((item) {
      final amount = item.qrisDetails?.amount ?? 0;
      if (amount < price.start || amount > price.end) return false;
      if (range != null) {
        final endOfDay = DateTime(
            range.end.year, range.end.month, range.end.day, 23, 59, 59);
        if (item.reportDate.isBefore(range.start) || item.reportDate.isAfter(endOfDay)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  double get _total => _filtered.fold(
        0,
        (sum, e) => sum + (e.qrisDetails?.amount ?? 0),
      );

  // ---------------------------------------------------------------- chart

  /// Bucket nominal per hari (atau per minggu untuk rentang panjang).
  List<MapEntry<DateTime, double>> _chartPoints(List<ScannedItem> items) {
    if (items.isEmpty) return const [];

    final range = _effectiveDateRange;
    final weekly = _preset == _RangePreset.d90 || _preset == _RangePreset.all;

    final buckets = <DateTime, double>{};
    for (final item in items) {
      final d = item.reportDate;
      DateTime key;
      if (weekly) {
        // Awal minggu (Senin).
        key = DateTime(d.year, d.month, d.day)
            .subtract(Duration(days: d.weekday - 1));
      } else {
        key = DateTime(d.year, d.month, d.day);
      }
      buckets[key] = (buckets[key] ?? 0) + (item.qrisDetails?.amount ?? 0);
    }

    final sortedKeys = buckets.keys.toList()..sort();
    if (sortedKeys.isEmpty) return const [];

    // Isi tanggal kosong agar chart kontinu (maks. 31 titik).
    final start = range?.start ?? sortedKeys.first;
    final end = range?.end ?? sortedKeys.last;
    final points = <MapEntry<DateTime, double>>[];
    var cursor = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    final step = weekly ? const Duration(days: 7) : const Duration(days: 1);
    var guard = 0;

    while (!cursor.isAfter(last) && guard < 60) {
      points.add(MapEntry(cursor, buckets[cursor] ?? 0));
      cursor = cursor.add(step);
      guard++;
    }
    return points;
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
              start: now.subtract(const Duration(days: 29)), end: now),
      helpText: 'Pilih rentang tanggal',
      saveText: 'Terapkan',
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _preset = _RangePreset.custom;
      });
    }
  }

  Future<void> _export(List<ScannedItem> items) async {
    if (items.isEmpty) return;

    final format = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: 20 + MediaQuery.of(ctx).viewPadding.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.borderColor(isDark),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Ekspor ${items.length} transaksi',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AppTheme.inkColor(isDark),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ExportService.summary(items),
                style: TextStyle(fontSize: 12.5, color: AppTheme.mutedColor(isDark)),
              ),
              const SizedBox(height: 16),
              _exportOption(
                ctx,
                isDark,
                icon: Icons.table_chart_rounded,
                title: 'CSV (.csv)',
                subtitle: 'Universal — Excel, Google Sheets, Numbers',
                value: 'csv',
              ),
              const SizedBox(height: 8),
              _exportOption(
                ctx,
                isDark,
                icon: Icons.grid_on_rounded,
                title: 'Excel (.xls)',
                subtitle: 'Langsung terbuka sebagai workbook Excel',
                value: 'xls',
              ),
            ],
          ),
        );
      },
    );

    if (format == null) return;

    setState(() => _exporting = true);
    try {
      if (format == 'csv') {
        await ExportService.shareCsv(items);
      } else {
        await ExportService.shareExcel(items);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Laporan ${format.toUpperCase()} siap dibagikan.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengekspor: $e'),
            backgroundColor: AppTheme.dangerRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _exportOption(
    BuildContext ctx,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    required String value,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(ctx).pop(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.subtleBg(isDark),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.borderColor(isDark)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.qrisGreen.withOpacity(0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 19, color: AppTheme.qrisGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.inkColor(isDark),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.mutedColor(isDark)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: AppTheme.mutedColor(isDark)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;
    final points = _chartPoints(filtered);

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
              child: const Icon(Icons.insights_rounded,
                  size: 19, color: AppTheme.qrisGreen),
            ),
            const SizedBox(width: 10),
            Text(
              'Laporan QRIS',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: AppTheme.inkColor(isDark),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ekspor CSV / Excel',
            onPressed: filtered.isEmpty || _exporting ? null : () => _export(filtered),
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: _all.isEmpty
          ? _buildEmpty(isDark)
          : SafeArea(
              top: false,
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                children: [
                  _buildFilters(isDark),
                  const SizedBox(height: 12),
                  _buildSummary(isDark, filtered),
                  const SizedBox(height: 12),
                  _buildChart(isDark, points),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Transaksi (${filtered.length})',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: AppTheme.inkColor(isDark),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          ExportService.summary(filtered),
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.mutedColor(isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 26),
                      child: Column(
                        children: [
                          Icon(Icons.filter_alt_off_rounded,
                              size: 34, color: AppTheme.mutedColor(isDark)),
                          const SizedBox(height: 10),
                          Text(
                            'Tidak ada transaksi di filter ini',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.mutedColor(isDark),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _preset = _RangePreset.all;
                              _priceRange = null;
                              _customRange = null;
                            }),
                            child: const Text('Reset filter',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    )
                  else
                    ...filtered.map((item) => _transactionTile(isDark, item)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: filtered.isEmpty || _exporting
                        ? null
                        : () => _export(filtered),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      'Ekspor ${filtered.length} transaksi (CSV / Excel)',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.qrisGreenDark,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmpty(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.qrisGreen.withOpacity(isDark ? 0.15 : 0.10),
              ),
              child: const Icon(Icons.insights_rounded,
                  size: 42, color: AppTheme.qrisGreen),
            ),
            const SizedBox(height: 20),
            Text(
              'Belum ada data nominal',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppTheme.inkColor(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Laporan hanya menghitung QRIS dinamis yang memiliki nominal '
              '(mis. QRIS dengan nominal Rp 25.000). Pindai lebih banyak QRIS '
              'untuk melihat grafik dan mengekspor data.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, height: 1.5, color: AppTheme.mutedColor(isDark)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilters(bool isDark) {
    final price = _effectivePriceRange;
    final maxAmount = _maxAmount;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_alt_rounded,
                  size: 15, color: AppTheme.mutedColor(isDark)),
              const SizedBox(width: 6),
              Text(
                'Filter',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                  color: AppTheme.mutedColor(isDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _presetChip('7 hari', _RangePreset.d7, isDark),
              _presetChip('30 hari', _RangePreset.d30, isDark),
              _presetChip('90 hari', _RangePreset.d90, isDark),
              _presetChip('Semua', _RangePreset.all, isDark),
              _presetChip(
                _preset == _RangePreset.custom && _customRange != null
                    ? '${_fullFmt.format(_customRange!.start)} – ${_fullFmt.format(_customRange!.end)}'
                    : 'Kustom',
                _RangePreset.custom,
                isDark,
                onTapOverride: _pickCustomRange,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Harga',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mutedColor(isDark),
                ),
              ),
              const Spacer(),
              Text(
                '${_money.format(price.start)} – ${_money.format(price.end)}',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.inkColor(isDark),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (maxAmount > 0)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: AppTheme.qrisGreen,
                inactiveTrackColor: AppTheme.borderColor(isDark),
                thumbColor: AppTheme.qrisGreen,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                rangeThumbShape: const RoundRangeSliderThumbShape(
                    enabledThumbRadius: 7),
              ),
              child: RangeSlider(
                min: 0,
                max: maxAmount,
                values: RangeValues(
                  price.start.clamp(0, maxAmount),
                  price.end.clamp(0, maxAmount),
                ),
                onChanged: (v) => setState(() => _priceRange = v),
              ),
            ),
        ],
      ),
    );
  }

  Widget _presetChip(
    String label,
    _RangePreset preset,
    bool isDark, {
    VoidCallback? onTapOverride,
  }) {
    final active = _preset == preset;
    return GestureDetector(
      onTap: onTapOverride ?? () => setState(() => _preset = preset),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppTheme.qrisGreen.withOpacity(isDark ? 0.22 : 0.12)
              : AppTheme.subtleBg(isDark),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? AppTheme.qrisGreen.withOpacity(0.55)
                : AppTheme.borderColor(isDark),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: active
                ? (isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark)
                : AppTheme.mutedColor(isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(bool isDark, List<ScannedItem> items) {
    final total = _total;
    final count = items.length;
    final avg = count == 0 ? 0.0 : total / count;

    return Row(
      children: [
        Expanded(
          child: _statCard(
            isDark,
            label: 'Total',
            value: _money.format(total),
            icon: Icons.payments_rounded,
            accent: AppTheme.qrisGreen,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            isDark,
            label: 'Transaksi',
            value: '$count',
            icon: Icons.receipt_long_rounded,
            accent: AppTheme.qrAmber,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard(
            isDark,
            label: 'Rata-rata',
            value: _money.format(avg),
            icon: Icons.trending_up_rounded,
            accent: AppTheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _statCard(
    bool isDark, {
    required String label,
    required String value,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppTheme.borderColor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: accent),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.mutedColor(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppTheme.inkColor(isDark),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(bool isDark, List<MapEntry<DateTime, double>> points) {
    if (points.isEmpty) {
      return const SizedBox.shrink();
    }

    final maxY = points
        .map((e) => e.value)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final chartMax = maxY <= 0 ? 1000.0 : maxY * 1.25;
    final labelStep = (points.length / 5).ceil().clamp(1, 12);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 14, 10),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderColor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 10),
            child: Text(
              _preset == _RangePreset.d90 || _preset == _RangePreset.all
                  ? 'Nominal per minggu'
                  : 'Nominal per hari',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkColor(isDark),
              ),
            ),
          ),
          SizedBox(
            height: 168,
            child: BarChart(
              BarChartData(
                maxY: chartMax,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: chartMax / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: AppTheme.borderColor(isDark),
                    strokeWidth: 0.8,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: chartMax / 4,
                      getTitlesWidget: (value, meta) {
                        if (value <= 0) return const SizedBox.shrink();
                        final short = value >= 1000000
                            ? '${(value / 1000000).toStringAsFixed(1)}jt'
                            : value >= 1000
                                ? '${(value / 1000).toStringAsFixed(0)}rb'
                                : value.toStringAsFixed(0);
                        return Text(
                          short,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.mutedColor(isDark),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= points.length) {
                          return const SizedBox.shrink();
                        }
                        if (idx % labelStep != 0 &&
                            idx != points.length - 1) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _dayFmt.format(points[idx].key),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.mutedColor(isDark),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => AppTheme.qrisGreenDark,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        _money.format(rod.toY),
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: List.generate(points.length, (i) {
                  final value = points[i].value;
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: value,
                        width: points.length > 20 ? 6 : 11,
                        color: value == 0
                            ? AppTheme.borderColor(isDark)
                            : AppTheme.qrisGreen,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _transactionTile(bool isDark, ScannedItem item) {
    final d = item.qrisDetails;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor(isDark)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.qrisGreen.withOpacity(isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.qr_code_2_rounded,
                size: 18, color: AppTheme.qrisGreen),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d?.merchantName.isNotEmpty == true
                      ? d!.merchantName
                      : 'QRIS Tanpa Nama',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.inkColor(isDark),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fullFmt.format(item.reportDate)} · ${d?.displayAcquirer ?? '-'}',
                  style: TextStyle(
                      fontSize: 10.5, color: AppTheme.mutedColor(isDark)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _money.format(d?.amount ?? 0),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
