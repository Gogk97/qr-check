import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scanned_item.dart';
import '../utils/app_log.dart';

/// Satu baris laporan: satu QRIS unik beserta semua foto yang menampilkannya.
///
/// QRIS yang sama bisa terfoto lebih dari sekali (mis. dua screenshot dari
/// gambar yang sama). Laporan menghitung **satu** QRIS per baris agar total dan
/// chart tidak dobel, tetapi jumlah fotonya tetap dilaporkan.
class ReportEntry {
  const ReportEntry({required this.item, required this.photos});

  /// Foto perwakilan (yang paling baru).
  final ScannedItem item;

  /// Semua foto dengan isi QRIS identik, urut terbaru → terlama.
  final List<ScannedItem> photos;

  int get photoCount => photos.length;
  bool get isDuplicate => photos.length > 1;
  double get amount => item.qrisDetails?.amount ?? 0;
  DateTime get date => item.reportDate;

  /// Foto lain yang bukan perwakilan (untuk ditampilkan di detail).
  List<ScannedItem> get otherPhotos => photos.skip(1).toList();
}

/// Ekspor data QRIS ke format yang bisa dibuka di Excel / Google Sheets.
///
/// Dua format tanpa dependensi tambahan:
/// - **CSV** (UTF-8 + BOM) — universal, langsung rapi di Excel.
/// - **Excel XML (SpreadsheetML)** — file `.xls` asli yang dikenali Excel
///   sebagai workbook (bukan teks mentah), lengkap dengan tipe angka.
class ExportService {
  ExportService._();

  static final DateFormat _dateFmt = DateFormat('yyyy-MM-dd');
  static final DateFormat _timeFmt = DateFormat('HH:mm');
  static final DateFormat _stampFmt = DateFormat('yyyyMMdd_HHmm');
  static final NumberFormat _money = NumberFormat('#,##0', 'id_ID');

  static const int _amountColumn = 8;

  static const List<String> headers = [
    'Tanggal',
    'Jam',
    'Merchant',
    'Kota',
    'Kode Pos',
    'NMID',
    'Penyelenggara',
    'MCC',
    'Nominal (Rp)',
    'CRC Valid',
    'Tipe',
    'Nama File',
    'Jumlah Foto',
  ];

  // ------------------------------------------------------------ deduplikasi

  /// Identitas QRIS: isi payload QR.
  ///
  /// Dua foto dari QR yang sama menghasilkan payload identik, jadi payload
  /// adalah kunci paling tepat. Bila payload tidak tersimpan (data lama),
  /// fallback ke kombinasi NMID + nominal + merchant.
  static String fingerprint(ScannedItem item) {
    final raw = (item.rawContent ?? '').trim().toUpperCase();
    if (raw.isNotEmpty) return raw;
    final d = item.qrisDetails;
    return '${d?.nmid ?? ''}|${(d?.amount ?? 0).toStringAsFixed(0)}|'
        '${(d?.merchantName ?? '').trim().toUpperCase()}';
  }

