import '../models/scanned_item.dart';
import 'qris_parser.dart';

/// Tingkat keparahan satu temuan audit.
enum AuditSeverity { critical, warning, info }

/// Satu temuan hasil audit QRIS.
class AuditFinding {
  const AuditFinding({
    required this.code,
    required this.title,
    required this.detail,
    required this.severity,
    this.penalty = 0,
  });

  /// Kode stabil untuk testing/analitik, mis. `CRC_INVALID`.
  final String code;
  final String title;
  final String detail;
  final AuditSeverity severity;

  /// Pengurangan skor (0–100).
  final int penalty;
}

/// Kesimpulan audit.
enum AuditVerdict { safe, review, suspicious }

/// Hasil audit satu QRIS.
class QrisAuditResult {
  const QrisAuditResult({
    required this.score,
    required this.verdict,
    required this.findings,
    required this.crcValid,
    required this.structureValid,
    required this.nmid,
    required this.amount,
    required this.isDynamic,
  });

  final int score;
  final AuditVerdict verdict;
  final List<AuditFinding> findings;
  final bool crcValid;
  final bool structureValid;
  final String nmid;
  final double? amount;
  final bool isDynamic;

  bool get isSafe => verdict == AuditVerdict.safe;

  int get criticalCount =>
      findings.where((f) => f.severity == AuditSeverity.critical).length;
  int get warningCount =>
      findings.where((f) => f.severity == AuditSeverity.warning).length;

  String get headline => switch (verdict) {
        AuditVerdict.safe => 'QRIS terlihat aman',
        AuditVerdict.review => 'Perlu dicek',
        AuditVerdict.suspicious => 'Mencurigakan',
      };

  /// Temuan paling berat lebih dulu.
  List<AuditFinding> get sortedFindings {
    final list = [...findings];
    list.sort((a, b) {
      final bySeverity = a.severity.index.compareTo(b.severity.index);
      if (bySeverity != 0) return bySeverity;
      return b.penalty.compareTo(a.penalty);
    });
    return list;
  }
}

/// Audit struktur & keamanan payload QRIS (EMVCo MPM).
///
/// Semua pemeriksaan dilakukan lokal dari isi payload — tidak ada panggilan
/// jaringan, tidak ada data yang keluar dari perangkat.
class QrisAuditService {
  QrisAuditService._();

  // Tag EMVCo yang relevan untuk QRIS.
  static const _tagPayloadFormat = '00';
  static const _tagInitiation = '01';
  static const _tagNmid = '51';
  static const _tagMcc = '52';
  static const _tagCurrency = '53';
  static const _tagAmount = '54';
  static const _tagCountry = '58';
  static const _tagMerchant = '59';
  static const _tagCity = '60';
  static const _tagCrc = '63';

  /// Audit satu item.
  ///
  /// [nmidIndex] opsional: peta NMID → kumpulan nama merchant dari seluruh
  /// koleksi. Dipakai untuk mendeteksi satu NMID yang dipakai beberapa merchant
  /// (indikasi payload diedit).
  static QrisAuditResult audit(
    ScannedItem item, {
    Map<String, Set<String>>? nmidIndex,
  }) {
    final raw = (item.rawContent ?? '').trim();
    if (raw.isEmpty) {
      return QrisAuditResult(
        score: 0,
        verdict: AuditVerdict.suspicious,
        findings: const [
          AuditFinding(
            code: 'NO_PAYLOAD',
            title: 'Isi QR tidak tersimpan',
            detail:
                'Payload QRIS tidak ada, jadi keasliannya tidak bisa diperiksa.',
            severity: AuditSeverity.critical,
            penalty: 100,
          ),
        ],
        crcValid: false,
        structureValid: false,
        nmid: item.qrisDetails?.nmid ?? '',
        amount: item.qrisDetails?.amount,
        isDynamic: item.qrisDetails?.isDynamic ?? false,
      );
    }
    return auditPayload(raw, nmidIndex: nmidIndex);
  }

