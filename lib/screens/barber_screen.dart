import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'login_screen.dart';

class BarberScreen extends StatefulWidget {
  const BarberScreen({super.key});

  @override
  State<BarberScreen> createState() => _BarberScreenState();
}

class _BarberScreenState extends State<BarberScreen> {
  final SupabaseService _service = SupabaseService();
  List<ChairModel> _chairs = [];
  Map<String, List<QueueEntryModel>> _queuesByChair = {};
  String? _selectedChairId;
  BarberModel? _barber;
  bool _loading = true;
  bool _shopClosed = false;
  bool _autoRemoveEnabled = false;
  Timer? _autoRemoveTimer;
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscription = _service.subscribeToQueues(_loadData);
  }

  @override
  void dispose() {
    if (_subscription != null) _service.unsubscribe(_subscription!);
    _autoRemoveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.barberId == null) return;

    try {
      final chairs = await _service.getChairs(user.barberId!);
      final barber = await _service.getBarberById(user.barberId!);
      final shopClosed = await _service.isShopClosed(user.barberId!);
      final Map<String, List<QueueEntryModel>> queues = {};

      for (final chair in chairs) {
        queues[chair.id] = await _service.getQueueForChair(chair.id);
      }

      if (mounted) {
        setState(() {
          _chairs = chairs;
          _barber = barber;
          _shopClosed = shopClosed;
          _queuesByChair = queues;
          _selectedChairId ??= chairs.isNotEmpty ? chairs.first.id : null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Actions ─────────────────────────────────────────────

  Future<void> _nextCustomer() async {
    if (_selectedChairId == null) return;
    await _service.removeFirstInQueue(_selectedChairId!);
  }

  Future<void> _removeCustomer(QueueEntryModel entry) async {
    await _service.removeFromQueue(entry.id, entry.chairId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم حذف ${entry.userName ?? 'العميل'}',
              style: GoogleFonts.cairo()),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          action: SnackBarAction(
            label: 'تراجع',
            textColor: Colors.white,
            onPressed: _undoDelete,
          ),
        ),
      );
    }
  }

  Future<void> _undoDelete() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.barberId == null) return;

    final success = await _service.undoLastDelete(user.barberId!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'تم استعادة العميل بنجاح' : 'لا يمكن التراجع',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: success ? AppTheme.success : AppTheme.textMuted,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _clearQueue() async {
    if (_selectedChairId == null) return;
    final confirmed = await _showConfirm(
      'مسح الطابور',
      'هل أنت متأكد من مسح جميع العملاء في الطابور؟',
    );
    if (confirmed) {
      await _service.clearQueue(_selectedChairId!);
    }
  }

  Future<void> _toggleChairClosed(ChairModel chair) async {
    await _service.toggleChairClosed(chair.id, !chair.isClosed);
    _loadData();
  }

  Future<void> _toggleShop() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.barberId == null) return;

    final action = _shopClosed ? 'فتح' : 'إغلاق';
    final confirmed = await _showConfirm(
      '$action المحل',
      'هل تريد $action جميع الكراسي؟',
    );
    if (confirmed) {
      await _service.toggleShopClosed(user.barberId!, !_shopClosed);
      _loadData();
    }
  }

  Future<void> _addCustomerToQueue() async {
    if (_selectedChairId == null) return;

    final selectedChair = _chairs.firstWhere((c) => c.id == _selectedChairId);
    if (selectedChair.isClosed) {
      _showMessage('الكرسي مغلق حالياً', isError: true);
      return;
    }

    final phone = await _showInputDialog(
      title: 'إضافة عميل مسجل',
      hint: 'رقم هاتف العميل',
      icon: Icons.person_add_alt_1_rounded,
      keyboardType: TextInputType.phone,
      isLtr: true,
    );

    if (phone != null && phone.trim().isNotEmpty) {
      try {
        await _service.addCustomerToQueue(_selectedChairId!, phone.trim());
        _showMessage('تم إضافة العميل بنجاح');
      } catch (e) {
        _showMessage(
          e.toString().replaceAll('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  Future<void> _addGuestToQueue() async {
    if (_selectedChairId == null) return;
    final user = context.read<AuthProvider>().user;
    if (user == null || user.barberId == null) return;

    final selectedChair = _chairs.firstWhere((c) => c.id == _selectedChairId);
    if (selectedChair.isClosed) {
      _showMessage('الكرسي مغلق حالياً', isError: true);
      return;
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => const _GuestFormDialog(),
    );

    if (result != null) {
      try {
        await _service.addGuestToQueue(
          chairId: _selectedChairId!,
          name: result['name']!,
          phone: result['phone']!,
          barberId: user.barberId!,
        );
        _showMessage('تم إضافة الزائر بنجاح');
      } catch (e) {
        _showMessage(
          e.toString().replaceAll('Exception: ', ''),
          isError: true,
        );
      }
    }
  }

  void _toggleAutoRemove() {
    setState(() {
      _autoRemoveEnabled = !_autoRemoveEnabled;
    });

    if (_autoRemoveEnabled) {
      _autoRemoveTimer = Timer.periodic(
        const Duration(hours: 1),
        (_) => _autoRemoveFirstInQueue(),
      );
      _showMessage('تفعيل الحذف التلقائي — كل ساعة');
    } else {
      _autoRemoveTimer?.cancel();
      _autoRemoveTimer = null;
      _showMessage('تم إيقاف الحذف التلقائي');
    }
  }

  Future<void> _autoRemoveFirstInQueue() async {
    if (_selectedChairId == null) return;
    final removed = await _service.autoRemoveFirst(_selectedChairId!);
    if (removed && mounted) {
      _showMessage('تم حذف أول عميل تلقائياً');
    }
  }

  // ─── Helpers ─────────────────────────────────────────────

  void _showMessage(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: GoogleFonts.cairo()),
        backgroundColor: isError ? AppTheme.danger : AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<bool> _showConfirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title,
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text(message, style: GoogleFonts.cairo()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              child: Text('نعم', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  Future<String?> _showInputDialog({
    required String title,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool isLtr = false,
  }) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title,
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: keyboardType,
            textDirection: isLtr ? TextDirection.ltr : TextDirection.rtl,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, color: AppTheme.accent),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text('إضافة', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  void _logout() {
    context.read<AuthProvider>().logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // ─── Build ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final currentQueue = _queuesByChair[_selectedChairId] ?? [];
    final totalInQueue = _queuesByChair.values
        .fold<int>(0, (sum, list) => sum + list.length);
    final selectedChair = _selectedChairId != null
        ? _chairs.cast<ChairModel?>().firstWhere(
            (c) => c!.id == _selectedChairId,
            orElse: () => null)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم الحلاق'),
        automaticallyImplyLeading: false,
        actions: [
          // Auto-remove toggle
          IconButton(
            icon: Icon(
              _autoRemoveEnabled
                  ? Icons.timer_rounded
                  : Icons.timer_off_outlined,
              color: _autoRemoveEnabled ? AppTheme.accent : null,
            ),
            onPressed: _toggleAutoRemove,
            tooltip: _autoRemoveEnabled
                ? 'إيقاف الحذف التلقائي'
                : 'تفعيل الحذف التلقائي (كل ساعة)',
          ),
          // Undo button
          IconButton(
            icon: const Icon(Icons.undo_rounded),
            onPressed: _undoDelete,
            tooltip: 'تراجع عن الحذف',
          ),
          // Close shop toggle
          IconButton(
            icon: Icon(
              _shopClosed
                  ? Icons.lock_rounded
                  : Icons.lock_open_rounded,
            ),
            onPressed: _toggleShop,
            tooltip: _shopClosed ? 'فتح المحل' : 'إغلاق المحل',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      // ─── FABs: Add Customer / Add Guest ─────
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Add guest (no account)
          FloatingActionButton.small(
            heroTag: 'guest',
            onPressed: _addGuestToQueue,
            backgroundColor: AppTheme.primary,
            tooltip: 'إضافة زائر بدون حساب',
            child: const Icon(Icons.person_outline_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(height: 10),
          // Add registered customer
          FloatingActionButton(
            heroTag: 'registered',
            onPressed: _addCustomerToQueue,
            backgroundColor: AppTheme.accent,
            tooltip: 'إضافة عميل مسجل',
            child: const Icon(Icons.person_add_alt_1_rounded,
                color: Colors.white),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ─── Dashboard Header ───────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(24),
                      bottomRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (_barber != null) ...[
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.accent, width: 3),
                            image: _barber!.imageUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(_barber!.imageUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            color: AppTheme.accent.withOpacity(0.2),
                          ),
                          child: _barber!.imageUrl == null
                              ? const Icon(Icons.content_cut_rounded,
                                  color: AppTheme.accent, size: 32)
                              : null,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _barber!.name,
                          style: GoogleFonts.cairo(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        'مرحباً ${user?.name ?? ''}',
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // ─── Shop Status + Total ─────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_rounded,
                                    color: AppTheme.accent, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                  'العملاء: $totalInQueue',
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: _shopClosed
                                  ? AppTheme.danger.withOpacity(0.2)
                                  : AppTheme.success.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _shopClosed
                                      ? Icons.lock_rounded
                                      : Icons.check_circle_rounded,
                                  color: _shopClosed
                                      ? AppTheme.danger
                                      : AppTheme.success,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _shopClosed ? 'مغلق' : 'مفتوح',
                                  style: GoogleFonts.cairo(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _shopClosed
                                        ? AppTheme.danger
                                        : AppTheme.success,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // ─── Auto-remove indicator ─────
                      if (_autoRemoveEnabled) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_rounded,
                                  color: AppTheme.accent, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'الحذف التلقائي مفعل — كل ساعة',
                                style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // ─── Chair Tabs ─────────────────────
                if (_chairs.isNotEmpty)
                  Container(
                    height: 70,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _chairs.length,
                      itemBuilder: (context, index) {
                        final chair = _chairs[index];
                        final isSelected = chair.id == _selectedChairId;
                        final count = _queuesByChair[chair.id]?.length ?? 0;

                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedChairId = chair.id),
                          onLongPress: () => _toggleChairClosed(chair),
                          child: Container(
                            margin: const EdgeInsets.only(left: 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: chair.isClosed
                                  ? AppTheme.textMuted.withOpacity(0.15)
                                  : isSelected
                                      ? AppTheme.accent
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: chair.isClosed
                                    ? AppTheme.textMuted.withOpacity(0.3)
                                    : isSelected
                                        ? AppTheme.accent
                                        : AppTheme.divider,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Chair thumbnail
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(9),
                                    image: chair.imageUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(chair.imageUrl!),
                                            fit: BoxFit.cover,
                                            colorFilter: chair.isClosed
                                                ? const ColorFilter.mode(
                                                    Colors.grey,
                                                    BlendMode.saturation)
                                                : null,
                                          )
                                        : null,
                                    color: isSelected
                                        ? Colors.white.withOpacity(0.2)
                                        : AppTheme.primary.withOpacity(0.06),
                                  ),
                                  child: chair.imageUrl == null
                                      ? Icon(
                                          chair.isClosed
                                              ? Icons.lock_rounded
                                              : Icons.chair_rounded,
                                          size: 16,
                                          color: chair.isClosed
                                              ? AppTheme.textMuted
                                              : isSelected
                                                  ? Colors.white
                                                  : AppTheme.accent,
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  chair.name,
                                  style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w700,
                                    color: chair.isClosed
                                        ? AppTheme.textMuted
                                        : isSelected
                                            ? Colors.white
                                            : AppTheme.primary,
                                    fontSize: 13,
                                    decoration: chair.isClosed
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (chair.isClosed)
                                  Icon(Icons.lock_rounded,
                                      size: 14, color: AppTheme.textMuted)
                                else
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.white.withOpacity(0.2)
                                          : AppTheme.primary.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '$count',
                                      style: GoogleFonts.cairo(
                                        fontWeight: FontWeight.w800,
                                        color: isSelected
                                            ? Colors.white
                                            : AppTheme.primary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // ─── Chair Closed Banner ────────────
                if (selectedChair != null && selectedChair.isClosed)
                  Container(
                    width: double.infinity,
                    margin:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: AppTheme.danger.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_rounded,
                            color: AppTheme.danger, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'هذا الكرسي مغلق حالياً',
                            style: GoogleFonts.cairo(
                              color: AppTheme.danger,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _toggleChairClosed(selectedChair),
                          child: Text('فتح',
                              style: GoogleFonts.cairo(
                                color: AppTheme.success,
                                fontWeight: FontWeight.w700,
                              )),
                        ),
                      ],
                    ),
                  ),

                // ─── Action Buttons ─────────────────
                if (_selectedChairId != null &&
                    currentQueue.isNotEmpty &&
                    (selectedChair == null || !selectedChair.isClosed))
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _nextCustomer,
                            icon: const Icon(Icons.skip_next_rounded,
                                size: 20),
                            label: Text('العميل التالي',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.success,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _undoDelete,
                          icon: const Icon(Icons.undo_rounded),
                          tooltip: 'تراجع',
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primary.withOpacity(0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _clearQueue,
                          icon: const Icon(Icons.delete_sweep_rounded,
                              color: AppTheme.danger),
                          tooltip: 'مسح الكل',
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.danger.withOpacity(0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ─── Queue List ─────────────────────
                Expanded(
                  child: currentQueue.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_rounded,
                                  size: 64,
                                  color: AppTheme.textMuted.withOpacity(0.3)),
                              const SizedBox(height: 12),
                              Text(
                                'لا يوجد عملاء في الطابور',
                                style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              if (selectedChair != null &&
                                  !selectedChair.isClosed) ...[
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed: _addCustomerToQueue,
                                  icon: const Icon(
                                      Icons.person_add_alt_1_rounded,
                                      size: 18),
                                  label: Text('إضافة عميل',
                                      style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w600)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.accent,
                                    side:
                                        const BorderSide(color: AppTheme.accent),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
                          itemCount: currentQueue.length,
                          itemBuilder: (context, index) {
                            final entry = currentQueue[index];
                            return Dismissible(
                              key: Key(entry.id),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.delete_rounded,
                                    color: Colors.white),
                              ),
                              onDismissed: (_) => _removeCustomer(entry),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border:
                                      Border.all(color: AppTheme.divider),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: index == 0
                                            ? AppTheme.accent
                                            : AppTheme.primary
                                                .withOpacity(0.08),
                                        borderRadius:
                                            BorderRadius.circular(13),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${entry.position}',
                                          style: GoogleFonts.cairo(
                                            fontWeight: FontWeight.w800,
                                            color: index == 0
                                                ? Colors.white
                                                : AppTheme.primary,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            entry.userName ?? 'عميل',
                                            style: GoogleFonts.cairo(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            entry.userPhone ?? '',
                                            style: GoogleFonts.cairo(
                                              fontSize: 13,
                                              color: AppTheme.textMuted,
                                            ),
                                            textDirection: TextDirection.ltr,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded,
                                          color: AppTheme.danger, size: 22),
                                      onPressed: () =>
                                          _removeCustomer(entry),
                                      tooltip: 'حذف',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ─── Guest Form Dialog ────────────────────────────────────────
class _GuestFormDialog extends StatefulWidget {
  const _GuestFormDialog();

  @override
  State<_GuestFormDialog> createState() => _GuestFormDialogState();
}

class _GuestFormDialogState extends State<_GuestFormDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person_outline_rounded,
                  color: AppTheme.accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'إضافة زائر بدون حساب',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'أدخل اسم ورقم هاتف الزائر لإضافته للطابور',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'اسم الزائر',
                    prefixIcon: const Icon(Icons.person_outline,
                        color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'أدخل الاسم' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: 'رقم الهاتف',
                    prefixIcon: const Icon(Icons.phone_outlined,
                        color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'أدخل رقم الهاتف' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, {
                  'name': _nameCtrl.text.trim(),
                  'phone': _phoneCtrl.text.trim(),
                });
              }
            },
            child: Text('إضافة للطابور', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }
}
