import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/scanned_item.dart';
import '../utils/app_log.dart';

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
  ];

  /// Hanya QRIS yang punya nominal — itulah yang masuk laporan.
  static List<ScannedItem> reportable(List<ScannedItem> items) {
    final list = items
        .where((e) => e.isQRIS && (e.qrisDetails?.amount ?? 0) > 0)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  static List<List<String>> _rows(List<ScannedItem> items) {
    return items.map((item) {
      final d = item.qrisDetails;
      return [
        _dateFmt.format(item.addedAt),
        _timeFmt.format(item.addedAt),
        d?.merchantName ?? '',
        d?.merchantCity ?? '',
        d?.postalCode ?? '',
        d?.nmid ?? '',
        d?.displayAcquirer ?? '',
        d?.mcc ?? '',
        ((d?.amount ?? 0)).toStringAsFixed(0),
        (d?.isValidCRC ?? false) ? 'Ya' : 'Tidak',
        (d?.isDynamic ?? false) ? 'Dinamis' : 'Statis',
        item.fileName,
      ];
    }).toList();
  }

  // ------------------------------------------------------------------- CSV

  static String buildCsv(List<ScannedItem> items) {
    final buffer = StringBuffer();
    buffer.writeln(headers.map(_csvField).join(','));
    for (final row in _rows(items)) {
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

  static String buildExcelXml(List<ScannedItem> items) {
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
    final rows = _rows(items);
    for (final row in rows) {
      sb.writeln('   <Row>');
      for (var i = 0; i < row.length; i++) {
        final isNumber = i == 8; // kolom Nominal
        final type = isNumber ? 'Number' : 'String';
        sb.writeln('    <Cell><Data ss:Type="$type">'
            '${_xmlEscape(row[i])}</Data></Cell>');
      }
      sb.writeln('   </Row>');
    }

    // Total
    final total = items.fold<double>(
      0,
      (sum, e) => sum + (e.qrisDetails?.amount ?? 0),
    );
    sb.writeln('   <Row>');
    sb.writeln('    <Cell ss:StyleID="head"><Data ss:Type="String">TOTAL</Data></Cell>');
    for (var i = 1; i < headers.length; i++) {
      if (i == 8) {
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
  static Future<void> shareCsv(List<ScannedItem> items) async {
    try {
      final file = await _writeTemp('${_baseName()}.csv', buildCsv(items));
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Laporan QRIS Qristal (${items.length} transaksi)',
      );
    } catch (e) {
      AppLog.d('⚠️ Gagal ekspor CSV: $e');
      rethrow;
    }
  }

  /// Bagikan file Excel (.xls SpreadsheetML).
  static Future<void> shareExcel(List<ScannedItem> items) async {
    try {
      final file = await _writeTemp('${_baseName()}.xls', buildExcelXml(items));
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/vnd.ms-excel')],
        subject: 'Laporan QRIS Qristal (${items.length} transaksi)',
      );
    } catch (e) {
      AppLog.d('⚠️ Gagal ekspor Excel: $e');
      rethrow;
    }
  }

  /// Ringkasan teks untuk ditampilkan di UI.
  static String summary(List<ScannedItem> items) {
    final total = items.fold<double>(
      0,
      (sum, e) => sum + (e.qrisDetails?.amount ?? 0),
    );
    return '${items.length} transaksi · Rp ${_money.format(total)}';
  }
}