  /// Audit langsung dari string payload (dipakai juga oleh test).
  static QrisAuditResult auditPayload(
    String payload, {
    Map<String, Set<String>>? nmidIndex,
  }) {
    final findings = <AuditFinding>[];
    final clean = payload.trim();

    // ---------------------------------------------------------- struktur TLV
    final parsed = _walkTlv(clean, findings);
    final structureValid = findings.every((f) => f.code != 'TLV_BROKEN');

    final payloadFormat = parsed[_tagPayloadFormat] ?? '';
    final initiation = parsed[_tagInitiation] ?? '';
    final tag51 = parsed[_tagNmid] ?? '';
    final nmid = _extractNmid(tag51);
    final currency = parsed[_tagCurrency] ?? '';
    final amountRaw = parsed[_tagAmount] ?? '';
    final country = parsed[_tagCountry] ?? '';
    final merchant = (parsed[_tagMerchant] ?? '').trim();
    final city = (parsed[_tagCity] ?? '').trim();
    final mcc = (parsed[_tagMcc] ?? '').trim();
    final crc = parsed[_tagCrc] ?? '';

    // ------------------------------------------------------------ bukan QRIS
    if (payloadFormat != '01') {
      findings.add(const AuditFinding(
        code: 'NOT_QRIS',
        title: 'Bukan payload QRIS standar',
        detail:
            'Tag 00 (versi payload) tidak bernilai "01". Kemungkinan ini QR '
            'biasa, bukan QRIS EMVCo.',
        severity: AuditSeverity.critical,
        penalty: 30,
      ));
    }

    // ------------------------------------------------------------------- CRC
    var crcValid = false;
    if (crc.isEmpty) {
      findings.add(const AuditFinding(
        code: 'CRC_MISSING',
        title: 'CRC tidak ada',
        detail: 'Tag 63 (checksum) tidak ditemukan, payload tidak bisa '
            'diverifikasi keutuhannya.',
        severity: AuditSeverity.critical,
        penalty: 25,
      ));
    } else {
      final withoutCrc = clean.substring(0, clean.length - 4);
      final expected = QRISParser.calculateCRC16(withoutCrc).toUpperCase();
      crcValid = expected == crc.toUpperCase();
      if (!crcValid) {
        findings.add(AuditFinding(
          code: 'CRC_INVALID',
          title: 'Checksum tidak cocok',
          detail:
              'CRC seharusnya $expected tetapi tertulis ${crc.toUpperCase()}. '
              'Isi QRIS kemungkinan sudah diubah setelah dibuat.',
          severity: AuditSeverity.critical,
          penalty: 45,
        ));
      }
    }

    // ------------------------------------------------------------------ NMID
    if (nmid.isEmpty) {
      findings.add(const AuditFinding(
        code: 'NMID_MISSING',
        title: 'NMID tidak ada',
        detail: 'Tag 51 (National Merchant ID) wajib ada pada QRIS.',
        severity: AuditSeverity.critical,
        penalty: 20,
      ));
    } else if (!_isValidNmid(nmid)) {
      findings.add(AuditFinding(
        code: 'NMID_INVALID',
        title: 'Format NMID tidak wajar',
        detail:
            'NMID "$nmid" tidak mengikuti pola ID + 13–15 digit. QRIS dengan '
            'NMID tidak wajar sering berasal dari penyedia tidak resmi.',
        severity: AuditSeverity.critical,
        penalty: 15,
      ));
    }

    if (nmid.isNotEmpty && nmidIndex != null) {
      final merchants = nmidIndex[nmid] ?? const <String>{};
      if (merchants.length > 1) {
        findings.add(AuditFinding(
          code: 'NMID_CONFLICT',
          title: 'NMID dipakai beberapa merchant',
          detail:
              'NMID yang sama muncul dengan ${merchants.length} nama merchant '
              'berbeda (${merchants.take(3).join(', ')}). Periksa apakah ada '
              'payload yang diedit.',
          severity: AuditSeverity.critical,
          penalty: 25,
        ));
      }
    }

    // -------------------------------------------------------- mata uang/negara
    if (currency.isNotEmpty && currency != '360') {
      findings.add(AuditFinding(
        code: 'CURRENCY_NOT_IDR',
        title: 'Mata uang bukan Rupiah',
        detail: 'Tag 53 bernilai $currency, seharusnya 360 (IDR).',
        severity: AuditSeverity.critical,
        penalty: 25,
      ));
    }
    if (country.isNotEmpty && country.toUpperCase() != 'ID') {
      findings.add(AuditFinding(
        code: 'COUNTRY_NOT_ID',
        title: 'Negara bukan Indonesia',
        detail: 'Tag 58 bernilai $country, seharusnya ID.',
        severity: AuditSeverity.critical,
        penalty: 20,
      ));
    }

    // ----------------------------------------------------------------- nominal
    double? amount;
    if (amountRaw.isNotEmpty) {
      amount = double.tryParse(amountRaw.replaceAll(',', '.'));
      if (amount == null || amount <= 0) {
        findings.add(AuditFinding(
          code: 'AMOUNT_INVALID',
          title: 'Nominal tidak valid',
          detail: 'Tag 54 berisi "$amountRaw" yang bukan angka positif.',
          severity: AuditSeverity.warning,
          penalty: 15,
        ));
        amount = null;
      }
    }

    final isDynamic = initiation == '12';
    if (!isDynamic && amountRaw.isNotEmpty) {
      findings.add(const AuditFinding(
        code: 'STATIC_WITH_AMOUNT',
        title: 'QRIS statis mencantumkan nominal',
        detail:
            'QRIS statis biasanya tanpa nominal. Nominal pada QRIS statis bisa '
            'berarti tag 54 ditambahkan pihak lain.',
        severity: AuditSeverity.warning,
        penalty: 10,
      ));
    }
    if (isDynamic && amountRaw.isEmpty) {
      findings.add(const AuditFinding(
        code: 'DYNAMIC_WITHOUT_AMOUNT',
        title: 'QRIS dinamis tanpa nominal',
        detail: 'QRIS dinamis biasanya membawa nominal pembayaran.',
        severity: AuditSeverity.info,
      ));
    }

    // ---------------------------------------------------------------- merchant
    if (merchant.isEmpty) {
      findings.add(const AuditFinding(
        code: 'MERCHANT_MISSING',
        title: 'Nama merchant kosong',
        detail: 'Tag 59 wajib berisi nama merchant.',
        severity: AuditSeverity.warning,
        penalty: 10,
      ));
    } else if (RegExp(r'[<>{}\\|^~]').hasMatch(merchant)) {
      findings.add(AuditFinding(
        code: 'MERCHANT_ODD_CHARS',
        title: 'Nama merchant mengandung karakter aneh',
        detail: 'Nama "$merchant" memuat karakter yang tidak lazim pada QRIS.',
        severity: AuditSeverity.warning,
        penalty: 10,
      ));
    }
    if (mcc.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(mcc)) {
      findings.add(AuditFinding(
        code: 'MCC_INVALID',
        title: 'Kode kategori merchant tidak wajar',
        detail: 'Tag 52 berisi "$mcc", seharusnya 4 digit (contoh 5812).',
        severity: AuditSeverity.warning,
        penalty: 5,
      ));
    }
    if (city.isEmpty) {
      findings.add(const AuditFinding(
        code: 'CITY_MISSING',
        title: 'Kota merchant kosong',
        detail: 'Tag 60 tidak diisi — QRIS tetap sah, tetapi tidak lengkap.',
        severity: AuditSeverity.info,
      ));
    }

    // ------------------------------------------------------------------ skor
    final penalty = findings.fold<int>(0, (sum, f) => sum + f.penalty);
    final score = (100 - penalty).clamp(0, 100);
    final verdict = score >= 85
        ? AuditVerdict.safe
        : score >= 60
            ? AuditVerdict.review
            : AuditVerdict.suspicious;

    return QrisAuditResult(
      score: score,
      verdict: verdict,
      findings: findings,
      crcValid: crcValid,
      structureValid: structureValid,
      nmid: nmid,
      amount: amount,
      isDynamic: isDynamic,
    );
  }

