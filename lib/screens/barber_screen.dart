import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'login_screen.dart';

// BarberScreen is the main screen for role='barber' users.
// It loads their own BarberModel (staff record) via user.barberId → barbers.id,
// then loads the ShopModel for that barber, and shows a full queue dashboard.
// No chair-selection step — each barber has their own dedicated screen.

class BarberScreen extends StatefulWidget {
  const BarberScreen({super.key});

  @override
  State<BarberScreen> createState() => _BarberScreenState();
}

class _BarberScreenState extends State<BarberScreen> {
  final SupabaseService _service = SupabaseService();
  List<QueueEntryModel> _queue = [];
  BarberModel? _barber;
  ShopModel? _shop;
  bool _loading = true;
  bool _autoRemoveEnabled = false;
  Timer? _autoRemoveTimer;
  RealtimeChannel? _subscription;
  int _currentIndex = 0;

  // Profile tab state
  final _nameCtrl = TextEditingController();
  final _picker = ImagePicker();
  bool _barberSaving = false;
  bool _barberUploadingImage = false;

  // Portfolio state
  List<String> _portfolioUrls = [];
  bool _addingPhoto = false;

  // Payments tab state
  List<PaymentRequestModel> _paymentRequests = [];
  RealtimeChannel? _paymentChannel;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscription   = _service.subscribeToQueues(_loadData);
    final barberId  = context.read<AuthProvider>().user?.barberId ?? '';
    _paymentChannel = _service.subscribeToPaymentsForBarber(barberId, _loadPaymentRequests);
  }

  @override
  void dispose() {
    if (_subscription   != null) _service.unsubscribe(_subscription!);
    if (_paymentChannel != null) _service.unsubscribe(_paymentChannel!);
    _autoRemoveTimer?.cancel();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ─── Data Loading ─────────────────────────────────────────

  Future<void> _loadData() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.barberId == null) return;
    try {
      final barber = await _service.getBarberById(user.barberId!);
      if (barber == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final results = await Future.wait([
        _service.getShopById(barber.shopId),
        _service.getQueueForBarber(barber.id),
        _service.getBarberPortfolio(barber.id),
        _service.getPendingPaymentsForBarber(barber.id),
      ]);
      if (mounted) {
        setState(() {
          _barber          = barber;
          _shop            = results[0] as ShopModel?;
          _queue           = results[1] as List<QueueEntryModel>;
          _portfolioUrls   = results[2] as List<String>;
          _paymentRequests = results[3] as List<PaymentRequestModel>;
          _loading         = false;
          if (_nameCtrl.text.isEmpty) _nameCtrl.text = barber.name;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Barber Profile Actions ───────────────────────────────

  Future<void> _pickAndUploadBarberImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;
    setState(() => _barberUploadingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final url = await _service.uploadImage(
        bytes,
        fileExt: ext.isNotEmpty ? ext : 'jpg',
        folder: 'barbers',
      );
      if (_barber != null) {
        await _service.updateBarber(_barber!.id, name: _barber!.name, imageUrl: url);
        if (mounted) {
          setState(() => _barber = BarberModel(
                id: _barber!.id,
                shopId: _barber!.shopId,
                name: _barber!.name,
                imageUrl: url,
                isClosed: _barber!.isClosed,
                isVipLocked: _barber!.isVipLocked,
                isNormalLocked: _barber!.isNormalLocked,
                queueLength: _barber!.queueLength,
                paymentNumber: _barber!.paymentNumber,
              ));
          _showMessage('تم تحديث صورة الحلاق');
        }
      }
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _barberUploadingImage = false);
    }
  }

  Future<void> _saveBarberProfile() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _barber == null) return;
    setState(() => _barberSaving = true);
    try {
      await _service.updateBarber(_barber!.id, name: name, imageUrl: _barber!.imageUrl);
      setState(() => _barber = BarberModel(
            id: _barber!.id,
            shopId: _barber!.shopId,
            name: name,
            imageUrl: _barber!.imageUrl,
            isClosed: _barber!.isClosed,
            isVipLocked: _barber!.isVipLocked,
            isNormalLocked: _barber!.isNormalLocked,
            queueLength: _barber!.queueLength,
            paymentNumber: _barber!.paymentNumber,
          ));
      _showMessage('تم حفظ بيانات الحلاق');
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _barberSaving = false);
    }
  }

  // ─── Portfolio Actions ────────────────────────────────────

  Future<void> _addPortfolioPhoto() async {
    if (_barber == null) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 82,
    );
    if (picked == null || !mounted) return;
    setState(() => _addingPhoto = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final url = await _service.uploadImage(
        bytes,
        fileExt: ext.isNotEmpty ? ext : 'jpg',
        folder: 'portfolio',
      );
      await _service.addPortfolioPhoto(_barber!.id, url);
      if (mounted) {
        setState(() => _portfolioUrls.insert(0, url));
        _showMessage('تمت إضافة الصورة');
      }
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _addingPhoto = false);
    }
  }

  Future<void> _deletePortfolioPhoto(String url) async {
    if (_barber == null) return;
    try {
      await _service.deletePortfolioPhoto(_barber!.id, url);
      if (mounted) {
        setState(() => _portfolioUrls.remove(url));
        _showMessage('تم حذف الصورة');
      }
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  // ─── Payment Actions ──────────────────────────────────────

  Future<void> _loadPaymentRequests() async {
    if (_barber == null || !mounted) return;
    try {
      final requests = await _service.getPendingPaymentsForBarber(_barber!.id);
      if (!mounted) return;
      final previousCount = _paymentRequests.length;
      setState(() => _paymentRequests = requests);
      if (requests.length > previousCount) {
        final newest = requests.last;
        NotificationService.notifyBarberNewPayment(newest.userName ?? '');
      }
    } catch (_) {}
  }

  Future<void> _editPaymentNumber() async {
    final ctrl =
        TextEditingController(text: _barber?.paymentNumber ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text('رقم الدفع',
              style:
                  GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              hintText: 'رقم الحساب أو المحفظة',
              prefixIcon: Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppTheme.accent),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, ctrl.text.trim()),
              child: Text('حفظ', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty || _barber == null) return;
    try {
      await _service.updateBarberPaymentNumber(_barber!.id, result);
      if (mounted) {
        setState(() => _barber = BarberModel(
              id: _barber!.id,
              shopId: _barber!.shopId,
              name: _barber!.name,
              imageUrl: _barber!.imageUrl,
              isClosed: _barber!.isClosed,
              isVipLocked: _barber!.isVipLocked,
              isNormalLocked: _barber!.isNormalLocked,
              queueLength: _barber!.queueLength,
              paymentNumber: result,
            ));
        _showMessage('تم حفظ رقم الدفع');
      }
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''),
          isError: true);
    }
  }

  Future<void> _approvePayment(PaymentRequestModel payment) async {
    try {
      await _service.approvePayment(payment);
      if (mounted) {
        _showMessage('✓ تمت الموافقة — تمت إضافة العميل للطابور');
        await Future.wait([_loadPaymentRequests(), _loadData()]);
      }
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''),
          isError: true);
    }
  }

  Future<void> _rejectPayment(PaymentRequestModel payment) async {
    final confirmed = await _showConfirm(
      'رفض الطلب',
      'هل تريد رفض طلب "${payment.userName ?? 'العميل'}"؟',
    );
    if (!confirmed) return;
    try {
      await _service.rejectPayment(payment.id);
      if (mounted) {
        _showMessage('تم رفض الطلب');
        await _loadPaymentRequests();
      }
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''),
          isError: true);
    }
  }

  void _openPaymentPhoto(String url) {
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
              child: Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade900,
                        padding: const EdgeInsets.all(32),
                        child: const Icon(
                            Icons.broken_image_rounded,
                            color: Colors.white54,
                            size: 64),
                      )),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Queue Actions ────────────────────────────────────────

  Future<void> _nextVip() async {
    if (_barber == null) return;
    await _service.removeFirstInQueue(_barber!.id, 'vip');
    await _loadData();
  }

  Future<void> _nextNormal() async {
    if (_barber == null) return;
    await _service.removeFirstInQueue(_barber!.id, 'normal');
    await _loadData();
  }

  Future<void> _toggleVipLocked() async {
    if (_barber == null) return;
    await _service.toggleBarberVipLocked(_barber!.id, !_barber!.isVipLocked);
    await _loadData();
  }

  Future<void> _toggleNormalLocked() async {
    if (_barber == null) return;
    await _service.toggleBarberNormalLocked(_barber!.id, !_barber!.isNormalLocked);
    await _loadData();
  }

  Future<void> _removeCustomer(QueueEntryModel entry) async {
    await _service.removeFromQueue(entry.id, entry.barberId);
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
    if (_barber == null) return;
    final success = await _service.undoLastDelete(_barber!.shopId);
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
    if (_barber == null) return;
    final confirmed = await _showConfirm(
      'مسح الطابور',
      'هل أنت متأكد من مسح جميع العملاء في الطابور؟',
    );
    if (confirmed) {
      await _service.clearQueue(_barber!.id);
      await _loadData();
    }
  }

  Future<void> _toggleBarberClosed() async {
    if (_barber == null) return;
    await _service.toggleBarberClosed(_barber!.id, !_barber!.isClosed);
    await _loadData();
  }

  Future<void> _addCustomerToQueue() async {
    if (_barber == null) return;
    if (_barber!.isClosed) {
      _showMessage('أنت مغلق حالياً', isError: true);
      return;
    }

    final vipEnabled = _shop?.vipEnabled ?? false;
    String selectedType = 'normal';

    if (vipEnabled) {
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text('نوع الطابور',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            content: Text('اختر نوع الطابور للعميل المسجل',
                style: GoogleFonts.cairo()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('إلغاء', style: GoogleFonts.cairo()),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'normal'),
                icon: const Icon(Icons.people_rounded),
                label: Text('عادي', style: GoogleFonts.cairo()),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'vip'),
                icon: const Icon(Icons.star_rounded, color: Colors.white),
                label: Text('VIP', style: GoogleFonts.cairo()),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB300)),
              ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      selectedType = picked;
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
        await _service.addCustomerToQueue(_barber!.id, phone.trim(),
            queueType: selectedType);
        _showMessage('تم إضافة العميل بنجاح');
        await _loadData();
      } catch (e) {
        _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
      }
    }
  }

  Future<void> _addGuestToQueue() async {
    if (_barber == null) return;
    if (_barber!.isClosed) {
      _showMessage('أنت مغلق حالياً', isError: true);
      return;
    }
    final vipEnabled = _shop?.vipEnabled ?? false;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _GuestFormDialog(vipEnabled: vipEnabled),
    );
    if (result != null && _shop != null) {
      try {
        final queueType = vipEnabled ? (result['type'] ?? 'normal') : 'normal';
        await _service.addGuestToQueue(
          barberId: _barber!.id,
          shopId: _shop!.id,
          name: result['name']!,
          phone: result['phone']!,
          queueType: queueType,
        );
        _showMessage('تم إضافة الزائر بنجاح');
        await _loadData();
      } catch (e) {
        _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
      }
    }
  }

  void _toggleAutoRemove() {
    setState(() => _autoRemoveEnabled = !_autoRemoveEnabled);
    if (_autoRemoveEnabled) {
      _autoRemoveTimer = Timer.periodic(
        const Duration(hours: 1),
        (_) async {
          if (_barber == null) return;
          final removed = await _service.autoRemoveFirst(_barber!.id);
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

  void _logout() {
    context.read<AuthProvider>().logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف الحساب',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content: Text(
          'هل أنت متأكد أنك تريد حذف حسابك نهائياً؟ لا يمكن التراجع.',
          style: GoogleFonts.cairo(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('حذف',
                style: GoogleFonts.cairo(
                    color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await context.read<AuthProvider>().deleteCurrentUserAccount();
    if (success && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
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

  // ─── Queue Tab UI ─────────────────────────────────────────

  Widget _buildQueueTab() {
    final barber = _barber;
    if (barber == null) {
      return Center(
        child: Text(
          'لا يوجد سجل حلاق مرتبط بهذا الحساب',
          style: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 15),
          textAlign: TextAlign.center,
        ),
      );
    }

    final vipEnabled = _shop?.vipEnabled ?? false;
    final vipEntries = _queue.where((e) => e.queueType == 'vip').toList();
    final normalEntries = _queue.where((e) => e.queueType == 'normal').toList();

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
                      image: barber.imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(barber.imageUrl!),
                              fit: BoxFit.cover)
                          : null,
                      color: AppTheme.accent.withValues(alpha: 0.2),
                    ),
                    child: barber.imageUrl == null
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
                          barber.name,
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        if (_shop != null)
                          Text(
                            _shop!.name,
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Shop badge
                  if (_shop != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.store_rounded,
                              color: AppTheme.accent, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            _shop!.name,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
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
              // Status row: queue counts | open/closed
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (vipEnabled) ...[
                    _HeaderBadge(
                      icon: Icons.star_rounded,
                      label: 'VIP: ${vipEntries.length}',
                      color: const Color(0xFFFFB300),
                    ),
                    const SizedBox(width: 8),
                    _HeaderBadge(
                      icon: Icons.people_rounded,
                      label: 'عادي: ${normalEntries.length}',
                      color: AppTheme.accent,
                    ),
                  ] else
                    _HeaderBadge(
                      icon: Icons.people_rounded,
                      label: 'الطابور: ${_queue.length}',
                      color: AppTheme.accent,
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: barber.isClosed
                          ? AppTheme.danger.withValues(alpha: 0.2)
                          : AppTheme.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          barber.isClosed
                              ? Icons.lock_rounded
                              : Icons.check_circle_rounded,
                          color: barber.isClosed
                              ? AppTheme.danger
                              : AppTheme.success,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          barber.isClosed ? 'مغلق' : 'مفتوح',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: barber.isClosed
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
                    color: AppTheme.accent.withValues(alpha: 0.15),
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

        // ─── Barber Closed Banner ────────────────────
        if (barber.isClosed)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border:
                  Border.all(color: AppTheme.danger.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded,
                    color: AppTheme.danger, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'أنت مغلق حالياً',
                    style: GoogleFonts.cairo(
                      color: AppTheme.danger,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _toggleBarberClosed,
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
        if (!barber.isClosed)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              children: [
                if (vipEnabled) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              vipEntries.isNotEmpty ? _nextVip : null,
                          icon: const Icon(Icons.star_rounded,
                              size: 18, color: Colors.white),
                          label: Text('التالي VIP',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFB300),
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: normalEntries.isNotEmpty
                              ? _nextNormal
                              : null,
                          icon: const Icon(Icons.skip_next_rounded, size: 18),
                          label: Text('التالي عادي',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _queue.isNotEmpty ? _nextNormal : null,
                      icon: const Icon(Icons.skip_next_rounded, size: 20),
                      label: Text('التالي',
                          style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _undoDelete,
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: Text('تراجع',
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.primary),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            _queue.isNotEmpty ? _clearQueue : null,
                        icon: const Icon(Icons.delete_sweep_rounded,
                            size: 18, color: AppTheme.danger),
                        label: Text('مسح الكل',
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w600,
                                color: AppTheme.danger)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: BorderSide(
                              color: _queue.isNotEmpty
                                  ? AppTheme.danger
                                  : AppTheme.textMuted),
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
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
                              color: AppTheme.textMuted
                                  .withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text(
                            'لا يوجد عملاء في الطابور',
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              color: AppTheme.textMuted,
                            ),
                          ),
                          if (!barber.isClosed) ...[
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
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                      children: (vipEnabled)
                          ? [
                              const _SectionHeader(
                                icon: Icons.star_rounded,
                                label: 'طابور VIP',
                                color: Color(0xFFFFB300),
                              ),
                              if (vipEntries.isEmpty)
                                const _EmptySectionMessage(
                                    label: 'لا يوجد عملاء VIP')
                              else
                                ...vipEntries.asMap().entries.map((e) {
                                  final entry = e.value;
                                  return _QueueEntryCard(
                                    entry: entry,
                                    isFirst: e.key == 0,
                                    isVip: true,
                                    onRemove: () => _removeCustomer(entry),
                                  );
                                }),
                              const SizedBox(height: 16),
                              const _SectionHeader(
                                icon: Icons.people_rounded,
                                label: 'الطابور العادي',
                                color: AppTheme.accent,
                              ),
                              if (normalEntries.isEmpty)
                                const _EmptySectionMessage(
                                    label:
                                        'لا يوجد عملاء في الطابور العادي')
                              else
                                ...normalEntries.asMap().entries.map((e) {
                                  final entry = e.value;
                                  return _QueueEntryCard(
                                    entry: entry,
                                    isFirst: e.key == 0,
                                    isVip: false,
                                    onRemove: () => _removeCustomer(entry),
                                  );
                                }),
                            ]
                          : _queue.asMap().entries.map((e) {
                              final entry = e.value;
                              return _QueueEntryCard(
                                entry: entry,
                                isFirst: e.key == 0,
                                isVip: false,
                                onRemove: () => _removeCustomer(entry),
                              );
                            }).toList(),
                    ),
        ),
      ],
    );
  }

  // ─── Payments Tab ────────────────────────────────────────

  Widget _buildPaymentsTab() {
    final barber = _barber;
    if (barber == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final hasNumber = barber.paymentNumber?.isNotEmpty == true;

    return Column(
      children: [
        // ── Payment number header ────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          decoration: const BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              Text('رقم الحساب للدفع',
                  style: GoogleFonts.cairo(
                      fontSize: 12, color: Colors.white60)),
              const SizedBox(height: 8),
              if (hasNumber) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      barber.paymentNumber!,
                      style: GoogleFonts.cairo(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: AppTheme.accent,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded,
                          color: Colors.white54, size: 20),
                      tooltip: 'نسخ',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(
                            text: barber.paymentNumber!));
                        _showMessage('تم نسخ رقم الحساب');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded,
                          color: Colors.white38, size: 18),
                      tooltip: 'تعديل',
                      onPressed: _editPaymentNumber,
                    ),
                  ],
                ),
                Text('العملاء يحولون الدفع لهذا الرقم',
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: Colors.white38)),
              ] else ...[
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _editPaymentNumber,
                  icon: const Icon(Icons.add_rounded,
                      color: Colors.white70, size: 18),
                  label: Text('تعيين رقم الدفع',
                      style: GoogleFonts.cairo(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 4),
                Text('يجب تعيين رقم الدفع حتى يتمكن العملاء من الحجز',
                    style: GoogleFonts.cairo(
                        fontSize: 10, color: Colors.white38),
                    textAlign: TextAlign.center),
              ],
            ],
          ),
        ),

        // ── Toolbar: count + refresh button ──────────
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                'الطلبات المعلقة',
                style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
              if (_paymentRequests.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_paymentRequests.length}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: _loadPaymentRequests,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: Text('تحديث',
                    style: GoogleFonts.cairo(
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),

        // ── Pending bookings ─────────────────────────
        Expanded(
          child: _paymentRequests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_rounded,
                          size: 64,
                          color: AppTheme.textMuted
                              .withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text('لا توجد طلبات حجز معلقة',
                          style: GoogleFonts.cairo(
                              fontSize: 15,
                              color: AppTheme.textMuted)),
                      const SizedBox(height: 6),
                      Text('ستظهر الطلبات الجديدة هنا تلقائياً',
                          style: GoogleFonts.cairo(
                              fontSize: 12,
                              color: AppTheme.textMuted
                                  .withValues(alpha: 0.6))),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPaymentRequests,
                  child: ListView.separated(
                    padding:
                        const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    itemCount: _paymentRequests.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final req = _paymentRequests[i];
                      return _BarberPaymentCard(
                        order: i + 1,
                        payment: req,
                        onApprove: () => _approvePayment(req),
                        onReject: () => _rejectPayment(req),
                        onPhotoTap: () =>
                            _openPaymentPhoto(req.photoUrl),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  // ─── Barber Profile Tab ───────────────────────────────────

  Widget _buildProfileTab() {
    final barber = _barber;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          // ─── Barber Image ─────────────────────────
          GestureDetector(
            onTap: _barberUploadingImage ? null : _pickAndUploadBarberImage,
            child: Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.accent, width: 3),
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    image: barber?.imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(barber!.imageUrl!),
                            fit: BoxFit.cover)
                        : null,
                  ),
                  child: _barberUploadingImage
                      ? const Padding(
                          padding: EdgeInsets.all(32),
                          child:
                              CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : barber?.imageUrl == null
                          ? const Icon(Icons.content_cut_rounded,
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
            'اضغط لتغيير صورة الحلاق',
            style: GoogleFonts.cairo(
                fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 32),
          // ─── Barber Name ──────────────────────────
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم الحلاق',
              prefixIcon: Icon(Icons.content_cut_rounded,
                  color: AppTheme.accent),
            ),
          ),
          const SizedBox(height: 24),
          // ─── Shop info (read-only) ────────────────
          if (_shop != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.store_rounded,
                      color: AppTheme.accent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _shop!.name,
                          style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        Text(
                          'الصالون المنتسب',
                          style: GoogleFonts.cairo(
                              color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          // ─── Save Button ──────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _barberSaving ? null : _saveBarberProfile,
              child: _barberSaving
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
          const SizedBox(height: 32),
          // ─── Portfolio ────────────────────────────
          Row(
            children: [
              const Icon(Icons.photo_library_rounded,
                  color: AppTheme.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'أعمالي',
                style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary),
              ),
              const Spacer(),
              _addingPhoto
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton.icon(
                      onPressed:
                          _barber != null ? _addPortfolioPhoto : null,
                      icon: const Icon(Icons.add_photo_alternate_rounded,
                          size: 18, color: AppTheme.accent),
                      label: Text('إضافة',
                          style: GoogleFonts.cairo(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w700)),
                    ),
            ],
          ),
          const SizedBox(height: 10),
          if (_portfolioUrls.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_photo_alternate_outlined,
                      size: 40,
                      color: AppTheme.textMuted.withValues(alpha: 0.4)),
                  const SizedBox(height: 8),
                  Text('لم تضف أي صور بعد',
                      style: GoogleFonts.cairo(
                          fontSize: 13, color: AppTheme.textMuted)),
                ],
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _portfolioUrls.length,
              itemBuilder: (_, i) {
                final url = _portfolioUrls[i];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: AppTheme.divider,
                          child: const Icon(Icons.broken_image_rounded,
                              color: AppTheme.textMuted),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _deletePortfolioPhoto(url),
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                              color: AppTheme.danger,
                              shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 14),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          // ─── Logout ───────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded,
                  color: AppTheme.primary),
              label: Text('تسجيل الخروج',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _confirmDeleteAccount,
              icon: const Icon(Icons.delete_forever_rounded,
                  color: Colors.red),
              label: Text('حذف الحساب',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w600, color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final barber = _barber;
    final vipEnabled = _shop?.vipEnabled ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentIndex == 0
              ? (barber != null ? '${barber.name} — لوحة التحكم' : 'لوحة التحكم')
              : _currentIndex == 1
                  ? 'طلبات الحجز المدفوع'
                  : 'الملف الشخصي',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
        actions: _currentIndex == 0 && barber != null
            ? [
                // Auto-remove timer toggle
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
                // VIP lock — only shown when VIP enabled for this shop
                if (vipEnabled)
                  IconButton(
                    icon: Icon(
                      Icons.star_rounded,
                      color: barber.isVipLocked
                          ? AppTheme.danger
                          : const Color(0xFFFFB300),
                    ),
                    onPressed: _toggleVipLocked,
                    tooltip: barber.isVipLocked
                        ? 'فتح طابور VIP'
                        : 'إغلاق طابور VIP',
                  ),
                // Normal queue lock
                IconButton(
                  icon: Icon(
                    Icons.people_rounded,
                    color: barber.isNormalLocked
                        ? AppTheme.danger
                        : AppTheme.accent,
                  ),
                  onPressed: _toggleNormalLocked,
                  tooltip: barber.isNormalLocked
                      ? 'فتح الطابور'
                      : 'إغلاق الطابور',
                ),
                // Open/closed toggle
                IconButton(
                  icon: Icon(
                    barber.isClosed
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    color: barber.isClosed ? AppTheme.danger : null,
                  ),
                  onPressed: _toggleBarberClosed,
                  tooltip: barber.isClosed ? 'فتح' : 'إغلاق',
                ),
              ]
            : null,
      ),
      floatingActionButton: _currentIndex == 0 && barber != null && !_loading
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
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.people_alt_outlined),
            activeIcon: Icon(Icons.people_alt_rounded),
            label: 'الطابور',
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _paymentRequests.isNotEmpty,
              label: Text('${_paymentRequests.length}'),
              child: const Icon(Icons.receipt_long_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: _paymentRequests.isNotEmpty,
              label: Text('${_paymentRequests.length}'),
              child: const Icon(Icons.receipt_long_rounded),
            ),
            label: 'الحجوزات',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline_rounded),
            activeIcon: Icon(Icons.person_rounded),
            label: 'الملف الشخصي',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(
              index: _currentIndex,
              children: [
                _buildQueueTab(),
                _buildPaymentsTab(),
                _buildProfileTab(),
              ],
            ),
    );
  }
}

// ─── Section Header ───────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty Section Message ────────────────────────────────────
class _EmptySectionMessage extends StatelessWidget {
  final String label;
  const _EmptySectionMessage({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        label,
        style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Header Badge ─────────────────────────────────────────────
class _HeaderBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _HeaderBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Queue Entry Card ─────────────────────────────────────────
class _QueueEntryCard extends StatelessWidget {
  final QueueEntryModel entry;
  final bool isFirst;
  final bool isVip;
  final VoidCallback onRemove;

  const _QueueEntryCard({
    required this.entry,
    required this.isFirst,
    required this.isVip,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final posColor = isVip
        ? (isFirst ? const Color(0xFFFFB300) : const Color(0xFFFFD54F))
        : (isFirst
            ? AppTheme.accent
            : AppTheme.primary.withValues(alpha: 0.08));
    final posTextColor = isVip
        ? (isFirst ? Colors.white : const Color(0xFF7A5800))
        : (isFirst ? Colors.white : AppTheme.primary);

    return Dismissible(
      key: Key(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: AppTheme.danger,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) => onRemove(),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isVip
                ? const Color(0xFFFFB300).withValues(alpha: 0.35)
                : AppTheme.divider,
          ),
        ),
        child: Row(
          children: [
            // Position badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: posColor,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: isVip && isFirst
                    ? const Icon(Icons.star_rounded,
                        color: Colors.white, size: 22)
                    : Text(
                        '${entry.position}',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w800,
                          color: posTextColor,
                          fontSize: 18,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
              onPressed: onRemove,
              tooltip: 'حذف',
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Barber Payment Card ──────────────────────────────────────
class _BarberPaymentCard extends StatefulWidget {
  final int order;
  final PaymentRequestModel payment;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final VoidCallback onPhotoTap;

  const _BarberPaymentCard({
    required this.order,
    required this.payment,
    required this.onApprove,
    required this.onReject,
    required this.onPhotoTap,
  });

  @override
  State<_BarberPaymentCard> createState() => _BarberPaymentCardState();
}

class _BarberPaymentCardState extends State<_BarberPaymentCard> {
  bool _busy = false;

  Future<void> _handle(Future<void> Function() action) async {
    setState(() => _busy = true);
    await action();
    if (mounted) setState(() => _busy = false);
  }

  String _walletLabel(String key) => const {
        'zain_cash':   'زين كاش',
        'asia_hawala': 'آسيا حوالة',
        'fib':         'FIB',
        'qi_card':     'Qi Card',
        'fastpay':     'FastPay',
      }[key] ?? key;

  @override
  Widget build(BuildContext context) {
    final p = widget.payment;
    final isVip = p.queueType == 'vip';
    final queueColor =
        isVip ? const Color(0xFFFFB300) : AppTheme.accent;
    final waitMin = p.createdAt
        .difference(DateTime.now())
        .abs()
        .inMinutes;
    final timeLabel = waitMin < 60
        ? 'منذ $waitMin دقيقة'
        : 'منذ ${(waitMin / 60).floor()} ساعة';

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
          // ── Header ──────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text('${widget.order}',
                        style: GoogleFonts.cairo(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
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
                                color: Colors.white60,
                                fontSize: 12),
                            textDirection: TextDirection.ltr),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: queueColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isVip
                            ? Icons.star_rounded
                            : Icons.people_rounded,
                        size: 13,
                        color: queueColor,
                      ),
                      const SizedBox(width: 4),
                      Text(isVip ? 'VIP' : 'عادي',
                          style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: queueColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Body: photo + details ───────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            child: const Icon(
                                Icons.broken_image_rounded,
                                color: Colors.grey,
                                size: 36),
                          ),
                          loadingBuilder: (_, child, prog) =>
                              prog == null
                                  ? child
                                  : Container(
                                      width: 110,
                                      height: 130,
                                      decoration: BoxDecoration(
                                        color: AppTheme.divider,
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
                                    color: Colors.white,
                                    fontSize: 10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PRow(Icons.account_balance_wallet_rounded,
                          _walletLabel(p.walletType), 'المحفظة'),
                      const SizedBox(height: 8),
                      _PRow(
                          Icons.attach_money_rounded,
                          p.amount != null
                              ? '${p.amount!.toStringAsFixed(0)} د'
                              : '—',
                          'المبلغ'),
                      const SizedBox(height: 8),
                      _PRow(Icons.phone_rounded,
                          p.userPhone ?? '—', 'الهاتف'),
                      const SizedBox(height: 8),
                      _PRow(Icons.access_time_rounded, timeLabel,
                          'الوقت'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, indent: 16, endIndent: 16),

          // ── Action buttons ──────────────────────────
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
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _handle(widget.onReject),
                          icon: const Icon(Icons.close_rounded,
                              size: 20),
                          label: Text('رفض',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.danger,
                            side: const BorderSide(
                                color: AppTheme.danger, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(
                                vertical: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _handle(widget.onApprove),
                          icon: const Icon(Icons.check_rounded,
                              size: 20),
                          label: Text('قبول وإضافة للطابور',
                              style: GoogleFonts.cairo(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14)),
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

class _PRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _PRow(this.icon, this.value, this.label);

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
          child: Icon(icon, size: 14, color: AppTheme.accent),
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

// ─── Guest Form Dialog ────────────────────────────────────────
class _GuestFormDialog extends StatefulWidget {
  final bool vipEnabled;
  const _GuestFormDialog({this.vipEnabled = false});

  @override
  State<_GuestFormDialog> createState() => _GuestFormDialogState();
}

class _GuestFormDialogState extends State<_GuestFormDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isVip = false;

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
                color: AppTheme.primary.withValues(alpha: 0.08),
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
                    prefixIcon:
                        Icon(Icons.person_outline, color: AppTheme.accent),
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
                if (widget.vipEnabled) ...[
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: _isVip
                          ? const Color(0xFFFFB300).withValues(alpha: 0.1)
                          : AppTheme.primary.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isVip
                            ? const Color(0xFFFFB300)
                                .withValues(alpha: 0.4)
                            : AppTheme.divider,
                      ),
                    ),
                    child: SwitchListTile(
                      value: _isVip,
                      onChanged: (v) => setState(() => _isVip = v),
                      secondary: Icon(
                        Icons.star_rounded,
                        color: _isVip
                            ? const Color(0xFFFFB300)
                            : AppTheme.textMuted,
                      ),
                      title: Text(
                        'طابور VIP',
                        style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w600,
                          color: _isVip
                              ? const Color(0xFFFFB300)
                              : AppTheme.primary,
                          fontSize: 14,
                        ),
                      ),
                      activeThumbColor: const Color(0xFFFFB300),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                      dense: true,
                    ),
                  ),
                ],
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
                  'type': _isVip ? 'vip' : 'normal',
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
