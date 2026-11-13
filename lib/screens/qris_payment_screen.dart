import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../models/payment_record.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';

class QrisPaymentScreen extends StatefulWidget {
  const QrisPaymentScreen({super.key});

  @override
  State<QrisPaymentScreen> createState() => _QrisPaymentScreenState();
}

class _QrisPaymentScreenState extends State<QrisPaymentScreen> {
  static const int _paymentAmount = 15000;
  static const String _qrisAssetPath = 'assets/images/qris_payment.png';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedBank = 'BCA';
  final List<String> _bankOptions = [
    'BCA',
    'Mandiri',
    'BRI',
    'BNI',
    'GoPay',
    'OVO',
    'DANA',
    'ShopeePay',
    'Lainnya',
  ];

  File? _proofImageFile;
  bool _isSubmitting = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadCurrentUserData();
  }

  Future<void> _loadCurrentUserData() async {
    final user = await AuthService.getCurrentUser();
    if (user != null && mounted) {
      if (user.isGuest) {
        _nameController.text = 'Pengguna Tamu';
      } else {
        _nameController.text = user.name;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ─── PICK IMAGE ──────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (picked != null) {
        setState(() {
          _proofImageFile = File(picked.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memilih gambar: $e'),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
    }
  }

  void _showImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(
              top: BorderSide(color: AppTheme.borderColor(isDark), width: 1),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.borderColor(isDark),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Unggah Bukti Transfer',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: AppTheme.inkColor(isDark),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.subtleBg(isDark),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.borderColor(isDark)),
                    ),
                    child: Icon(Icons.photo_library_outlined, color: AppTheme.inkColor(isDark), size: 20),
                  ),
                  title: Text(
                    'Pilih dari Galeri',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkColor(isDark),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.subtleBg(isDark),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.borderColor(isDark)),
                    ),
                    child: const Icon(Icons.camera_alt_outlined, color: AppTheme.qrisGreen, size: 20),
                  ),
                  title: Text(
                    'Ambil dari Kamera',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.inkColor(isDark),
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickImage(ImageSource.camera);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── SHARE / SAVE QRIS ───────────────────────────────────────
  Future<void> _shareQrisImage() async {
    try {
      await Share.shareXFiles(
        [XFile(_qrisAssetPath)],
        text: 'QRIS Pembayaran QRIS Detector PRO (Rp $_paymentAmount)',
      );
    } catch (_) {
      await Share.share(
        'QRIS Pembayaran QRIS Detector PRO\nNominal: Rp $_paymentAmount\nNMID: ID2021095713545',
      );
    }
  }

  // ─── ZOOM QRIS MODAL ─────────────────────────────────────────
  void _showZoomedQris() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 4.0,
                child: Image.asset(
                  _qrisAssetPath,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xCC0A0E0D),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF232D29)),
              ),
              child: const Text(
                'Cubit untuk memperbesar QRIS',
                style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── SUBMIT FORM ─────────────────────────────────────────────
  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_proofImageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mohon lampirkan foto screenshot bukti transfer Anda.'),
          backgroundColor: AppTheme.qrAmber,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = await AuthService.getCurrentUser();
      final now = DateTime.now();
      final orderId = 'QRIS-${now.millisecondsSinceEpoch}';

      final record = PaymentRecord(
        id: orderId,
        userId: user?.id ?? 'guest',
        userName: _nameController.text.trim(),
        userEmail: user?.email ?? '-',
        senderBank: _selectedBank,
        amount: _paymentAmount,
        localProofPath: _proofImageFile?.path,
        status: 'PENDING',
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        createdAt: now,
      );

      // Simpan di riwayat lokal device
      await PaymentService.savePaymentLocal(record);

      // Kirim data ke Google Sheets & Drive (Apps Script)
      final success = await PaymentService.submitPayment(
        record: record,
        proofImagePath: _proofImageFile?.path,
      );

      if (!mounted) return;

      _showSuccessDialog(record, success);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi kesalahan saat memproses data: $e'),
          backgroundColor: AppTheme.dangerRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSuccessDialog(PaymentRecord record, bool uploadedToServer) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: AppTheme.cardColor(isDark),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.qrisGreen.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.qrisGreen,
                size: 40,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Konfirmasi Terkirim',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: AppTheme.inkColor(isDark),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bukti pembayaran Anda berhasil disimpan dan masuk antrean verifikasi.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.mutedColor(isDark),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.subtleBg(isDark),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderColor(isDark)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Order ID', record.id, isDark),
                  const SizedBox(height: 5),
                  _buildDetailRow('Pengirim', record.userName, isDark),
                  const SizedBox(height: 5),
                  _buildDetailRow('Metode', record.senderBank, isDark),
                  const SizedBox(height: 5),
                  _buildDetailRow('Nominal', 'Rp ${record.amount}', isDark, isHighlight: true),
                  const SizedBox(height: 5),
                  _buildDetailRow('Status', 'Menunggu Verifikasi', isDark),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  uploadedToServer ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
                  size: 15,
                  color: uploadedToServer ? AppTheme.qrisGreen : AppTheme.qrAmber,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    uploadedToServer
                        ? 'Tercatat di server & bukti tersimpan di Cloud.'
                        : 'Tersimpan lokal di HP (akan disinkron saat online).',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.mutedColor(isDark),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.qrisGreenDark,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pop(true);
              },
              child: const Text('Selesai', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isDark, {bool isHighlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.mutedColor(isDark)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w700,
            color: isHighlight
                ? (isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark)
                : AppTheme.inkColor(isDark),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  // ─── RIWAYAT PEMBAYARAN SHEET ────────────────────────────────
  Future<void> _showPaymentHistorySheet() async {
    final list = await PaymentService.getLocalPayments();
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          decoration: BoxDecoration(
            color: AppTheme.cardColor(isDark),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            border: Border(
              top: BorderSide(color: AppTheme.borderColor(isDark), width: 1),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.borderColor(isDark),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Riwayat Pembayaran Anda',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: AppTheme.inkColor(isDark),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Daftar bukti transaksi yang pernah Anda kirimkan.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.mutedColor(isDark),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 40, color: AppTheme.mutedColor(isDark)),
                            const SizedBox(height: 8),
                            Text(
                              'Belum ada riwayat pembayaran.',
                              style: TextStyle(color: AppTheme.mutedColor(isDark), fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, idx) {
                          final item = list[list.length - 1 - idx];
                          final isVerified = item.status == 'VERIFIED';
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.subtleBg(isDark),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isVerified
                                    ? AppTheme.qrisGreen.withOpacity(0.4)
                                    : AppTheme.borderColor(isDark),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isVerified
                                        ? AppTheme.qrisGreen.withOpacity(0.15)
                                        : AppTheme.qrAmber.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isVerified
                                        ? Icons.check_circle_rounded
                                        : Icons.hourglass_top_rounded,
                                    color: isVerified ? AppTheme.qrisGreen : AppTheme.qrAmber,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.id,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.5,
                                          color: AppTheme.inkColor(isDark),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Rp ${item.amount} • ${item.senderBank}',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: AppTheme.mutedColor(isDark),
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: isVerified
                                        ? AppTheme.qrisGreen.withOpacity(0.14)
                                        : AppTheme.qrAmber.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isVerified ? 'Aktif' : 'Diproses',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: isVerified
                                          ? (isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark)
                                          : AppTheme.qrAmber,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── BUILD SCREEN ────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Pembayaran QRIS PRO',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 17,
            letterSpacing: -0.3,
            color: AppTheme.inkColor(isDark),
          ),
        ),
        elevation: 0,
        backgroundColor: AppTheme.cardColor(isDark),
        actions: [
          IconButton(
            tooltip: 'Riwayat Pembayaran',
            icon: Icon(Icons.receipt_long_rounded, color: AppTheme.inkColor(isDark)),
            onPressed: _showPaymentHistorySheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. PRO Plan Benefit Ledger
            _buildProBanner(isDark),

            const SizedBox(height: 16),

            // 2. QRIS Stand Display Card
            _buildQrisCard(isDark),

            const SizedBox(height: 16),

            // 3. Panduan 4 Langkah Bayar
            _buildInstructionCard(isDark),

            const SizedBox(height: 18),

            // 4. Form Konfirmasi Pembayaran
            _buildConfirmationForm(isDark),
          ],
        ),
      ),
    );
  }

  // ─── WIDGET: PRO BANNER ──────────────────────────────────────
  Widget _buildProBanner(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.qrAmber.withOpacity(0.45),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.qrAmber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: AppTheme.qrAmber, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'QRIS Detector PRO',
                  style: TextStyle(
                    color: AppTheme.inkColor(isDark),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                decoration: BoxDecoration(
                  color: AppTheme.qrAmber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'SEKALI BAYAR',
                  style: TextStyle(
                    color: AppTheme.qrAmber,
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProFeatureRow(text: 'Hapus massal tanpa batasan kuota'),
              SizedBox(height: 5),
              _ProFeatureRow(text: '100% bebas semua iklan selamanya'),
              SizedBox(height: 5),
              _ProFeatureRow(text: 'Pemindaian galeri JIT prioritas'),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: AppTheme.borderColor(isDark)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Total Tagihan:',
                style: TextStyle(
                  color: AppTheme.mutedColor(isDark),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () {
                  Clipboard.setData(const ClipboardData(text: '15000'));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Nominal Rp 15.000 disalin ke clipboard!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.subtleBg(isDark),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.borderColor(isDark)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Rp 15.000',
                        style: TextStyle(
                          color: AppTheme.inkColor(isDark),
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.copy_rounded, color: AppTheme.mutedColor(isDark), size: 13),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── WIDGET: QRIS STAND CARD ─────────────────────────────────
  Widget _buildQrisCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor(isDark)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.qrisGreenDark.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.qr_code_2_rounded, color: AppTheme.qrisGreenDark, size: 18),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'QRIS Standar Nasional',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: AppTheme.inkColor(isDark),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.qrisGreen.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'STATIS',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: AppTheme.qrisGreen,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Foto QRIS Poster
          GestureDetector(
            onTap: _showZoomedQris,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: Image.asset(
                      _qrisAssetPath,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xCC0A0E0D),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in_rounded, color: Colors.white, size: 13),
                      SizedBox(width: 4),
                      Text('Perbesar', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Action Buttons: Simpan & Bagikan
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showZoomedQris,
                  icon: Icon(Icons.fullscreen_rounded, size: 16, color: AppTheme.inkColor(isDark)),
                  label: Text('Layar Penuh', style: TextStyle(fontSize: 12, color: AppTheme.inkColor(isDark), fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.borderColor(isDark)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareQrisImage,
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Bagi / Simpan', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.textDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── WIDGET: PANDUAN LANGKAH BAYAR ───────────────────────────
  Widget _buildInstructionCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.subtleBg(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cara Pembayaran:',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: AppTheme.inkColor(isDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildStepItem('1', 'Buka m-Banking (BCA, Mandiri, BRI, BNI) atau E-Wallet (GoPay, OVO, DANA, ShopeePay).', isDark),
          _buildStepItem('2', 'Pilih menu "Bayar via QRIS" -> scan langsung atau unggah foto QRIS di atas.', isDark),
          _buildStepItem('3', 'Ketik nominal transfer tepat Rp 15.000 lalu selesaikan pembayaran.', isDark),
          _buildStepItem('4', 'Screenshot bukti transaksi Anda lalu unggah pada form di bawah ini.', isDark),
        ],
      ),
    );
  }

  Widget _buildStepItem(String number, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.cardColor(isDark),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: AppTheme.borderColor(isDark)),
            ),
            child: Text(
              number,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: AppTheme.inkColor(isDark),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: AppTheme.mutedColor(isDark),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── WIDGET: FORM KONFIRMASI ─────────────────────────────────
  Widget _buildConfirmationForm(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardColor(isDark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderColor(isDark)),
      ),
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.assignment_turned_in_rounded, color: AppTheme.qrisGreenDark, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Formulir Konfirmasi Pembayaran',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: AppTheme.inkColor(isDark),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Nama Pengirim
            Text(
              'Nama Rekening / Pemilik Akun Pengirim *',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkColor(isDark),
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Contoh: Budi Santoso',
                hintStyle: TextStyle(color: AppTheme.mutedColor(isDark), fontSize: 13),
                prefixIcon: Icon(Icons.person_outline_rounded, size: 18, color: AppTheme.mutedColor(isDark)),
                filled: true,
                fillColor: AppTheme.subtleBg(isDark),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.borderColor(isDark)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.borderColor(isDark)),
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama pengirim wajib diisi' : null,
            ),

            const SizedBox(height: 14),

            // Bank / E-Wallet Pengirim
            Text(
              'Metode Pembayaran / Asal Bank *',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkColor(isDark),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _bankOptions.map((bank) {
                final isSelected = _selectedBank == bank;
                return ChoiceChip(
                  label: Text(
                    bank,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? (isDark ? const Color(0xFF34D399) : AppTheme.qrisGreenDark)
                          : AppTheme.inkColor(isDark),
                    ),
                  ),
                  selected: isSelected,
                  backgroundColor: AppTheme.subtleBg(isDark),
                  selectedColor: AppTheme.qrisGreen.withOpacity(0.15),
                  side: BorderSide(
                    color: isSelected ? AppTheme.qrisGreen : AppTheme.borderColor(isDark),
                    width: isSelected ? 1.4 : 1.0,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  showCheckmark: false,
                  onSelected: (val) {
                    if (val) setState(() => _selectedBank = bank);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 14),

            // Catatan Opsional
            Text(
              'Catatan Tambahan (Opsional)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkColor(isDark),
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                hintText: 'Nomor referensi m-Banking / keterangan transfer',
                hintStyle: TextStyle(color: AppTheme.mutedColor(isDark), fontSize: 13),
                prefixIcon: Icon(Icons.note_alt_outlined, size: 18, color: AppTheme.mutedColor(isDark)),
                filled: true,
                fillColor: AppTheme.subtleBg(isDark),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.borderColor(isDark)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppTheme.borderColor(isDark)),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Upload Bukti Transfer Box
            Text(
              'Lampiran Bukti Transfer (Screenshot) *',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.inkColor(isDark),
              ),
            ),
            const SizedBox(height: 8),

            if (_proofImageFile == null)
              InkWell(
                onTap: _showImageSourcePicker,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.subtleBg(isDark),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.borderColor(isDark),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppTheme.cardColor(isDark),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_upload_outlined, color: AppTheme.primary, size: 22),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Ketuk untuk Unggah Screenshot Bukti Bayar',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Format JPG, PNG (Maks 5MB)',
                        style: TextStyle(fontSize: 10.5, color: AppTheme.mutedColor(isDark)),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.subtleBg(isDark),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.qrisGreen.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        _proofImageFile!,
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: AppTheme.qrisGreen, size: 15),
                              SizedBox(width: 4),
                              Text('Foto Siap Dikirim', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _proofImageFile!.path.split('/').last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: AppTheme.mutedColor(isDark)),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _showImageSourcePicker,
                      child: const Text('Ganti', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.dangerRed, size: 19),
                      onPressed: () => setState(() => _proofImageFile = null),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // Tombol Kirim Konfirmasi
            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.qrisGreenDark,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Mengirim ke Google Sheets & Drive...',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Kirim Konfirmasi Pembayaran',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProFeatureRow extends StatelessWidget {
  final String text;
  const _ProFeatureRow({required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_rounded, color: AppTheme.qrAmber, size: 13),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppTheme.inkColor(isDark),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