  /// Audit seluruh koleksi, sekaligus mendeteksi konflik NMID.
  static Map<String, QrisAuditResult> auditAll(List<ScannedItem> items) {
    final index = buildNmidIndex(items);
    return {
      for (final item in items) item.id: audit(item, nmidIndex: index),
    };
  }

  /// Peta NMID → nama merchant yang memakainya.
  static Map<String, Set<String>> buildNmidIndex(List<ScannedItem> items) {
    final index = <String, Set<String>>{};
    for (final item in items) {
      final nmid = (item.qrisDetails?.nmid ?? '').trim();
      if (nmid.isEmpty) continue;
      final merchant = (item.qrisDetails?.merchantName ?? '').trim();
      index.putIfAbsent(nmid, () => <String>{}).add(merchant);
    }
    return index;
  }

  /// Item yang butuh perhatian (tidak aman), paling buruk lebih dulu.
  static List<MapEntry<ScannedItem, QrisAuditResult>> needsReview(
      List<ScannedItem> items) {
    final results = auditAll(items);
    final list = items
        .where((e) => results[e.id]?.isSafe == false)
        .map((e) => MapEntry(e, results[e.id]!))
        .toList()
      ..sort((a, b) => a.value.score.compareTo(b.value.score));
    return list;
  }

  static int countNeedsReview(List<ScannedItem> items) =>
      needsReview(items).length;

