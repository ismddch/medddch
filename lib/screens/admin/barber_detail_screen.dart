import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/models.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';
import '../products_screen.dart';
import 'barber_form_screen.dart';

// Detail screen for a ShopModel (salon).
// Shows staff barbers (BarberModel list), VIP/prepayment toggles,
// ability to create barber accounts, and products management.

class BarberDetailScreen extends StatefulWidget {
  final ShopModel shop;

  const BarberDetailScreen({super.key, required this.shop});

  @override
  State<BarberDetailScreen> createState() => _BarberDetailScreenState();
}

class _BarberDetailScreenState extends State<BarberDetailScreen> {
  final SupabaseService _service = SupabaseService();
  ShopModel? _shop;
  List<BarberModel> _barbers = [];
  List<QueueEntryModel> _queueEntries = [];
  Set<String> _linkedBarberIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final shop = await _service.getShopById(widget.shop.id);
      final barbers = await _service.getBarbers(widget.shop.id);
      final queue = await _service.getShopQueue(widget.shop.id);
      final linkedIds = await _service.getBarberLinkedUserIds(widget.shop.id);
      if (mounted) {
        setState(() {
          _shop = shop ?? widget.shop;
          _barbers = barbers;
          _queueEntries = queue;
          _linkedBarberIds = linkedIds;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addBarber() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => const _BarberFormDialog(),
    );
    if (result != null) {
      await _service.addBarber(
        widget.shop.id,
        result['name']!,
        imageUrl: result['image_url']?.isEmpty == true ? null : result['image_url'],
        location: result['location']?.isEmpty == true ? null : result['location'],
      );
      _loadData();
    }
  }

  Future<void> _editBarber(BarberModel barber) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _BarberFormDialog(barber: barber),
    );
    if (result != null) {
      await _service.updateBarber(
        barber.id,
        name: result['name']!,
        imageUrl: result['image_url']?.isEmpty == true ? null : result['image_url'],
        location: result['location']?.isEmpty == true ? null : result['location'],
      );
      _loadData();
    }
  }

  Future<void> _deleteBarber(BarberModel barber) async {
    final confirmed = await _showConfirmDialog(
      title: 'حذف الحلاق',
      message: 'هل تريد حذف "${barber.name}"؟ سيتم حذف الطابور المرتبط.',
    );
    if (confirmed) {
      await _service.deleteBarber(barber.id);
      _loadData();
    }
  }

  Future<void> _createBarberAccount() async {
    final shop = _shop ?? widget.shop;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _CreateBarberAccountDialog(shopName: shop.name),
    );
    if (result != null) {
      try {
        await _service.createBarberWithUser(
          shopId: widget.shop.id,
          name: result['name']!,
          phone: result['phone']!,
          password: result['password']!,
        );
        if (mounted) {
          _loadData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم إنشاء حساب الحلاق بنجاح',
                  style: GoogleFonts.cairo()),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e.toString().replaceAll('Exception: ', ''),
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: AppTheme.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    }
  }

  Future<void> _linkBarberAccount(BarberModel barber) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _LinkBarberAccountDialog(barberName: barber.name),
    );
    if (result != null) {
      try {
        await _service.createUserForBarber(
          barberId: barber.id,
          name: barber.name,
          phone: result['phone']!,
          password: result['password']!,
        );
        if (mounted) {
          _loadData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تم ربط حساب الحلاق بنجاح',
                  style: GoogleFonts.cairo()),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e.toString().replaceAll('Exception: ', ''),
                style: GoogleFonts.cairo(),
              ),
              backgroundColor: AppTheme.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    }
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
  }) async {
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
              child: Text('حذف', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final shop = _shop ?? widget.shop;

    return Scaffold(
      appBar: AppBar(
        title: Text(shop.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'تعديل',
            onPressed: () async {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BarberFormScreen(shop: shop),
                ),
              );
              if (updated == true) _loadData();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  // ─── Shop Profile Header ───────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Photo
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppTheme.accent, width: 3),
                            image: shop.imageUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(shop.imageUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            color: AppTheme.accent.withOpacity(0.2),
                          ),
                          child: shop.imageUrl == null
                              ? const Icon(Icons.store_rounded,
                                  color: AppTheme.accent, size: 44)
                              : null,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          shop.name,
                          style: GoogleFonts.cairo(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'الرمز: ${shop.code}',
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Info row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (shop.phone != null) ...[
                              const Icon(Icons.phone_outlined,
                                  color: Colors.white54, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                shop.phone!,
                                style: GoogleFonts.cairo(
                                    fontSize: 12, color: Colors.white54),
                                textDirection: TextDirection.ltr,
                              ),
                              const SizedBox(width: 16),
                            ],
                            if (shop.address != null) ...[
                              const Icon(Icons.location_on_outlined,
                                  color: Colors.white54, size: 14),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  shop.address!,
                                  style: GoogleFonts.cairo(
                                      fontSize: 12,
                                      color: Colors.white54),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Quick stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _MiniStat(
                              icon: Icons.content_cut_rounded,
                              value: '${_barbers.length}',
                              label: 'حلاقون',
                            ),
                            const SizedBox(width: 24),
                            _MiniStat(
                              icon: Icons.people_rounded,
                              value: '${_queueEntries.length}',
                              label: 'في الطابور',
                            ),
                            const SizedBox(width: 24),
                            _MiniStat(
                              icon: shop.isActive
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              value: shop.isActive ? 'نشط' : 'معطل',
                              label: 'الحالة',
                              color: shop.isActive
                                  ? AppTheme.success
                                  : AppTheme.danger,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ─── Barbers Section ───────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'الحلاقون (${_barbers.length})',
                            style: GoogleFonts.cairo(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addBarber,
                          icon: const Icon(Icons.add_rounded,
                              size: 20, color: AppTheme.accent),
                          label: Text('إضافة',
                              style: GoogleFonts.cairo(
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_barbers.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'لا يوجد حلاقون — اضغط "إضافة"',
                          style: GoogleFonts.cairo(
                              fontSize: 14, color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  else
                    ...List.generate(_barbers.length, (i) {
                      final barber = _barbers[i];
                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 5),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Row(
                          children: [
                            // ─── Barber Image ─────────────
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color:
                                      AppTheme.accent.withOpacity(0.3),
                                  width: 2,
                                ),
                                image: barber.imageUrl != null
                                    ? DecorationImage(
                                        image:
                                            NetworkImage(barber.imageUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                                color: AppTheme.accent.withOpacity(0.1),
                              ),
                              child: barber.imageUrl == null
                                  ? const Icon(Icons.content_cut_rounded,
                                      color: AppTheme.accent, size: 24)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    barber.name,
                                    style: GoogleFonts.cairo(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  Text(
                                    '${barber.queueLength} في الانتظار',
                                    style: GoogleFonts.cairo(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  if (_linkedBarberIds.contains(barber.id))
                                    Row(children: [
                                      const Icon(
                                          Icons.check_circle_rounded,
                                          color: AppTheme.success,
                                          size: 13),
                                      const SizedBox(width: 3),
                                      Text(
                                        'حساب نشط',
                                        style: GoogleFonts.cairo(
                                          fontSize: 11,
                                          color: AppTheme.success,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ])
                                  else
                                    Row(children: [
                                      const Icon(
                                          Icons.no_accounts_outlined,
                                          color: AppTheme.textMuted,
                                          size: 13),
                                      const SizedBox(width: 3),
                                      Text(
                                        'لا يوجد حساب',
                                        style: GoogleFonts.cairo(
                                          fontSize: 11,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                    ]),
                                ],
                              ),
                            ),
                            if (!_linkedBarberIds.contains(barber.id))
                              IconButton(
                                icon: const Icon(Icons.key_rounded,
                                    color: AppTheme.accent, size: 20),
                                onPressed: () =>
                                    _linkBarberAccount(barber),
                                tooltip: 'إنشاء حساب تسجيل دخول',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                    minWidth: 36, minHeight: 36),
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: AppTheme.accent, size: 20),
                              onPressed: () => _editBarber(barber),
                              tooltip: 'تعديل',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                            ),
                            IconButton(
                              icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: AppTheme.danger,
                                  size: 22),
                              onPressed: () => _deleteBarber(barber),
                              tooltip: 'حذف الحلاق',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 28),

                  // ─── VIP Privileges Section ────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'صلاحيات VIP',
                      style: GoogleFonts.cairo(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        secondary: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: (shop.vipEnabled
                                    ? const Color(0xFFFFB300)
                                    : AppTheme.textMuted)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.star_rounded,
                            color: shop.vipEnabled
                                ? const Color(0xFFFFB300)
                                : AppTheme.textMuted,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          'تفعيل طابور VIP',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          shop.vipEnabled
                              ? 'العملاء يمكنهم اختيار VIP أو عادي'
                              : 'الطابور العادي فقط متاح للعملاء',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        value: shop.vipEnabled,
                        activeThumbColor: const Color(0xFFFFB300),
                        onChanged: (val) async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await _service.toggleShopVip(shop.id, val);
                            await _loadData();
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString()
                                      .replaceAll('Exception: ', ''),
                                  style: GoogleFonts.cairo(),
                                ),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─── Prepayment Section ────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'الدفع المسبق',
                      style: GoogleFonts.cairo(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        secondary: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: (shop.prepaymentEnabled
                                    ? AppTheme.accent
                                    : AppTheme.textMuted)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.payment_rounded,
                            color: shop.prepaymentEnabled
                                ? AppTheme.accent
                                : AppTheme.textMuted,
                            size: 22,
                          ),
                        ),
                        title: Text(
                          'تفعيل الدفع المسبق',
                          style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          shop.prepaymentEnabled
                              ? 'العملاء يحجزون مسبقاً ويدفعون قبل الدخول'
                              : 'العملاء ينضمون للطابور مباشرة',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        value: shop.prepaymentEnabled,
                        activeThumbColor: AppTheme.accent,
                        onChanged: (val) async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await _service.toggleShopPrepayment(
                                shop.id, val);
                            await _loadData();
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  e.toString()
                                      .replaceAll('Exception: ', ''),
                                  style: GoogleFonts.cairo(),
                                ),
                                backgroundColor: AppTheme.danger,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(12)),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ─── Barber Account Section ────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'إنشاء حساب حلاق',
                      style: GoogleFonts.cairo(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _createBarberAccount,
                        icon: const Icon(Icons.person_add_alt_1_rounded,
                            size: 20),
                        label: Text('إنشاء حساب حلاق جديد في هذا الصالون',
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.accent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                ProductsScreen(barberId: widget.shop.id),
                          ),
                        ),
                        icon: const Icon(Icons.shopping_bag_outlined,
                            size: 20, color: Colors.white),
                        label: Text('إدارة منتجات الصالون',
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─── Mini Stat Widget ─────────────────────────────────────────
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color ?? Colors.white70, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color ?? Colors.white,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.cairo(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }
}

// ─── Create Barber Account Dialog ─────────────────────────────
// Creates both a barber record and a user login simultaneously via createBarberWithUser.
class _CreateBarberAccountDialog extends StatefulWidget {
  final String shopName;

  const _CreateBarberAccountDialog({required this.shopName});

  @override
  State<_CreateBarberAccountDialog> createState() =>
      _CreateBarberAccountDialogState();
}

class _CreateBarberAccountDialogState
    extends State<_CreateBarberAccountDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('إنشاء حساب حلاق',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            Text(
              'في صالون ${widget.shopName}',
              style: GoogleFonts.cairo(
                  fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'اسم الحلاق',
                    prefixIcon: const Icon(Icons.person_outline,
                        color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'أدخل الاسم' : null,
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
                      (v == null || v.isEmpty) ? 'أدخل رقم الهاتف' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  decoration: InputDecoration(
                    hintText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
                    if (v.length < 4) return 'كلمة المرور قصيرة';
                    return null;
                  },
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
                  'password': _passCtrl.text.trim(),
                });
              }
            },
            child: Text('إنشاء', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }
}

// ─── Link Barber Account Dialog ───────────────────────────────────────────
// Creates a users login record for an *existing* barbers record.
class _LinkBarberAccountDialog extends StatefulWidget {
  final String barberName;

  const _LinkBarberAccountDialog({required this.barberName});

  @override
  State<_LinkBarberAccountDialog> createState() =>
      _LinkBarberAccountDialogState();
}

class _LinkBarberAccountDialogState extends State<_LinkBarberAccountDialog> {
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ربط حساب تسجيل دخول',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            Text(
              'للحلاق: ${widget.barberName}',
              style: GoogleFonts.cairo(
                  fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                    (v == null || v.isEmpty) ? 'أدخل رقم الهاتف' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passCtrl,
                decoration: const InputDecoration(
                  hintText: 'كلمة المرور',
                  prefixIcon: Icon(Icons.lock_outline,
                      color: AppTheme.accent),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
                  if (v.length < 4) return 'كلمة المرور قصيرة جداً';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, {
                  'phone': _phoneCtrl.text.trim(),
                  'password': _passCtrl.text.trim(),
                });
              }
            },
            icon: const Icon(Icons.key_rounded, size: 18),
            label: Text('ربط', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }
}

// ─── Barber Form Dialog (Add / Edit staff barber) with Image Upload ─────
class _BarberFormDialog extends StatefulWidget {
  final BarberModel? barber;

  const _BarberFormDialog({this.barber});

  @override
  State<_BarberFormDialog> createState() => _BarberFormDialogState();
}

class _BarberFormDialogState extends State<_BarberFormDialog> {
  final SupabaseService _service = SupabaseService();
  final _picker = ImagePicker();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _locationCtrl;
  final _formKey = GlobalKey<FormState>();

  Uint8List? _pickedBytes;
  String? _pickedExt;
  String? _existingImageUrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.barber?.name ?? '');
    _locationCtrl = TextEditingController(text: widget.barber?.location ?? '');
    _existingImageUrl = widget.barber?.imageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );

    if (picked != null) {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      setState(() {
        _pickedBytes = bytes;
        _pickedExt = ext.isNotEmpty ? ext : 'jpg';
        _existingImageUrl = null;
      });
    }
  }

  void _removeImage() {
    setState(() {
      _pickedBytes = null;
      _pickedExt = null;
      _existingImageUrl = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    String? imageUrl = _existingImageUrl;

    if (_pickedBytes != null) {
      setState(() => _uploading = true);
      try {
        imageUrl = await _service.uploadImage(
          _pickedBytes!,
          fileExt: _pickedExt ?? 'jpg',
          folder: 'barbers',
        );
      } catch (e) {
        setState(() => _uploading = false);
        return;
      }
      setState(() => _uploading = false);
    }

    if (mounted) {
      Navigator.pop(context, {
        'name': _nameCtrl.text.trim(),
        'image_url': imageUrl ?? '',
        'location': _locationCtrl.text.trim(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.barber != null;
    final hasLocal = _pickedBytes != null;
    final hasNetwork =
        _existingImageUrl != null && _existingImageUrl!.isNotEmpty;
    final hasImage = hasLocal || hasNetwork;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isEdit ? 'تعديل الحلاق' : 'إضافة حلاق',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ─── Image Picker ──────────────
                Stack(
                  children: [
                    GestureDetector(
                      onTap: _uploading ? null : _pickImage,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppTheme.accent, width: 2.5),
                          color: AppTheme.primary.withOpacity(0.05),
                          image: hasLocal
                              ? DecorationImage(
                                  image: MemoryImage(_pickedBytes!),
                                  fit: BoxFit.cover,
                                )
                              : hasNetwork
                                  ? DecorationImage(
                                      image: NetworkImage(
                                          _existingImageUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                        ),
                        child: !hasImage
                            ? Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_a_photo_rounded,
                                      color: AppTheme.accent, size: 28),
                                  const SizedBox(height: 4),
                                  Text(
                                    'اختر صورة',
                                    style: GoogleFonts.cairo(
                                        fontSize: 10,
                                        color: AppTheme.textMuted),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                    if (hasImage && !_uploading)
                      Positioned(
                        top: -4,
                        left: -4,
                        child: GestureDetector(
                          onTap: _removeImage,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: AppTheme.danger,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    if (_uploading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                // ─── Name Field ────────────────
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: !hasImage,
                  decoration: InputDecoration(
                    hintText: 'اسم الحلاق (مثال: أحمد)',
                    prefixIcon: const Icon(Icons.content_cut_rounded,
                        color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'أدخل اسم الحلاق'
                          : null,
                ),
                const SizedBox(height: 12),
                // ─── Location Field ─────────────
                TextFormField(
                  controller: _locationCtrl,
                  decoration: const InputDecoration(
                    hintText: 'الموقع / المنطقة (مثال: الرياض)',
                    prefixIcon: Icon(Icons.location_on_outlined,
                        color: AppTheme.accent),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _uploading ? null : () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: _uploading ? null : _submit,
            child: _uploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    isEdit ? 'حفظ' : 'إضافة',
                    style: GoogleFonts.cairo(),
                  ),
          ),
        ],
      ),
    );
  }
}
