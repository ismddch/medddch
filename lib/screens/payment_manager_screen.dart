import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'login_screen.dart';

class PaymentManagerScreen extends StatefulWidget {
  const PaymentManagerScreen({super.key});

  @override
  State<PaymentManagerScreen> createState() => _PaymentManagerScreenState();
}

class _PaymentManagerScreenState extends State<PaymentManagerScreen> {
  final SupabaseService _service = SupabaseService();
  List<PaymentRequestModel> _requests = [];
  bool _loading = true;
  String? _error;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _channel = _service.subscribeToPayments(_loadData);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() { _error = null; });
    }
    try {
      final data = await _service.getPendingPayments();
      if (mounted) setState(() { _requests = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _approve(PaymentRequestModel payment) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.approvePayment(payment);
      messenger.showSnackBar(_snack('✓ تمت الموافقة — تمت إضافة العميل للطابور', isError: false));
    } catch (e) {
      messenger.showSnackBar(_snack(e.toString().replaceAll('Exception: ', ''), isError: true));
    }
  }

  Future<void> _reject(PaymentRequestModel payment) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('رفض الطلب', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text(
            'هل تريد رفض طلب "${payment.userName ?? 'العميل'}"؟',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo(color: AppTheme.textMuted)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('رفض', style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.rejectPayment(payment.id);
      messenger.showSnackBar(_snack('تم رفض الطلب', isError: false));
    } catch (e) {
      messenger.showSnackBar(_snack(e.toString().replaceAll('Exception: ', ''), isError: true));
    }
  }

  SnackBar _snack(String msg, {required bool isError}) => SnackBar(
        content: Text(msg, style: GoogleFonts.cairo()),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  void _openPhoto(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: () => Navigator.pop(ctx),
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade900,
                  padding: const EdgeInsets.all(32),
                  child: const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _logout() {
    context.read<AuthProvider>().logout();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('طلبات الدفع', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            if (!_loading && _error == null)
              Text(
                '${_requests.length} طلب معلق',
                style: GoogleFonts.cairo(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
            onPressed: () { setState(() => _loading = true); _loadData(); },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'تسجيل الخروج',
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _requests.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                        itemCount: _requests.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 14),
                        itemBuilder: (_, i) {
                          final req = _requests[i];
                          return _PaymentCard(
                            order: i + 1,
                            payment: req,
                            onApprove: () => _approve(req),
                            onReject: () => _reject(req),
                            onPhotoTap: () => _openPhoto(req.photoUrl),
                          );
                        },
                      ),
                    ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded,
                  size: 56, color: AppTheme.success),
            ),
            const SizedBox(height: 20),
            Text('لا توجد طلبات معلقة',
                style: GoogleFonts.cairo(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primary)),
            const SizedBox(height: 8),
            Text('ستظهر الطلبات الجديدة هنا تلقائياً',
                style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textMuted)),
          ],
        ),
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 56, color: AppTheme.danger),
              const SizedBox(height: 16),
              Text('فشل تحميل الطلبات', style: GoogleFonts.cairo(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.primary)),
              const SizedBox(height: 8),
              Text(_error!, style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textMuted),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () { setState(() => _loading = true); _loadData(); },
                icon: const Icon(Icons.refresh_rounded),
                label: Text('إعادة المحاولة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Payment Card ─────────────────────────────────────────────────────────────

class _PaymentCard extends StatefulWidget {
  final int order;
  final PaymentRequestModel payment;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final VoidCallback onPhotoTap;

  const _PaymentCard({
    required this.order,
    required this.payment,
    required this.onApprove,
    required this.onReject,
    required this.onPhotoTap,
  });

  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  bool _busy = false;

  Future<void> _handle(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  String _walletLabel(String key) {
    const map = {
      'zain_cash':   'زين كاش',
      'asia_hawala': 'آسيا حوالة',
      'fib':         'FIB',
      'qi_card':     'Qi Card',
      'fastpay':     'FastPay',
    };
    return map[key] ?? key;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final isVip = p.queueType == 'vip';
    final queueColor = isVip ? const Color(0xFFFFB300) : AppTheme.accent;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header: order number + customer name ───────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                // Order number badge
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      '${widget.order}',
                      style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.userName ?? 'عميل',
                        style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15),
                      ),
                      if (p.userPhone != null)
                        Text(p.userPhone!,
                            style: GoogleFonts.cairo(
                                color: Colors.white60, fontSize: 12),
                            textDirection: TextDirection.ltr),
                    ],
                  ),
                ),
                // Queue type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: queueColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isVip ? Icons.star_rounded : Icons.people_rounded,
                        size: 13,
                        color: queueColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isVip ? 'VIP' : 'عادي',
                        style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: queueColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Body: photo + details ───────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Photo (tappable)
                GestureDetector(
                  onTap: widget.onPhotoTap,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          p.photoUrl,
                          width: 110,
                          height: 130,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 110,
                            height: 130,
                            decoration: BoxDecoration(
                              color: AppTheme.divider,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Icons.broken_image_rounded,
                                color: Colors.grey, size: 36),
                          ),
                          loadingBuilder: (_, child, progress) => progress == null
                              ? child
                              : Container(
                                  width: 110,
                                  height: 130,
                                  decoration: BoxDecoration(
                                    color: AppTheme.divider,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2)),
                                ),
                        ),
                      ),
                      Positioned(
                        bottom: 6,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('اضغط للتكبير',
                                style: GoogleFonts.cairo(
                                    color: Colors.white, fontSize: 10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailRow(Icons.store_rounded,     p.shopName   ?? '—', 'الصالون'),
                      const SizedBox(height: 8),
                      _DetailRow(Icons.content_cut_rounded, p.barberName ?? '—', 'الحلاق'),
                      const SizedBox(height: 8),
                      _DetailRow(Icons.account_balance_wallet_rounded,
                          _walletLabel(p.walletType), 'المحفظة'),
                      const SizedBox(height: 8),
                      _DetailRow(Icons.attach_money_rounded,
                          p.amount != null
                              ? '${p.amount!.toStringAsFixed(0)} IQD'
                              : '—',
                          'المبلغ'),
                      const SizedBox(height: 8),
                      _DetailRow(Icons.access_time_rounded,
                          _formatTime(p.createdAt), 'الوقت'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // ── Action buttons ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _busy
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : Row(
                    children: [
                      // Reject
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _handle(widget.onReject),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          label: Text('رفض',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: const BorderSide(color: AppTheme.danger, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Accept
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () => _handle(widget.onApprove),
                          icon: const Icon(Icons.check_rounded, size: 20),
                          label: Text('قبول وإضافة للطابور',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

// ── Detail Row ────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _DetailRow(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: AppTheme.accent),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.cairo(
                      fontSize: 10, color: AppTheme.textMuted)),
              Text(value,
                  style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ],
    );
  }
}
