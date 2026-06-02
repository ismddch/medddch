import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:share_plus/share_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../utils/constants.dart';
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
  int _prevQueueLength = -1; // -1 = initial load, skip notification
  BarberModel? _barber;
  ShopModel? _shop;
  bool _loading = true;
  bool _autoRemoveEnabled = false;
  Timer? _autoRemoveTimer;
  RealtimeChannel? _subscription;
  int _currentIndex = 0;

  // Profile tab state
  final _nameCtrl   = TextEditingController();
  final _tiktokCtrl = TextEditingController();
  final _picker = ImagePicker();
  bool _barberSaving = false;
  bool _barberUploadingImage = false;

  // Portfolio state
  List<String> _portfolioUrls = [];
  bool _addingPhoto = false;

  // Payments tab state
  List<PaymentRequestModel> _paymentRequests = [];
  RealtimeChannel? _paymentChannel;

  // Menu tab state
  List<BarberMenuItemModel> _menuItems = [];
  bool _menuLoading = false;

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
    _tiktokCtrl.dispose();
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
        _service.getBarberMenu(barber.id),
      ]);
      if (mounted) {
        setState(() {
          _barber          = barber;
          _shop            = results[0] as ShopModel?;
          final newQueue   = results[1] as List<QueueEntryModel>;
          final prevLen    = _prevQueueLength;
          _queue           = newQueue;
          _prevQueueLength = newQueue.length;
          _portfolioUrls   = results[2] as List<String>;
          _paymentRequests = results[3] as List<PaymentRequestModel>;
          _menuItems       = results[4] as List<BarberMenuItemModel>;
          _loading         = false;
          if (_nameCtrl.text.isEmpty) _nameCtrl.text = barber.name;
          if (_tiktokCtrl.text.isEmpty) _tiktokCtrl.text = barber.tiktokUrl ?? '';

          // Notify barber when a new customer joins (skip the very first load)
          if (prevLen >= 0 && newQueue.length > prevLen) {
            NotificationService.notifyBarberNewCustomer(barber.name);
          }
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
    final name   = _nameCtrl.text.trim();
    final tiktok = _tiktokCtrl.text.trim();
    if (name.isEmpty || _barber == null) return;
    setState(() => _barberSaving = true);
    try {
      await _service.updateBarber(_barber!.id, name: name, imageUrl: _barber!.imageUrl);
      if (tiktok != (_barber!.tiktokUrl ?? '')) {
        await _service.updateBarberTiktokUrl(_barber!.id, tiktok.isEmpty ? null : tiktok);
      }
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
            tiktokUrl: tiktok.isEmpty ? null : tiktok,
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

  Future<void> _addWallet() async {
    if (_barber == null) return;
    // Wallets not yet configured by this barber
    final available = kWallets
        .where((w) => !(_barber!.walletNumbers.containsKey(w['key']!)))
        .toList();

    String? pickedKey;
    String? pickedLabel;

    // Let the barber pick which wallet to add
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: AppTheme.divider,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 20),
              Text('اختر المحفظة',
                  style: GoogleFonts.cairo(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: AppTheme.primary)),
              const SizedBox(height: 16),
              if (available.isEmpty)
                Center(
                  child: Text('تمت إضافة جميع المحافظ المتاحة',
                      style: GoogleFonts.cairo(
                          fontSize: 13, color: AppTheme.textMuted)),
                )
              else
                ...available.map((w) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.account_balance_wallet_rounded,
                            color: AppTheme.accent, size: 20),
                      ),
                      title: Text(w['label']!,
                          style: GoogleFonts.cairo(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () {
                        pickedKey   = w['key'];
                        pickedLabel = w['label'];
                        Navigator.pop(ctx);
                      },
                    )),
            ],
          ),
        ),
      ),
    );

    if (pickedKey == null || pickedLabel == null) return;
    // Now ask for the account number
    await _editWalletNumber(pickedKey!, pickedLabel!);
  }

  Future<void> _deleteWallet(String walletKey, String walletLabel) async {
    if (_barber == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Text('حذف المحفظة',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text(
            'هل تريد إزالة "$walletLabel" من قائمة طرق الدفع؟',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('حذف', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    final updated = Map<String, String>.from(_barber!.walletNumbers)
      ..remove(walletKey);
    try {
      await _service.updateBarberWalletNumbers(_barber!.id, updated);
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
              paymentNumber: _barber!.paymentNumber,
              walletNumbers: updated,
              tiktokUrl: _barber!.tiktokUrl,
            ));
        _showMessage('تم حذف $walletLabel');
      }
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  Future<void> _editWalletNumber(String walletKey, String walletLabel) async {
    if (_barber == null) return;
    final current = _barber!.walletNumbers[walletKey] ?? '';
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('رقم حساب $walletLabel',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'أدخل رقم الحساب',
              prefixIcon: const Icon(Icons.account_balance_wallet_rounded,
                  color: AppTheme.accent),
              suffixIcon: ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => ctrl.clear(),
                    )
                  : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text('حفظ', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (result == null || _barber == null) return;
    final updated = Map<String, String>.from(_barber!.walletNumbers);
    if (result.isEmpty) {
      updated.remove(walletKey);
    } else {
      updated[walletKey] = result;
    }
    try {
      await _service.updateBarberWalletNumbers(_barber!.id, updated);
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
              paymentNumber: _barber!.paymentNumber,
              walletNumbers: updated,
              tiktokUrl: _barber!.tiktokUrl,
            ));
        _showMessage(result.isEmpty ? 'تم حذف الرقم' : 'تم حفظ رقم الحساب');
      }
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
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

  // ─── Menu Actions ─────────────────────────────────────────

  Future<void> _loadMenu() async {
    if (_barber == null) return;
    setState(() => _menuLoading = true);
    try {
      final items = await _service.getBarberMenu(_barber!.id);
      if (mounted) setState(() => _menuItems = items);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _menuLoading = false);
    }
  }

  Future<void> _addOrEditMenuItem({BarberMenuItemModel? existing}) async {
    if (_barber == null) return;
    // Use a StatefulWidget dialog so controllers have a proper lifecycle
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _MenuItemDialog(existing: existing),
    );
    if (result == null) return;

    final name      = result['name']      as String;
    final price     = result['price']     as double;
    final queueType = result['queueType'] as String? ?? 'both';
    if (name.isEmpty) return;

    try {
      if (existing == null) {
        final item = await _service.addMenuItem(
            barberId: _barber!.id, name: name, price: price, queueType: queueType);
        if (mounted) setState(() => _menuItems.add(item));
      } else {
        await _service.updateMenuItem(
            id: existing.id, name: name, price: price, queueType: queueType);
        await _loadMenu();
      }
      if (mounted) _showMessage(existing == null ? 'تمت إضافة الخدمة' : 'تم تحديث الخدمة');
    } catch (e) {
      if (mounted) _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  Future<void> _toggleItemAvailability(BarberMenuItemModel item) async {
    try {
      await _service.updateMenuItem(
          id: item.id, isAvailable: !item.isAvailable);
      await _loadMenu();
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  Future<void> _deleteMenuItem(BarberMenuItemModel item) async {
    final confirmed = await _showConfirm(
        'حذف الخدمة', 'هل تريد حذف "${item.name}" من القائمة؟');
    if (!confirmed) return;
    try {
      await _service.deleteMenuItem(item.id);
      if (mounted) setState(() => _menuItems.remove(item));
      _showMessage('تم حذف الخدمة');
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  // ─── Queue Actions ────────────────────────────────────────

  Future<void> _nextCustomer() async {
    if (_barber == null) return;
    // Serve whoever joined first (global position order, no type priority)
    await _service.removeNextInQueue(_barber!.id);
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
                // ── Single "التالي" button (join-order, no type priority) ──
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _queue.isNotEmpty ? _nextCustomer : null,
                    icon: const Icon(Icons.skip_next_rounded, size: 20),
                    label: Text(
                      'التالي',
                      style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppTheme.textMuted.withValues(alpha: 0.25),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
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

        // ─── Unified Queue List ──────────────────────
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
                      children: [
                        // Chronological order — position reflects actual booking time
                        ..._queue.asMap().entries.map((e) {
                          final entry = e.value;
                          final isVip = entry.queueType == 'vip';
                          return _QueueEntryCard(
                            entry: entry,
                            isFirst: e.key == 0,
                            isVip: isVip,
                            onRemove: () => _removeCustomer(entry),
                          );
                        }),
                      ],
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

    return Column(
      children: [
        // ── Per-wallet account numbers header ─────────
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded,
                      color: Colors.white60, size: 16),
                  const SizedBox(width: 8),
                  Text('أرقام الحسابات حسب المحفظة',
                      style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 12),
              _buildBookingToggle(barber),
              const SizedBox(height: 14),
              // ── Active wallets ──────────────────────────
              if (barber.walletNumbers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: Text(
                      'لم تضف أي محفظة بعد\nاضغط على "إضافة محفظة" للبدء',
                      style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: Colors.white30,
                          height: 1.6),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                ...barber.walletNumbers.entries.map((entry) {
                  final key    = entry.key;
                  final number = entry.value;
                  final label  = kWallets.firstWhere(
                    (w) => w['key'] == key,
                    orElse: () => {'key': key, 'label': key},
                  )['label']!;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: Text(label,
                              style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(number,
                              style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppTheme.accent,
                                  letterSpacing: 2),
                              textDirection: TextDirection.ltr),
                        ),
                        // Copy
                        IconButton(
                          icon: const Icon(Icons.copy_rounded,
                              color: Colors.white38, size: 18),
                          tooltip: 'نسخ',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: number));
                            _showMessage('تم نسخ رقم $label');
                          },
                        ),
                        // Edit
                        IconButton(
                          icon: const Icon(Icons.edit_rounded,
                              color: Colors.white54, size: 18),
                          tooltip: 'تعديل',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          onPressed: () => _editWalletNumber(key, label),
                        ),
                        // Delete
                        IconButton(
                          icon: Icon(Icons.delete_rounded,
                              color: AppTheme.danger.withValues(alpha: 0.7),
                              size: 18),
                          tooltip: 'حذف',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 32, minHeight: 32),
                          onPressed: () => _deleteWallet(key, label),
                        ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 6),
              // ── Add wallet button ───────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: kWallets.every(
                          (w) => barber.walletNumbers.containsKey(w['key']))
                      ? null
                      : _addWallet,
                  icon: const Icon(Icons.add_rounded,
                      color: Colors.white70, size: 18),
                  label: Text('إضافة محفظة',
                      style: GoogleFonts.cairo(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
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

  // ─── Booking Toggle ──────────────────────────────────────

  Widget _buildBookingToggle(BarberModel barber) {
    final isLocked = barber.hidePaymentNumbers;
    return GestureDetector(
      onTap: () async {
        if (_barber == null) return;
        final newVal = !_barber!.hidePaymentNumbers;
        try {
          await _service.toggleHidePaymentNumbers(_barber!.id, newVal);
          _showMessage(newVal
              ? 'تم إيقاف الحجوزات الجديدة'
              : 'تم تفعيل الحجوزات الجديدة');
          await _loadData();
        } catch (e) {
          _showMessage(e.toString().replaceAll('Exception: ', ''),
              isError: true);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isLocked
              ? AppTheme.danger.withValues(alpha: 0.15)
              : Colors.green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isLocked
                ? AppTheme.danger.withValues(alpha: 0.5)
                : Colors.green.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: isLocked ? AppTheme.danger : Colors.green,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLocked ? 'الحجوزات مغلقة' : 'الحجوزات مفتوحة',
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isLocked ? AppTheme.danger : Colors.green,
                    ),
                  ),
                  Text(
                    isLocked
                        ? 'العملاء لا يرون أرقام الحسابات'
                        : 'العملاء يرون أرقام الحسابات',
                    style: GoogleFonts.cairo(
                        fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),
            Switch(
              value: !isLocked,
              onChanged: null,
              activeThumbColor: Colors.green,
              inactiveThumbColor: AppTheme.danger,
              inactiveTrackColor: AppTheme.danger.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Barber Profile Tab ───────────────────────────────────

  Widget _buildMarketingLink(String barberId) {
    final link = 'hallaqak://barber/$barberId';

    Future<void> copyLink() async {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        _showMessage('تم نسخ الرابط');
      }
    }

    Future<void> shareLink() async {
      await Share.share(
        'احجز مع حلاقك المفضل مباشرة عبر تطبيق حلاقك 💈\n$link',
        subject: 'رابط حجز مباشر',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary,
            AppTheme.primary.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.link_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'رابط التسويق الخاص بك',
                      style: GoogleFonts.cairo(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                    Text(
                      'شاركه مع عملائك لدخول صفحتك مباشرة',
                      style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Link display box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25)),
            ),
            child: Text(
              link,
              style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 12),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: copyLink,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text('نسخ',
                      style: GoogleFonts.cairo(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: shareLink,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.share_rounded, size: 16),
                  label: Text('مشاركة',
                      style: GoogleFonts.cairo(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

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
          // ─── Marketing Link ───────────────────────
          if (_barber != null) _buildMarketingLink(_barber!.id),
          const SizedBox(height: 24),
          // ─── TikTok Link ──────────────────────────
          TextField(
            controller: _tiktokCtrl,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'رابط TikTok',
              hintText: 'https://www.tiktok.com/@username',
              hintStyle: GoogleFonts.cairo(fontSize: 12),
              prefixIcon: const Padding(
                padding: EdgeInsets.all(12),
                child: FaIcon(FontAwesomeIcons.tiktok, size: 20, color: Color(0xFF010101)),
              ),
              suffixIcon: _tiktokCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () => setState(() => _tiktokCtrl.clear()),
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
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
          // ─── Logo above work images ───────────────
          Center(
            child: Image.asset(
              'assets/logo.png',
              height: 56,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 16),
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

  // ─── Menu Tab UI ─────────────────────────────────────────

  Widget _buildMenuTab() {
    if (_barber == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        // ── Header ────────────────────────────────────────
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'قائمة الخدمات',
                style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white),
              ),
              const SizedBox(height: 4),
              Text(
                'أضف خدماتك وحدّد لكل خدمة ما إذا كانت لـ VIP أو العادي أو الجميع',
                style: GoogleFonts.cairo(
                    fontSize: 12, color: Colors.white60),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _addOrEditMenuItem(),
                  icon: const Icon(Icons.add_rounded,
                      size: 20, color: AppTheme.primary),
                  label: Text('إضافة خدمة جديدة',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── List ──────────────────────────────────────────
        Expanded(
          child: _menuLoading
              ? const Center(child: CircularProgressIndicator())
              : _menuItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_book_rounded,
                              size: 64,
                              color: AppTheme.textMuted.withValues(alpha: 0.3)),
                          const SizedBox(height: 12),
                          Text(
                            'لا توجد خدمات بعد',
                            style: GoogleFonts.cairo(
                                fontSize: 16, color: AppTheme.textMuted),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'اضغط على "إضافة خدمة جديدة" للبدء',
                            style: GoogleFonts.cairo(
                                fontSize: 13, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                      itemCount: _menuItems.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final item = _menuItems[i];
                        return _MenuItemCard(
                          item: item,
                          onEdit: () => _addOrEditMenuItem(existing: item),
                          onToggle: () => _toggleItemAvailability(item),
                          onDelete: () => _deleteMenuItem(item),
                        );
                      },
                    ),
        ),
      ],
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
                  : _currentIndex == 2
                      ? 'الملف الشخصي'
                      : 'قائمة الخدمات',
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
      floatingActionButton: _currentIndex == 0 && barber != null && !_loading && !barber.isClosed
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
        type: BottomNavigationBarType.fixed,
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
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _menuItems.isNotEmpty,
              label: Text('${_menuItems.length}'),
              child: const Icon(Icons.menu_book_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: _menuItems.isNotEmpty,
              label: Text('${_menuItems.length}'),
              child: const Icon(Icons.menu_book_rounded),
            ),
            label: 'القائمة',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _currentIndex == 0
              ? _buildQueueTab()
              : _currentIndex == 1
                  ? _buildPaymentsTab()
                  : _currentIndex == 2
                      ? _buildProfileTab()
                      : _buildMenuTab(),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.userName ?? 'عميل',
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      // ── VIP badge ──────────────────────────────
                      if (isVip) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFB300)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFFFB300)
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded,
                                  size: 11,
                                  color: Color(0xFFFFB300)),
                              const SizedBox(width: 3),
                              Text(
                                'VIP',
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF7A5800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
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
                  // ── Selected services (if any) ───────────────
                  if (entry.selectedServices != null &&
                      entry.selectedServices!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        ...entry.selectedServices!.map((s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppTheme.accent
                                        .withValues(alpha: 0.25)),
                              ),
                              child: Text(
                                s['name'] as String? ?? '',
                                style: GoogleFonts.cairo(
                                    fontSize: 11,
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.w600),
                              ),
                            )),
                        if (entry.servicesTotal != null &&
                            entry.servicesTotal! > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF43A047)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: const Color(0xFF43A047)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '${entry.servicesTotal!.toStringAsFixed(entry.servicesTotal! == entry.servicesTotal!.roundToDouble() ? 0 : 2)} MRU',
                              style: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: const Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w700),
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                      ],
                    ),
                  ],
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

          // ── Selected services (if any) ──────────────
          if (p.selectedServices != null &&
              p.selectedServices!.isNotEmpty) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long_rounded,
                          size: 14, color: queueColor),
                      const SizedBox(width: 6),
                      Text(
                        'الخدمة المطلوبة',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...p.selectedServices!.map((s) {
                    final price =
                        (s['price'] as num?)?.toDouble() ?? 0.0;
                    final priceStr = price == price.roundToDouble()
                        ? '${price.toInt()} MRU'
                        : '${price.toStringAsFixed(2)} MRU';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: queueColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s['name']?.toString() ?? '',
                              style: GoogleFonts.cairo(
                                fontSize: 13,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            priceStr,
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: queueColor,
                            ),
                            textDirection: TextDirection.ltr,
                          ),
                        ],
                      ),
                    );
                  }),
                  // Services total
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'المجموع',
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                          ),
                        ),
                        Text(
                          () {
                            final t = p.selectedServices!.fold(
                              0.0,
                              (sum, s) =>
                                  sum +
                                  ((s['price'] as num?)
                                          ?.toDouble() ??
                                      0.0),
                            );
                            return t == t.roundToDouble()
                                ? '${t.toInt()} MRU'
                                : '${t.toStringAsFixed(2)} MRU';
                          }(),
                          style: GoogleFonts.cairo(
                            fontSize: 14,
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
            ),
          ],

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

// ─── Menu Item Card ───────────────────────────────────────────
class _MenuItemCard extends StatelessWidget {
  final BarberMenuItemModel item;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _MenuItemCard({
    required this.item,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  static Color _qtColor(String qt) {
    switch (qt) {
      case 'vip':    return const Color(0xFFFFB300);
      case 'normal': return AppTheme.accent;
      default:       return AppTheme.success;
    }
  }

  static String _qtLabel(String qt) {
    switch (qt) {
      case 'vip':    return '⭐ VIP';
      case 'normal': return 'عادي';
      default:       return 'الجميع';
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = item.isAvailable;
    final priceStr = item.price == item.price.roundToDouble()
        ? item.price.toInt().toString()
        : item.price.toStringAsFixed(2);
    final qtColor = _qtColor(item.queueType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: available
              ? AppTheme.accent.withValues(alpha: 0.25)
              : AppTheme.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Availability dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: available ? AppTheme.success : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          // Queue-type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: qtColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: qtColor.withValues(alpha: 0.35)),
            ),
            child: Text(
              _qtLabel(item.queueType),
              style: GoogleFonts.cairo(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: qtColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name
          Expanded(
            child: Text(
              item.name,
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: available ? AppTheme.primary : AppTheme.textMuted,
                decoration:
                    available ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
          // Price badge
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: available
                  ? AppTheme.accent.withValues(alpha: 0.1)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$priceStr MRU',
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: available ? AppTheme.accent : AppTheme.textMuted,
              ),
              textDirection: TextDirection.ltr,
            ),
          ),
          const SizedBox(width: 4),
          // Toggle availability
          IconButton(
            icon: Icon(
              available
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              size: 20,
              color: available ? AppTheme.accent : AppTheme.textMuted,
            ),
            onPressed: onToggle,
            tooltip: available ? 'إخفاء' : 'إظهار',
          ),
          // Edit
          IconButton(
            icon: const Icon(Icons.edit_rounded,
                size: 20, color: AppTheme.primary),
            onPressed: onEdit,
            tooltip: 'تعديل',
          ),
          // Delete
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                size: 20, color: AppTheme.danger),
            onPressed: onDelete,
            tooltip: 'حذف',
          ),
        ],
      ),
    );
  }
}

// ─── Menu Item Dialog (StatefulWidget — avoids controller disposal crash) ────
class _MenuItemDialog extends StatefulWidget {
  final BarberMenuItemModel? existing;
  const _MenuItemDialog({this.existing});

  @override
  State<_MenuItemDialog> createState() => _MenuItemDialogState();
}

class _MenuItemDialogState extends State<_MenuItemDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late String _queueType; // 'vip' | 'normal' | 'both'

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    _nameCtrl  = TextEditingController(text: ex?.name ?? '');
    _priceCtrl = TextEditingController(
      text: ex != null
          ? ex.price.toStringAsFixed(
              ex.price == ex.price.roundToDouble() ? 0 : 2)
          : '',
    );
    _queueType = ex?.queueType ?? 'both';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name  = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0.0;
    if (name.isEmpty) return;
    Navigator.pop(context, {'name': name, 'price': price, 'queueType': _queueType});
  }

  Widget _queueChip(String value, String label, IconData icon, Color color) {
    final selected = _queueType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _queueType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : Colors.grey.shade300,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? color : AppTheme.textMuted),
              const SizedBox(height: 3),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? color : AppTheme.textMuted,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isNew ? 'إضافة خدمة جديدة' : 'تعديل الخدمة',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textDirection: TextDirection.rtl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                hintText: 'اسم الخدمة (مثال: قص شعر)',
                prefixIcon: const Icon(Icons.content_cut_rounded,
                    color: AppTheme.accent),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: '0.00',
                prefixIcon: const Icon(Icons.payments_rounded,
                    color: AppTheme.accent),
                suffixText: 'MRU',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            // Queue type selector
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'تُعرض لـ:',
                style: GoogleFonts.cairo(
                    fontSize: 12, color: AppTheme.textMuted),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _queueChip('vip',    'VIP فقط', Icons.star_rounded,   const Color(0xFFFFB300)),
                const SizedBox(width: 6),
                _queueChip('both',   'الجميع',  Icons.people_rounded, AppTheme.success),
                const SizedBox(width: 6),
                _queueChip('normal', 'عادي فقط', Icons.person_rounded, AppTheme.accent),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent),
            child: Text(isNew ? 'إضافة' : 'حفظ',
                style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }
}
