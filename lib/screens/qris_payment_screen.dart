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
          backgroundColor: Colors.red,
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
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: Colors.grey.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Unggah Bukti Transfer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE0E7FF),
                    child: Icon(Icons.photo_library_rounded, color: AppTheme.primary),
                  ),
                  title: const Text('Pilih dari Galeri'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickImage(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFDCFCE7),
                    child: Icon(Icons.camera_alt_rounded, color: AppTheme.qrisGreenDark),
                  ),
                  title: const Text('Ambil dari Kamera'),
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
      // Fallback pesan jika asset sharing langsung terhalang
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
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 3.5,
                child: Image.asset(
                  _qrisAssetPath,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Cubit untuk memperbesar QRIS',
              style: TextStyle(color: Colors.white70, fontSize: 13),
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
          content: Text('⚠️ Mohon lampirkan foto screenshot bukti transfer Anda.'),
          backgroundColor: Colors.orange,
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
          backgroundColor: Colors.red,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.qrisGreenDark.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.qrisGreenDark,
                size: 48,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Konfirmasi Terkirim!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bukti pembayaran Anda berhasil disimpan.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Order ID:', record.id),
                  const SizedBox(height: 4),
                  _buildDetailRow('Pengirim:', record.userName),
                  const SizedBox(height: 4),
                  _buildDetailRow('Bank/E-Wallet:', record.senderBank),
                  const SizedBox(height: 4),
                  _buildDetailRow('Nominal:', 'Rp ${record.amount}'),
                  const SizedBox(height: 4),
                  _buildDetailRow('Status:', 'Menunggu Verifikasi'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  uploadedToServer ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
                  size: 16,
                  color: uploadedToServer ? AppTheme.qrisGreenDark : Colors.orange,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    uploadedToServer
                        ? 'Tercatat di Server & Bukti tersimpan di Cloud Supabase.'
                        : 'Tersimpan lokal di HP (akan disinkron saat online).',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop(); // Tutup dialog
              Navigator.of(context).pop(true); // Kembali ke Home
            },
            child: const Text('Selesai', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Riwayat Pembayaran Anda',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Daftar bukti transaksi yang pernah Anda kirimkan.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            const Text('Belum ada riwayat pembayaran.', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, idx) {
                          final item = list[list.length - 1 - idx]; // Newest first
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: item.status == 'VERIFIED'
                                        ? AppTheme.qrisGreenDark.withOpacity(0.15)
                                        : Colors.orange.withOpacity(0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    item.status == 'VERIFIED'
                                        ? Icons.check_circle_rounded
                                        : Icons.hourglass_top_rounded,
                                    color: item.status == 'VERIFIED'
                                        ? AppTheme.qrisGreenDark
                                        : Colors.orange,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.id,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Rp ${item.amount} • ${item.senderBank}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: item.status == 'VERIFIED'
                                        ? AppTheme.qrisGreenDark.withOpacity(0.15)
                                        : Colors.orange.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    item.status == 'VERIFIED' ? 'Aktif' : 'Diproses',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: item.status == 'VERIFIED'
                                          ? AppTheme.qrisGreenDark
                                          : Colors.orange,
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

  // ─── WEBHOOK SETTINGS DIALOG (DIHAPUS - URL SEKARANG HARDCODED) ──

  // ─── BUILD SCREEN ────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Pembayaran QRIS PRO',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'Riwayat Pembayaran',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: _showPaymentHistorySheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. PRO Plan Benefit Banner
            _buildProBanner(isDark),

            const SizedBox(height: 18),

            // 2. QRIS Stand Display Card
            _buildQrisCard(isDark),

            const SizedBox(height: 18),

            // 3. Panduan 3 Langkah Bayar
            _buildInstructionCard(isDark),

            const SizedBox(height: 22),

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
        gradient: const LinearGradient(
          colors: [Color(0xFFD97706), Color(0xFFF59E0B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
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
                  color: Colors.white.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'QRIS Detector PRO',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'SEKALI BAYAR',
                  style: TextStyle(
                    color: Color(0xFFD97706),
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
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
              SizedBox(height: 4),
              _ProFeatureRow(text: '100% bebas semua iklan selamanya'),
              SizedBox(height: 4),
              _ProFeatureRow(text: 'Pemindaian galeri JIT prioritas'),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Total Tagihan:',
                style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
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
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Rp 15.000',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.copy_rounded, color: Colors.white70, size: 13),
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
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.qr_code_2_rounded, color: AppTheme.qrisGreenDark, size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'QRIS Standar Nasional',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'STATIS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.green,
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
                  borderRadius: BorderRadius.circular(14),
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
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text('Perbesar', style: TextStyle(color: Colors.white, fontSize: 11)),
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
                  icon: const Icon(Icons.fullscreen_rounded, size: 16),
                  label: const Text('Layar Penuh', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _shareQrisImage,
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: const Text('Bagi / Simpan', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cara Mudah Membayar:',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildStepItem('1', 'Buka m-Banking (BCA, Mandiri, BRI, BNI) atau E-Wallet (GoPay, OVO, DANA, ShopeePay).'),
          _buildStepItem('2', 'Pilih menu "Bayar via QRIS" -> scan langsung atau unggah foto QRIS di atas.'),
          _buildStepItem('3', 'Ketik nominal transfer tepat Rp 15.000 lalu selesaikan pembayaran.'),
          _buildStepItem('4', 'Screenshot bukti transaksi Anda lalu unggah pada form di bawah ini.'),
        ],
      ),
    );
  }

  Widget _buildStepItem(String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 9,
            backgroundColor: AppTheme.primary.withOpacity(0.2),
            child: Text(
              number,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12, height: 1.3)),
          ),
        ],
      ),
    );
  }

  // ─── WIDGET: FORM KONFIRMASI ─────────────────────────────────
  Widget _buildConfirmationForm(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.assignment_turned_in_rounded, color: AppTheme.qrisGreenDark, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Formulir Konfirmasi Pembayaran',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Nama Pengirim
            const Text(
              'Nama Rekening / Pemilik Akun Pengirim *',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: 'Contoh: Budi Santoso',
                prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                ),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Nama pengirim wajib diisi' : null,
            ),

            const SizedBox(height: 14),

            // Bank / E-Wallet Pengirim
            const Text(
              'Metode Pembayaran / Asal Bank *',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _bankOptions.map((bank) {
                final isSelected = _selectedBank == bank;
                return ChoiceChip(
                  label: Text(bank, style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500)),
                  selected: isSelected,
                  selectedColor: AppTheme.primary.withOpacity(0.2),
                  onSelected: (val) {
                    if (val) setState(() => _selectedBank = bank);
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 14),

            // Catatan Opsional
            const Text(
              'Catatan Tambahan (Opsional)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                hintText: 'Nomor referensi m-Banking / keterangan transfer',
                prefixIcon: const Icon(Icons.note_alt_outlined, size: 20),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0)),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Upload Bukti Transfer Box
            const Text(
              'Lampiran Bukti Transfer (Screenshot) *',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),

            if (_proofImageFile == null)
              InkWell(
                onTap: _showImageSourcePicker,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 110,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.primary.withOpacity(0.4),
                      style: BorderStyle.solid,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_upload_outlined, color: AppTheme.primary, size: 26),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Ketuk untuk Unggah Screenshot Bukti Bayar',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Format JPG, PNG (Maks 5MB)',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.qrisGreenDark.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _proofImageFile!,
                        width: 60,
                        height: 60,
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
                              Icon(Icons.check_circle_rounded, color: AppTheme.qrisGreenDark, size: 16),
                              SizedBox(width: 4),
                              Text('Foto Siap Dikirim', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _proofImageFile!.path.split('/').last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _showImageSourcePicker,
                      child: const Text('Ganti', style: TextStyle(fontSize: 12)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                      onPressed: () => setState(() => _proofImageFile = null),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 22),

            // Tombol Kirim Konfirmasi
            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.qrisGreenDark,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 3,
              ),
              child: _isSubmitting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Mengirim ke Google Sheets & Drive...',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Kirim Konfirmasi Pembayaran',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.check_circle_rounded, color: Colors.white, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
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