  // ------------------------------------------------------------------ helper

  /// Tag 51 pada QRIS berisi sub-TLV: `00` penyelenggara, `02` NMID,
  /// `03` kategori. Ambil nilai sub-tag tertentu.
  static String _extractSubTag(String tag51, String subTag) {
    final sub = _parseSubTlv(tag51);
    return (sub[subTag] ?? '').trim();
  }

  /// NMID sesungguhnya: sub-tag `02` di dalam tag 51.
  ///
  /// Beberapa penerbit lama menaruh NMID langsung di tag 51 tanpa sub-TLV —
  /// keduanya didukung.
  static String _extractNmid(String tag51) {
    final nested = _extractSubTag(tag51, '02');
    if (nested.isNotEmpty) return nested;
    final direct = tag51.trim();
    if (direct.toUpperCase().startsWith('ID')) return direct;
    return direct;
  }

  static Map<String, String> _parseSubTlv(String value) {
    final tags = <String, String>{};
    var index = 0;
    while (index + 4 <= value.length) {
      final tag = value.substring(index, index + 2);
      final len = int.tryParse(value.substring(index + 2, index + 4));
      if (len == null || index + 4 + len > value.length) break;
      tags[tag] = value.substring(index + 4, index + 4 + len);
      index += 4 + len;
    }
    return tags;
  }

  static bool _isValidNmid(String nmid) {
    final upper = nmid.toUpperCase();
    if (!upper.startsWith('ID')) return false;
    final digits = upper.substring(2);
    if (!RegExp(r'^\d+$').hasMatch(digits)) return false;
    return digits.length >= 13 && digits.length <= 15;
  }

  /// Telusuri TLV secara ketat; catat masalah struktur ke [findings].
  static Map<String, String> _walkTlv(String payload, List<AuditFinding> findings) {
    final tags = <String, String>{};
    final duplicates = <String>{};
    var index = 0;

    while (index < payload.length) {
      // Tag 63 (CRC) adalah elemen terakhir dengan panjang 04.
      if (index + 4 > payload.length) {
        findings.add(const AuditFinding(
          code: 'TLV_BROKEN',
          title: 'Struktur payload terpotong',
          detail: 'Ada sisa karakter yang tidak membentuk tag-length-value.',
          severity: AuditSeverity.critical,
          penalty: 20,
        ));
        break;
      }

      final tag = payload.substring(index, index + 2);
      final lenStr = payload.substring(index + 2, index + 4);
      final len = int.tryParse(lenStr);

      if (!RegExp(r'^\d{2}$').hasMatch(tag) || len == null) {
        findings.add(AuditFinding(
          code: 'TLV_BROKEN',
          title: 'Struktur payload tidak valid',
          detail: 'Tag/panjang pada posisi $index bukan angka.',
          severity: AuditSeverity.critical,
          penalty: 20,
        ));
        break;
      }

      if (index + 4 + len > payload.length) {
        findings.add(AuditFinding(
          code: 'TLV_BROKEN',
          title: 'Struktur payload terpotong',
          detail: 'Tag $tag menyatakan panjang $len tetapi data tidak cukup.',
          severity: AuditSeverity.critical,
          penalty: 20,
        ));
        break;
      }

      final value = payload.substring(index + 4, index + 4 + len);
      if (tags.containsKey(tag)) duplicates.add(tag);
      tags[tag] = value;
      index += 4 + len;
    }

    if (duplicates.isNotEmpty) {
      findings.add(AuditFinding(
        code: 'TLV_DUPLICATE',
        title: 'Tag ganda pada payload',
        detail: 'Tag ${duplicates.join(', ')} muncul lebih dari sekali. '
            'QRIS standar hanya boleh memuat satu nilai per tag.',
        severity: AuditSeverity.warning,
        penalty: 10,
      ));
    }

    return tags;
  }
}
