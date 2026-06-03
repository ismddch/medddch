import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../utils/constants.dart';
import '../utils/theme.dart';

class PaymentBookingScreen extends StatefulWidget {
  final BarberModel barber;   // individual staff barber
  final ShopModel shop;       // the shop/salon
  final String queueType;
  final double? prefilledAmount;                      // total from service selection
  final List<Map<String, dynamic>>? selectedServices; // services chosen by customer

  const PaymentBookingScreen({
    super.key,
    required this.barber,
    required this.shop,
    required this.queueType,
    this.prefilledAmount,
    this.selectedServices,
  });

  @override
  State<PaymentBookingScreen> createState() => _PaymentBookingScreenState();
}

class _PaymentBookingScreenState extends State<PaymentBookingScreen> {
  final SupabaseService _service = SupabaseService();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _amountCtrl = TextEditingController();

  String? _selectedWallet;
  Uint8List? _photoBytes;
  String? _photoExt;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill amount from service menu if provided
    if (widget.prefilledAmount != null && widget.prefilledAmount! > 0) {
      _amountCtrl.text = widget.prefilledAmount!.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final ext = picked.name.split('.').last.toLowerCase();
    setState(() {
      _photoBytes = bytes;
      _photoExt = ext.isNotEmpty ? ext : 'jpg';
    });
  }