  /// Hanya QRIS yang punya nominal — itulah yang masuk laporan.
  ///
  /// QRIS identik digabung jadi satu [ReportEntry] (foto terbaru jadi
  /// perwakilan), lalu diurutkan dari tanggal terbaru.
  static List<ReportEntry> reportEntries(List<ScannedItem> items) {
    final base = items
        .where((e) => e.isQRIS && (e.qrisDetails?.amount ?? 0) > 0)
        .toList()
      ..sort((a, b) => b.reportDate.compareTo(a.reportDate));

    final grouped = <String, List<ScannedItem>>{};
    final order = <String>[];
    for (final item in base) {
      final key = fingerprint(item);
      final bucket = grouped[key];
      if (bucket == null) {
        grouped[key] = [item];
        order.add(key);
      } else {
        bucket.add(item);
      }
    }

    final entries = order
        .map((k) => ReportEntry(item: grouped[k]!.first, photos: grouped[k]!))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  /// Versi ringkas: satu item per QRIS unik (tanpa info jumlah foto).
  static List<ScannedItem> reportable(List<ScannedItem> items) =>
      reportEntries(items).map((e) => e.item).toList();

  /// Jumlah grup QRIS yang punya lebih dari satu foto, dan total foto sisanya.
  static ({int groups, int extraPhotos}) duplicateStats(
      List<ReportEntry> entries) {
    var groups = 0;
    var extra = 0;
    for (final e in entries) {
      if (e.isDuplicate) {
        groups++;
        extra += e.photoCount - 1;
      }
    }
    return (groups: groups, extraPhotos: extra);
  }

  static double totalOf(List<ReportEntry> entries) =>
      entries.fold<double>(0, (sum, e) => sum + e.amount);

  // ------------------------------------------------------------------ rows

  static List<List<String>> _rows(List<ReportEntry> entries) {
    return entries.map((entry) {
      final item = entry.item;
      final d = item.qrisDetails;
      return [
        _dateFmt.format(item.reportDate),
        _timeFmt.format(item.reportDate),
        d?.merchantName ?? '',
        d?.merchantCity ?? '',
        d?.postalCode ?? '',
        d?.nmid ?? '',
        d?.displayAcquirer ?? '',
        d?.mcc ?? '',
        entry.amount.toStringAsFixed(0),
        (d?.isValidCRC ?? false) ? 'Ya' : 'Tidak',
        (d?.isDynamic ?? false) ? 'Dinamis' : 'Statis',
        item.fileName,
        entry.photoCount.toString(),
      ];
    }).toList();
  }

  // ------------------------------------------------------------------- CSV

  static String buildCsv(List<ReportEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_csvField).join(','));
    for (final row in _rows(entries)) {
      buffer.writeln(row.map(_csvField).join(','));
    }
    // BOM agar Excel membaca UTF-8 dengan benar.
    return '\uFEFF$buffer';
  }

  static String _csvField(String value) {
    final needsQuote = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    final escaped = value.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }

  // ------------------------------------------------------- Excel XML (.xls)

  static String buildExcelXml(List<ReportEntry> entries) {
    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln('<?mso-application progid="Excel.Sheet"?>');
    sb.writeln('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"');
    sb.writeln(' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">');
    sb.writeln(' <Styles>');
    sb.writeln('  <Style ss:ID="head"><Font ss:Bold="1"/>'
        '<Interior ss:Color="#DDEBE4" ss:Pattern="Solid"/></Style>');
    sb.writeln(' </Styles>');
    sb.writeln(' <Worksheet ss:Name="Laporan QRIS">');
    sb.writeln('  <Table>');

    // Header
    sb.writeln('   <Row>');
    for (final h in headers) {
      sb.writeln('    <Cell ss:StyleID="head"><Data ss:Type="String">'
          '${_xmlEscape(h)}</Data></Cell>');
    }
    sb.writeln('   </Row>');

    // Baris data
    final rows = _rows(entries);
    for (final row in rows) {
      sb.writeln('   <Row>');
      for (var i = 0; i < row.length; i++) {
        final isNumber = i == _amountColumn;
        final type = isNumber ? 'Number' : 'String';
        sb.writeln('    <Cell><Data ss:Type="$type">'
            '${_xmlEscape(row[i])}</Data></Cell>');
      }
      sb.writeln('   </Row>');
    }

    // Total
    final total = totalOf(entries);
    sb.writeln('   <Row>');
    sb.writeln('    <Cell ss:StyleID="head"><Data ss:Type="String">TOTAL</Data></Cell>');
    for (var i = 1; i < headers.length; i++) {
      if (i == _amountColumn) {
        sb.writeln('    <Cell ss:StyleID="head"><Data ss:Type="Number">'
            '${total.toStringAsFixed(0)}</Data></Cell>');
      } else {
        sb.writeln('    <Cell ss:StyleID="head"><Data ss:Type="String"></Data></Cell>');
      }
    }
    sb.writeln('   </Row>');

    sb.writeln('  </Table>');
    sb.writeln(' </Worksheet>');
    sb.writeln('</Workbook>');
    return sb.toString();
  }

  static String _xmlEscape(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  // ---------------------------------------------------------------- sharing

  static Future<File> _writeTemp(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(content, flush: true);
    return file;
  }

  static String _baseName() =>
      'qristal_qris_${_stampFmt.format(DateTime.now())}';

  /// Bagikan CSV ke aplikasi lain (WhatsApp, Gmail, Drive, Excel).
  static Future<void> shareCsv(List<ReportEntry> entries) async {
    try {
      final file = await _writeTemp('${_baseName()}.csv', buildCsv(entries));
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Laporan QRIS Qristal (${entries.length} transaksi)',
      );
    } catch (e) {
      AppLog.d('⚠️ Gagal ekspor CSV: $e');
      rethrow;
    }
  }

  /// Bagikan file Excel (.xls SpreadsheetML).
  static Future<void> shareExcel(List<ReportEntry> entries) async {
    try {
      final file =
          await _writeTemp('${_baseName()}.xls', buildExcelXml(entries));
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/vnd.ms-excel')],
        subject: 'Laporan QRIS Qristal (${entries.length} transaksi)',
      );
    } catch (e) {
      AppLog.d('⚠️ Gagal ekspor Excel: $e');
      rethrow;
    }
  }

  /// Ringkasan teks untuk ditampilkan di UI.
  static String summary(List<ReportEntry> entries) {
    final total = totalOf(entries);
    return '${entries.length} transaksi · Rp ${_money.format(total)}';
  }
}
