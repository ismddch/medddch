import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';

class ChairDashboardScreen extends StatefulWidget {
  final ChairModel chair;
  final BarberModel barber;

  const ChairDashboardScreen({
    super.key,
    required this.chair,
    required this.barber,
  });

  @override
  State<ChairDashboardScreen> createState() => _ChairDashboardScreenState();
}

class _ChairDashboardScreenState extends State<ChairDashboardScreen> {
  final SupabaseService _service = SupabaseService();
  List<QueueEntryModel> _queue = [];
  late ChairModel _chair;
  bool _loading = true;
  bool _autoRemoveEnabled = false;
  Timer? _autoRemoveTimer;
  RealtimeChannel? _subscription;
  int _currentIndex = 0;
  int _prevQueueLength = -1;
  bool _initialLoadDone = false;

  // Chair profile tab state
  final _nameCtrl = TextEditingController();
  final _picker = ImagePicker();
  bool _chairSaving = false;
  bool _chairUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _chair = widget.chair;
    _nameCtrl.text = widget.chair.name;
    _loadQueue();
    _subscription = _service.subscribeToQueues(_loadQueue);
  }

  @override
  void dispose() {
    if (_subscription != null) _service.unsubscribe(_subscription!);
    _autoRemoveTimer?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ─── Chair Profile Actions ────────────────────────────────

  Future<void> _pickAndUploadChairImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;
    setState(() => _chairUploadingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final url = await _service.uploadImage(
        bytes,
        fileExt: ext.isNotEmpty ? ext : 'jpg',
        folder: 'chairs',
      );
      await _service.updateChair(_chair.id,
          name: _chair.name, imageUrl: url);
      setState(() => _chair = ChairModel(
            id: _chair.id,
            barberId: _chair.barberId,
            name: _chair.name,
            imageUrl: url,
            isClosed: _chair.isClosed,
            queueLength: _chair.queueLength,
          ));
      _showMessage('تم تحديث صورة الكرسي');
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _chairUploadingImage = false);
    }
  }

  Future<void> _saveChairProfile() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _chairSaving = true);
    try {
      await _service.updateChair(_chair.id,
          name: name, imageUrl: _chair.imageUrl);
      setState(() => _chair = ChairModel(
            id: _chair.id,
            barberId: _chair.barberId,
            name: name,
            imageUrl: _chair.imageUrl,
            isClosed: _chair.isClosed,
            queueLength: _chair.queueLength,
          ));
      _showMessage('تم حفظ بيانات الكرسي');
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _chairSaving = false);
    }
  }

  Future<void> _loadQueue() async {
    try {
      final queue = await _service.getQueueForChair(_chair.id);
      // Refresh chair state (e.g. isClosed may have changed)
      final chairs = await _service.getChairs(widget.barber.id);
      final updated = chairs.cast<ChairModel?>().firstWhere(
            (c) => c!.id == _chair.id,
            orElse: () => null,
          );
      if (mounted) {
        // Notify barber when a new customer joins (skip on first load).
        if (_initialLoadDone && queue.length > _prevQueueLength) {
          NotificationService.notifyBarberNewCustomer(_chair.name);
        }
        _prevQueueLength = queue.length;
        _initialLoadDone = true;

        setState(() {
          _queue = queue;
          if (updated != null) _chair = updated;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Queue Actions ────────────────────────────────────────

  Future<void> _nextCustomer() async {
    await _service.removeFirstInQueue(_chair.id);
    await _loadQueue();
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
    final success =
        await _service.undoLastDelete(widget.barber.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'تم استعادة العميل بنجاح' : 'لا يمكن التراجع',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor:
              success ? AppTheme.success : AppTheme.textMuted,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _clearQueue() async {
    final confirmed = await _showConfirm(
      'مسح الطابور',
      'هل أنت متأكد من مسح جميع العملاء في الطابور؟',
    );
    if (confirmed) await _service.clearQueue(_chair.id);
  }

  Future<void> _toggleChairClosed() async {
    await _service.toggleChairClosed(_chair.id, !_chair.isClosed);
    await _loadQueue();
  }

  Future<void> _addCustomerToQueue() async {
    if (_chair.isClosed) {
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
        await _service.addCustomerToQueue(_chair.id, phone.trim());
        _showMessage('تم إضافة العميل بنجاح');
      } catch (e) {
        _showMessage(e.toString().replaceAll('Exception: ', ''),
            isError: true);
      }
    }
  }

  Future<void> _addGuestToQueue() async {
    if (_chair.isClosed) {
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
          chairId: _chair.id,
          name: result['name']!,
          phone: result['phone']!,
          barberId: widget.barber.id,
        );
        _showMessage('تم إضافة الزائر بنجاح');
      } catch (e) {
        _showMessage(e.toString().replaceAll('Exception: ', ''),
            isError: true);
      }
    }
  }

  void _toggleAutoRemove() {
    setState(() => _autoRemoveEnabled = !_autoRemoveEnabled);
    if (_autoRemoveEnabled) {
      _autoRemoveTimer = Timer.periodic(
        const Duration(hours: 1),
        (_) async {
          final removed = await _service.autoRemoveFirst(_chair.id);
          if (removed && mounted) _showMessage('تم حذف أول عميل تلقائياً');
        },
      );
      _showMessage('تفعيل الحذف التلقائي — كل ساعة');
    } else {
      _autoRemoveTimer?.cancel();
      _autoRemoveTimer = null;
      _showMessage('تم إيقاف الحذف التلقائي');
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<bool> _showConfirm(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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

  // ─── Queue Tab UI ─────────────────────────────────────────

  Widget _buildQueueTab() {
    final user = context.watch<AuthProvider>().user;
    return Column(
      children: [
        // ─── Header ────────────────────────────────
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
              Row(
                children: [
                  // Barber avatar
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.accent, width: 2),
                      image: widget.barber.imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(widget.barber.imageUrl!),
                              fit: BoxFit.cover)
                          : null,
                      color: AppTheme.accent.withValues(alpha:0.2),
                    ),
                    child: widget.barber.imageUrl == null
                        ? const Icon(Icons.content_cut_rounded,
                            color: AppTheme.accent, size: 24)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.barber.name,
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'مرحباً ${user?.name ?? ''}',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Chair info badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chair_rounded,
                            color: AppTheme.accent, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          _chair.name,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Status row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people_rounded,
                            color: AppTheme.accent, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          'في الانتظار: ${_queue.length}',
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
                      color: _chair.isClosed
                          ? AppTheme.danger.withValues(alpha:0.2)
                          : AppTheme.success.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _chair.isClosed
                              ? Icons.lock_rounded
                              : Icons.check_circle_rounded,
                          color: _chair.isClosed
                              ? AppTheme.danger
                              : AppTheme.success,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _chair.isClosed ? 'مغلق' : 'مفتوح',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _chair.isClosed
                                ? AppTheme.danger
                                : AppTheme.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_autoRemoveEnabled) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha:0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_rounded,
                          color: AppTheme.accent, size: 14),
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

        // ─── Chair Closed Banner ────────────────────
        if (_chair.isClosed)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha:0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.danger.withValues(alpha:0.2)),
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
                  onPressed: _toggleChairClosed,
                  child: Text('فتح',
                      style: GoogleFonts.cairo(
                        color: AppTheme.success,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ],
            ),
          ),

        // ─── Action Buttons ─────────────────────────
        if (!_chair.isClosed)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        _queue.isNotEmpty ? _nextCustomer : null,
                    icon: const Icon(Icons.skip_next_rounded, size: 20),
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
                    backgroundColor:
                        AppTheme.primary.withValues(alpha:0.08),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _queue.isNotEmpty ? _clearQueue : null,
                  icon: const Icon(Icons.delete_sweep_rounded,
                      color: AppTheme.danger),
                  tooltip: 'مسح الكل',
                  style: IconButton.styleFrom(
                    backgroundColor:
                        AppTheme.danger.withValues(alpha:0.08),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

        // ─── Queue List ──────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _queue.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_rounded,
                              size: 64,
                              color: AppTheme.textMuted.withValues(alpha:0.3)),
                          const SizedBox(height: 12),
                          Text(
                            'لا يوجد عملاء في الطابور',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          if (!_chair.isClosed) ...[
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
                                side: const BorderSide(
                                    color: AppTheme.accent),
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding:
                          const EdgeInsets.fromLTRB(20, 12, 20, 100),
                      itemCount: _queue.length,
                      itemBuilder: (context, index) {
                        final entry = _queue[index];
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
                              border: Border.all(
                                  color: AppTheme.divider),
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
                                            .withValues(alpha:0.08),
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
    );
  }

  // ─── Chair Profile Tab ───────────────────────────────────

  Widget _buildChairTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // ─── Chair Image ──────────────────────────
          GestureDetector(
            onTap: _chairUploadingImage ? null : _pickAndUploadChairImage,
            child: Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.accent, width: 3),
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    image: _chair.imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_chair.imageUrl!),
                            fit: BoxFit.cover)
                        : null,
                  ),
                  child: _chairUploadingImage
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : _chair.imageUrl == null
                          ? const Icon(Icons.chair_rounded,
                              size: 52, color: AppTheme.accent)
                          : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط لتغيير صورة الكرسي',
            style: GoogleFonts.cairo(
                fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 32),
          // ─── Chair Name ───────────────────────────
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم الكرسي',
              prefixIcon:
                  Icon(Icons.chair_rounded, color: AppTheme.accent),
            ),
          ),
          const SizedBox(height: 24),
          // ─── Save Button ──────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _chairSaving ? null : _saveChairProfile,
              child: _chairSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text('حفظ التغييرات',
                      style: GoogleFonts.cairo(
                          fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? '${_chair.name} — لوحة التحكم'
              : 'إعدادات الكرسي',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: 'تغيير الكرسي',
          onPressed: () => Navigator.pop(context),
        ),
        actions: _currentIndex == 0
            ? [
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
                      : 'تفعيل الحذف التلقائي',
                ),
                IconButton(
                  icon: Icon(
                    _chair.isClosed
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    color: _chair.isClosed ? AppTheme.danger : null,
                  ),
                  onPressed: _toggleChairClosed,
                  tooltip:
                      _chair.isClosed ? 'فتح الكرسي' : 'إغلاق الكرسي',
                ),
              ]
            : null,
      ),
      floatingActionButton: _currentIndex == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'guest',
                  onPressed: _addGuestToQueue,
                  backgroundColor: AppTheme.primary,
                  tooltip: 'إضافة زائر بدون حساب',
                  child: const Icon(Icons.person_outline_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'registered',
                  onPressed: _addCustomerToQueue,
                  backgroundColor: AppTheme.accent,
                  tooltip: 'إضافة عميل مسجل',
                  child: const Icon(Icons.person_add_alt_1_rounded,
                      color: Colors.white),
                ),
              ],
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        selectedLabelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.cairo(),
        selectedItemColor: AppTheme.accent,
        unselectedItemColor: AppTheme.textMuted,
        backgroundColor: Colors.white,
        elevation: 12,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.people_alt_outlined),
            activeIcon: Icon(Icons.people_alt_rounded),
            label: 'الطابور',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chair_outlined),
            activeIcon: Icon(Icons.chair_rounded),
            label: 'الكرسي',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildQueueTab(),
          _buildChairTab(),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha:0.08),
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
                    fontWeight: FontWeight.w700, fontSize: 16),
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
                      fontSize: 12, color: AppTheme.textMuted),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'اسم الزائر',
                    prefixIcon: Icon(Icons.person_outline,
                        color: AppTheme.accent),
                    contentPadding: EdgeInsets.symmetric(
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
                  decoration: const InputDecoration(
                    hintText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone_outlined,
                        color: AppTheme.accent),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'أدخل رقم الهاتف'
                          : null,
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