  Future<void> _submit() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    if (_selectedWallet == null) {
      _showSnack('اختر طريقة الدفع', isError: true);
      return;
    }
    if (_photoBytes == null) {
      _showSnack('ارفع صورة إيصال الدفع', isError: true);
      return;
    }
    final amountText = _amountCtrl.text.trim();
    if (amountText.isEmpty) {
      _showSnack('أدخل مبلغ الدفع', isError: true);
      return;
    }
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      _showSnack('المبلغ غير صحيح', isError: true);
      return;
    }

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final photoUrl = await _service.uploadImage(
        _photoBytes!,
        fileExt: _photoExt ?? 'jpg',
        folder: 'payments',
      );
      await _service.createPaymentRequest(
        userId:           user.id,
        barberId:         widget.barber.id,
        shopId:           widget.shop.id,
        walletType:       _selectedWallet!,
        photoUrl:         photoUrl,
        amount:           amount,
        queueType:        widget.queueType,
        selectedServices: widget.selectedServices,
      );
      // Instant confirmation — barber review notification fires separately
      // when the realtime subscription picks up the new payment_requests row.
      NotificationService.notifyCustomerBookingSubmitted(widget.barber.name)
          .ignore();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', ''),
            style: GoogleFonts.cairo()),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: GoogleFonts.cairo()),
      backgroundColor: isError ? AppTheme.danger : AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Widget _buildAccountCard(String walletKey) {
    final walletLabel = kWallets
        .firstWhere((w) => w['key'] == walletKey,
            orElse: () => {'key': walletKey, 'label': walletKey})['label']!;
    final number = widget.barber.walletNumbers[walletKey] ?? '';
    final hasNumber = number.isNotEmpty;

    return Container(
      key: ValueKey(walletKey),
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            'رقم حساب $walletLabel',
            style: GoogleFonts.cairo(fontSize: 13, color: Colors.white60),
          ),
          const SizedBox(height: 10),
          if (hasNumber) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    number,
                    style: GoogleFonts.cairo(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.accent,
                      letterSpacing: 4,
                    ),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.copy_rounded,
                      color: Colors.white54, size: 22),
                  tooltip: 'نسخ',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: number));
                    _showSnack('تم نسخ رقم الحساب');
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'حوّل المبلغ إلى هذا الرقم عبر $walletLabel\nثم ارفع صورة الإيصال أدناه',
              style: GoogleFonts.cairo(fontSize: 12, color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'لم يحدد الحلاق رقم $walletLabel بعد',
                    style: GoogleFonts.cairo(
                        fontSize: 13, color: Colors.orange),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'تواصل مع الحلاق مباشرةً للحصول على رقم الحساب',
              style: GoogleFonts.cairo(fontSize: 11, color: Colors.white38),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVip = widget.queueType == 'vip';
    final queueColor = isVip ? const Color(0xFFFFB300) : AppTheme.accent;

    return Scaffold(
      appBar: AppBar(
        title: Text('حجز مكان — ${widget.barber.name}',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Queue type badge (only when VIP is available) ──
            if (widget.shop.vipEnabled) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: queueColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: queueColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isVip ? Icons.star_rounded : Icons.people_rounded,
                        color: queueColor,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isVip ? 'طابور VIP' : 'طابور عادي',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700,
                          color: queueColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ── Selected services summary ────────────────────
            if (widget.selectedServices != null &&
                widget.selectedServices!.isNotEmpty) ...[
              _SelectedServicesSummary(
                services: widget.selectedServices!,
                queueColor: queueColor,
              ),
              const SizedBox(height: 20),
            ],

            // ── Wallet-specific account number card ──────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _selectedWallet == null
                  ? Container(
                      key: const ValueKey('no-wallet'),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 22),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.touch_app_rounded,
                              color: Colors.white38, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'اختر المحفظة أدناه لعرض رقم الحساب',
                            style: GoogleFonts.cairo(
                                fontSize: 13, color: Colors.white38),
                          ),
                        ],
                      ),
                    )
                  : _buildAccountCard(_selectedWallet!),
            ),
            const SizedBox(height: 28),

            // ── Wallet selection (only barber-configured wallets) ────
            Text(
              'طريقة الدفع',
              style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary),
            ),
            const SizedBox(height: 10),
            if (widget.barber.walletNumbers.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 18, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'لم يحدد الحلاق طرق الدفع بعد،\nتواصل معه مباشرةً',
                        style: GoogleFonts.cairo(
                            fontSize: 13, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              )
            else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: widget.barber.walletNumbers.keys.map((key) {
                final label = kWallets.firstWhere(
                  (w) => w['key'] == key,
                  orElse: () => {'key': key, 'label': key},
                )['label']!;
                final selected = _selectedWallet == key;
                return GestureDetector(
                  onTap: () => setState(() => _selectedWallet = key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.accent.withValues(alpha: 0.1)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? AppTheme.accent : AppTheme.divider,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      label,
                      style: GoogleFonts.cairo(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? AppTheme.accent : AppTheme.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // ── Amount field ─────────────────────────────────
            Text(
              'مبلغ الدفع',
              style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                hintText: '0.00',
                prefixIcon: Icon(Icons.attach_money_rounded,
                    color: AppTheme.accent),
              ),
            ),
            const SizedBox(height: 24),

            // ── Payment photo upload ──────────────────────────
            Text(
              'صورة إيصال الدفع',
              style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _submitting ? null : _pickPhoto,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                height: _photoBytes != null ? 220 : 120,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _photoBytes != null
                        ? AppTheme.accent
                        : AppTheme.divider,
                    width: _photoBytes != null ? 2 : 1,
                  ),
                  image: _photoBytes != null
                      ? DecorationImage(
                          image: MemoryImage(_photoBytes!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _photoBytes == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_photo_alternate_rounded,
                              color: AppTheme.accent, size: 36),
                          const SizedBox(height: 8),
                          Text(
                            'اضغط لرفع صورة الإيصال',
                            style: GoogleFonts.cairo(
                                color: AppTheme.textMuted, fontSize: 13),
                          ),
                        ],
                      )
                    : Align(
                        alignment: Alignment.bottomLeft,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'اضغط لتغييرها',
                            style: GoogleFonts.cairo(
                                color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Submit button ────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 22),
                label: Text(
                  _submitting ? 'جارٍ الإرسال...' : 'إرسال طلب الحجز',
                  style: GoogleFonts.cairo(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Selected Services Summary Card ───────────────────────────
// Shown at the top of the payment screen when the customer
// selected services from ServiceSelectionScreen.
class _SelectedServicesSummary extends StatelessWidget {
  final List<Map<String, dynamic>> services;
  final Color queueColor;

  const _SelectedServicesSummary({
    required this.services,
    required this.queueColor,
  });

  double get _total => services.fold(
      0.0, (sum, s) => sum + ((s['price'] as num?)?.toDouble() ?? 0.0));

  String _fmt(double v) =>
      v == v.roundToDouble() ? '${v.toInt()} MRU' : '${v.toStringAsFixed(2)} MRU';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: queueColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: queueColor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: queueColor.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: queueColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.receipt_long_rounded,
                      color: queueColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'الخدمة المختارة',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: queueColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'مطلوب',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: queueColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Service rows
          ...services.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            final price = (s['price'] as num?)?.toDouble() ?? 0.0;
            return Column(
              children: [
                if (i > 0)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
                  child: Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: queueColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          s['name']?.toString() ?? '',
                          style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      Text(
                        _fmt(price),
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: queueColor,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),

          // Total row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: queueColor.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(18)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'المجموع',
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
                Text(
                  _fmt(_total),
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: queueColor,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
