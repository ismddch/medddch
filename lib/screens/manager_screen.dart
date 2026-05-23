import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'login_screen.dart';

class ManagerScreen extends StatefulWidget {
  const ManagerScreen({super.key});

  @override
  State<ManagerScreen> createState() => _ManagerScreenState();
}

class _ManagerScreenState extends State<ManagerScreen> {
  final SupabaseService _service = SupabaseService();

  List<PaymentRequestModel> _pendingRequests = [];
  // Only queue entries for prepayment-enabled barbers
  Map<String, Map<String, List<QueueEntryModel>>> _grouped = {};
  int _totalInQueue = 0;
  bool _loading = true;
  String? _error;
  RealtimeChannel? _queueChannel;
  RealtimeChannel? _paymentChannel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _queueChannel   = _service.subscribeToQueues(_loadData);
    _paymentChannel = _service.subscribeToPayments(_loadData);
  }

  @override
  void dispose() {
    if (_queueChannel != null) _service.unsubscribe(_queueChannel!);
    _paymentChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _service.getAllQueueEntries(),
        _service.getPendingPayments(),
      ]);

      final allEntries = results[0] as List<QueueEntryModel>;
      final payments   = results[1] as List<PaymentRequestModel>;

      // Keep only queue entries for prepayment-enabled shops
      final entries = allEntries
          .where((e) => e.shopPrepaymentEnabled)
          .toList();

      final grouped = <String, Map<String, List<QueueEntryModel>>>{};
      for (final e in entries) {
        final shop   = e.shopName   ?? 'غير معروف';
        final barber = e.barberName ?? 'حلاق';
        grouped.putIfAbsent(shop, () => {});
        grouped[shop]!.putIfAbsent(barber, () => []);
        grouped[shop]![barber]!.add(e);
      }

      if (mounted) {
        setState(() {
          _pendingRequests = payments;
          _grouped         = grouped;
          _totalInQueue    = entries.length;
          _loading         = false;
          _error           = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error   = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _acceptBooking(PaymentRequestModel payment) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _service.approvePayment(payment);
      messenger.showSnackBar(_snack('✓ تم قبول الحجز — العميل في الطابور', false));
    } catch (e) {
      messenger.showSnackBar(
          _snack(e.toString().replaceAll('Exception: ', ''), true));
    }
  }

  Future<void> _rejectBooking(PaymentRequestModel payment) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirmDialog(
      title: 'رفض الحجز',
      content: 'هل تريد رفض طلب حجز "${payment.userName ?? 'العميل'}"؟',
      actionLabel: 'رفض',
    );
    if (confirmed != true) return;
    try {
      await _service.rejectPayment(payment.id);
      messenger.showSnackBar(_snack('تم رفض الطلب', false));
    } catch (e) {
      messenger.showSnackBar(
          _snack(e.toString().replaceAll('Exception: ', ''), true));
    }
  }

  Future<void> _removeEntry(QueueEntryModel entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirmDialog(
      title: 'إزالة من الطابور',
      content: 'هل تريد إزالة "${entry.userName ?? 'العميل'}" من الطابور؟',
      actionLabel: 'إزالة',
    );
    if (confirmed != true) return;
    try {
      await _service.removeQueueEntry(entry.id);
      messenger.showSnackBar(_snack('تم إزالة العميل', false));
    } catch (e) {
      messenger.showSnackBar(
          _snack(e.toString().replaceAll('Exception: ', ''), true));
    }
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String content,
    required String actionLabel,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text(title,
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            content: Text(content, style: GoogleFonts.cairo()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('إلغاء',
                    style: GoogleFonts.cairo(color: AppTheme.textMuted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(actionLabel,
                    style: GoogleFonts.cairo(
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      );

  SnackBar _snack(String msg, bool isError) => SnackBar(
        content: Text(msg, style: GoogleFonts.cairo()),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  void _openPhoto(BuildContext context, String url) {
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
                  padding: const EdgeInsets.all(40),
                  child: const Icon(Icons.broken_image_rounded,
                      color: Colors.white54, size: 64),
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
    final hasContent =
        _pendingRequests.isNotEmpty || _grouped.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('إدارة الحجوزات',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            if (!_loading && _error == null)
              Text(
                '$_totalInQueue في الطابور'
                '${_pendingRequests.isNotEmpty ? ' · ${_pendingRequests.length} طلب معلق' : ''}',
                style: GoogleFonts.cairo(
                    fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _loading = true);
              _loadData();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : !hasContent
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: ListView(
                        padding:
                            const EdgeInsets.fromLTRB(16, 16, 16, 40),
                        children: [
                          // Stats
                          _StatsCard(
                            totalInQueue: _totalInQueue,
                            pendingCount: _pendingRequests.length,
                            totalBarbers: _grouped.length,
                          ),
                          const SizedBox(height: 20),

                          // ── Pending payment requests ──────────
                          if (_pendingRequests.isNotEmpty) ...[
                            _SectionHeader(
                              icon: Icons.pending_actions_rounded,
                              label: 'طلبات الحجز المعلقة',
                              count: _pendingRequests.length,
                              color: const Color(0xFFFF8C00),
                            ),
                            const SizedBox(height: 10),
                            ...List.generate(_pendingRequests.length, (i) {
                              final p = _pendingRequests[i];
                              return Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 12),
                                child: _PendingRequestCard(
                                  order: i + 1,
                                  payment: p,
                                  onAccept: () => _acceptBooking(p),
                                  onReject: () => _rejectBooking(p),
                                  onPhotoTap: () =>
                                      _openPhoto(context, p.photoUrl),
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                          ],

                          // ── Prepayment queue ──────────────────
                          if (_grouped.isNotEmpty) ...[
                            _SectionHeader(
                              icon: Icons.queue_rounded,
                              label: 'طابور الحجوزات المدفوعة',
                              count: _totalInQueue,
                              color: AppTheme.accent,
                            ),
                            const SizedBox(height: 10),
                            ...(_grouped.entries.map((shopEntry) =>
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 14),
                                  child: _BarberSection(
                                    shopName: shopEntry.key,
                                    barbers: shopEntry.value,
                                    onRemove: _removeEntry,
                                  ),
                                ))),
                          ],
                        ],
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
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  shape: BoxShape.circle),
              child: const Icon(Icons.event_available_rounded,
                  size: 54, color: AppTheme.accent),
            ),
            const SizedBox(height: 20),
            Text('لا توجد حجوزات حالياً',
                style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary)),
            const SizedBox(height: 8),
            Text('ستظهر طلبات الحجز هنا تلقائياً',
                style: GoogleFonts.cairo(
                    fontSize: 13, color: AppTheme.textMuted)),
          ],
        ),
      );

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 56, color: AppTheme.danger),
              const SizedBox(height: 16),
              Text('فشل تحميل البيانات',
                  style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary)),
              const SizedBox(height: 8),
              Text(_error!,
                  style: GoogleFonts.cairo(
                      fontSize: 12, color: AppTheme.textMuted),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() => _loading = true);
                  _loadData();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: Text('إعادة المحاولة',
                    style:
                        GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  const _SectionHeader(
      {required this.icon,
      required this.label,
      required this.count,
      required this.color});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: Text('$count',
                style: GoogleFonts.cairo(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Card
// ─────────────────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final int totalInQueue;
  final int pendingCount;
  final int totalBarbers;
  const _StatsCard(
      {required this.totalInQueue,
      required this.pendingCount,
      required this.totalBarbers});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            _Stat(Icons.people_rounded, '$totalInQueue', 'في الطابور',
                highlight: true),
            _Stat(Icons.pending_actions_rounded, '$pendingCount',
                'طلب معلق',
                highlight: pendingCount > 0,
                color: const Color(0xFFFF8C00)),
            _Stat(Icons.store_rounded, '$totalBarbers', 'صالونات'),
          ],
        ),
      );
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool highlight;
  final Color? color;
  const _Stat(this.icon, this.value, this.label,
      {this.highlight = false, this.color});

  @override
  Widget build(BuildContext context) {
    final c = highlight ? (color ?? AppTheme.accent) : Colors.white60;
    return Expanded(
      child: Column(children: [
        Icon(icon, color: c, size: 22),
        const SizedBox(height: 5),
        Text(value,
            style: GoogleFonts.cairo(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: highlight ? c : Colors.white)),
        Text(label,
            style:
                GoogleFonts.cairo(fontSize: 11, color: Colors.white54)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending Request Card  (photo + payment details + accept/reject)
// ─────────────────────────────────────────────────────────────────────────────

class _PendingRequestCard extends StatefulWidget {
  final int order;
  final PaymentRequestModel payment;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;
  final VoidCallback onPhotoTap;

  const _PendingRequestCard({
    required this.order,
    required this.payment,
    required this.onAccept,
    required this.onReject,
    required this.onPhotoTap,
  });

  @override
  State<_PendingRequestCard> createState() => _PendingRequestCardState();
}

class _PendingRequestCardState extends State<_PendingRequestCard> {
  bool _busy = false;

  Future<void> _handle(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  static String _walletLabel(String key) {
    const map = {
      'zain_cash':   'زين كاش',
      'asia_hawala': 'آسيا حوالة',
      'fib':         'FIB',
      'qi_card':     'Qi Card',
      'fastpay':     'FastPay',
    };
    return map[key] ?? key;
  }

  static String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final p     = widget.payment;
    final isVip = p.queueType == 'vip';
    const orange = Color(0xFFFF8C00);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: orange.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
              color: orange.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ───────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: orange,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(9)),
                  child: Center(
                    child: Text('${widget.order}',
                        style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.userName ?? 'عميل',
                          style: GoogleFonts.cairo(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                      if (p.userPhone != null)
                        Text(p.userPhone!,
                            style: GoogleFonts.cairo(
                                color: Colors.white70, fontSize: 12),
                            textDirection: TextDirection.ltr),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(9)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                          isVip
                              ? Icons.star_rounded
                              : Icons.people_rounded,
                          size: 13,
                          color: Colors.white),
                      const SizedBox(width: 3),
                      Text(isVip ? 'VIP' : 'عادي',
                          style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Photo + Payment details ───────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Photo thumbnail
                GestureDetector(
                  onTap: widget.onPhotoTap,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          p.photoUrl,
                          width: 110,
                          height: 140,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 110,
                            height: 140,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                                Icons.broken_image_rounded,
                                color: Colors.grey,
                                size: 40),
                          ),
                          loadingBuilder: (_, child, prog) =>
                              prog == null
                                  ? child
                                  : Container(
                                      width: 110,
                                      height: 140,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                      child: const Center(
                                          child:
                                              CircularProgressIndicator(
                                                  strokeWidth: 2)),
                                    ),
                        ),
                      ),
                      // Expand hint
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 5),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(14)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.zoom_in_rounded,
                                  color: Colors.white, size: 14),
                              const SizedBox(width: 3),
                              Text('تكبير',
                                  style: GoogleFonts.cairo(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // Payment details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تفاصيل الدفع',
                          style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary)),
                      const SizedBox(height: 10),
                      _PayDetail(
                          icon: Icons.store_rounded,
                          label: 'الصالون',
                          value: p.shopName ?? '—'),
                      _PayDetail(
                          icon: Icons.content_cut_rounded,
                          label: 'الحلاق',
                          value: p.barberName ?? '—'),
                      _PayDetail(
                          icon: Icons.account_balance_wallet_rounded,
                          label: 'طريقة الدفع',
                          value: _walletLabel(p.walletType)),
                      _PayDetail(
                          icon: Icons.attach_money_rounded,
                          label: 'المبلغ',
                          value: p.amount != null
                              ? '${p.amount!.toStringAsFixed(0)} IQD'
                              : '—',
                          highlight: true),
                      _PayDetail(
                          icon: Icons.access_time_rounded,
                          label: 'وقت الطلب',
                          value: _fmtTime(p.createdAt)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 14, endIndent: 14),

          // ── Action buttons ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      // Reject
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _handle(widget.onReject),
                          icon:
                              const Icon(Icons.close_rounded, size: 18),
                          label: Text('رفض',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: const BorderSide(
                                color: AppTheme.danger, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Accept
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () => _handle(widget.onAccept),
                          icon: const Icon(
                              Icons.how_to_reg_rounded,
                              size: 20),
                          label: Text('قبول الحجز',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 13),
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
}

// Payment detail row
class _PayDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;
  const _PayDetail(
      {required this.icon,
      required this.label,
      required this.value,
      this.highlight = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon,
                size: 14,
                color: highlight ? AppTheme.success : AppTheme.accent),
            const SizedBox(width: 5),
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
                          color: highlight
                              ? AppTheme.success
                              : AppTheme.primary),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Barber Section  (prepayment queue)
// ─────────────────────────────────────────────────────────────────────────────

class _BarberSection extends StatelessWidget {
  final String shopName;
  final Map<String, List<QueueEntryModel>> barbers;
  final Future<void> Function(QueueEntryModel) onRemove;
  const _BarberSection(
      {required this.shopName,
      required this.barbers,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final total = barbers.values.fold(0, (s, l) => s + l.length);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — shows shop name
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.store_rounded,
                      color: AppTheme.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(shopName,
                      style: GoogleFonts.cairo(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text('$total عميل',
                      style: GoogleFonts.cairo(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ],
            ),
          ),
          // Barbers (sub-groups)
          for (final barberEntry in barbers.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                const Icon(Icons.content_cut_rounded,
                    size: 15, color: AppTheme.accent),
                const SizedBox(width: 6),
                Text(barberEntry.key,
                    style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary)),
                const SizedBox(width: 6),
                Text('(${barberEntry.value.length})',
                    style: GoogleFonts.cairo(
                        fontSize: 12, color: AppTheme.textMuted)),
              ]),
            ),
            for (final entry in barberEntry.value)
              _EntryTile(
                  entry: entry, onRemove: () => onRemove(entry)),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Queue Entry Tile
// ─────────────────────────────────────────────────────────────────────────────

class _EntryTile extends StatelessWidget {
  final QueueEntryModel entry;
  final VoidCallback onRemove;
  const _EntryTile({required this.entry, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isVip = entry.queueType == 'vip';
    final color =
        isVip ? const Color(0xFFFFB300) : AppTheme.accent;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle),
            child: Center(
              child: Text('${entry.position}',
                  style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: color)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(entry.userName ?? 'عميل',
                        style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary)),
                  ),
                  if (isVip)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFB300)
                              .withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 11,
                              color: Color(0xFFFFB300)),
                          const SizedBox(width: 2),
                          Text('VIP',
                              style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      const Color(0xFFFFB300))),
                        ],
                      ),
                    ),
                ]),
                if (entry.userPhone != null)
                  Text(entry.userPhone!,
                      style: GoogleFonts.cairo(
                          fontSize: 11, color: AppTheme.textMuted),
                      textDirection: TextDirection.ltr),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.person_remove_rounded,
                color: AppTheme.danger, size: 22),
            tooltip: 'إزالة من الطابور',
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}
