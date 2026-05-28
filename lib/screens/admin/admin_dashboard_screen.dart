import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/models.dart';
import '../../services/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';
import '../login_screen.dart';
import '../products_screen.dart';
import 'barber_form_screen.dart';
import 'barber_detail_screen.dart';
import 'user_management_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final SupabaseService _service = SupabaseService();
  List<ShopModel> _shops = [];
  Map<String, int> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final shops = await _service.getAllShops();
      final stats = await _service.getAdminStats();
      if (mounted) {
        setState(() {
          _shops = shops;
          _stats = stats;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _deleteShop(ShopModel shop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('حذف الصالون',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text(
            'هل أنت متأكد من حذف "${shop.name}"؟\nسيتم حذف جميع الحلاقين والطوابير المرتبطة.',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              child: Text('حذف', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      await _service.deleteShop(shop.id);
      _loadData();
    }
  }

  Future<void> _toggleActive(ShopModel shop) async {
    await _service.toggleShopActive(shop.id, !shop.isActive);
    _loadData();
  }

  // ─── Quick-action sheet ───────────────────────────────────────
  void _showActions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'إجراءات سريعة',
                style: GoogleFonts.cairo(
                    fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _ActionTile(
                icon: Icons.store_rounded,
                color: AppTheme.accent,
                title: 'إضافة صالون جديد',
                subtitle: 'إنشاء صالون حلاقة جديد',
                onTap: () async {
                  Navigator.pop(ctx);
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const BarberFormScreen()),
                  );
                  _loadData();
                },
              ),
              const SizedBox(height: 10),
              _ActionTile(
                icon: Icons.content_cut_rounded,
                color: AppTheme.primary,
                title: 'إضافة حلاق إلى صالون',
                subtitle: 'إضافة حلاق بدون حساب دخول',
                onTap: () {
                  Navigator.pop(ctx);
                  _showAddBarberDialog();
                },
              ),
              const SizedBox(height: 10),
              _ActionTile(
                icon: Icons.person_add_rounded,
                color: AppTheme.success,
                title: 'إنشاء حساب حلاق',
                subtitle: 'حلاق مع حساب دخول للتطبيق',
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreateBarberAccountDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Returns the selected shop, or null if cancelled / no shops exist.
  Future<ShopModel?> _pickShop() async {
    if (_shops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('لا توجد صالونات — أضف صالوناً أولاً',
              style: GoogleFonts.cairo()),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return null;
    }
    if (_shops.length == 1) return _shops.first;

    return showModalBottomSheet<ShopModel>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('اختر الصالون',
                  style: GoogleFonts.cairo(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ..._shops.map((s) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.accent.withOpacity(0.1),
                      backgroundImage: s.imageUrl != null
                          ? NetworkImage(s.imageUrl!)
                          : null,
                      child: s.imageUrl == null
                          ? const Icon(Icons.store_rounded,
                              color: AppTheme.accent, size: 20)
                          : null,
                    ),
                    title: Text(s.name,
                        style:
                            GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    subtitle: Text('الرمز: ${s.code}',
                        style: GoogleFonts.cairo(
                            fontSize: 12, color: AppTheme.textMuted)),
                    onTap: () => Navigator.pop(ctx, s),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddBarberDialog() async {
    final shop = await _pickShop();
    if (shop == null || !mounted) return;

    final nameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('إضافة حلاق',
                  style:
                      GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              Text(
                'في صالون ${shop.name}',
                style: GoogleFonts.cairo(
                    fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'اسم الحلاق',
                prefixIcon: Icon(Icons.content_cut_rounded,
                    color: AppTheme.accent),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty)
                      ? 'أدخل اسم الحلاق'
                      : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, nameCtrl.text.trim());
                }
              },
              child: Text('إضافة', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    if (name == null || !mounted) return;

    try {
      await _service.addBarber(shop.id, name);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('تم إضافة الحلاق بنجاح', style: GoogleFonts.cairo()),
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
                style: GoogleFonts.cairo()),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _showCreateBarberAccountDialog() async {
    final shop = await _pickShop();
    if (shop == null || !mounted) return;

    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('إنشاء حساب حلاق',
                  style:
                      GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              Text(
                'في صالون ${shop.name}',
                style: GoogleFonts.cairo(
                    fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'اسم الحلاق',
                      prefixIcon: Icon(Icons.person_outline,
                          color: AppTheme.accent),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'أدخل الاسم' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      hintText: 'رقم الهاتف',
                      prefixIcon: Icon(Icons.phone_outlined,
                          color: AppTheme.accent),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'أدخل رقم الهاتف'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passCtrl,
                    decoration: const InputDecoration(
                      hintText: 'كلمة المرور',
                      prefixIcon: Icon(Icons.lock_outline,
                          color: AppTheme.accent),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty)
                        return 'أدخل كلمة المرور';
                      if (v.length < 4) return 'كلمة المرور قصيرة جداً';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, {
                    'name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim(),
                    'password': passCtrl.text.trim(),
                  });
                }
              },
              child: Text('إنشاء', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    phoneCtrl.dispose();
    passCtrl.dispose();
    if (result == null || !mounted) return;

    try {
      await _service.createBarberWithUser(
        shopId: shop.id,
        name: result['name']!,
        phone: result['phone']!,
        password: result['password']!,
      );
      _loadData();
      if (mounted) {
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
                style: GoogleFonts.cairo()),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _openProductsPicker() async {
    if (_shops.isEmpty) return;
    if (_shops.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductsScreen(barberId: _shops.first.id),
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<ShopModel>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text('اختر الصالون',
                  style: GoogleFonts.cairo(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              ..._shops.map((s) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.accent.withOpacity(0.1),
                      backgroundImage: s.imageUrl != null
                          ? NetworkImage(s.imageUrl!)
                          : null,
                      child: s.imageUrl == null
                          ? const Icon(Icons.store_rounded,
                              color: AppTheme.accent, size: 20)
                          : null,
                    ),
                    title: Text(s.name,
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    subtitle: Text('الرمز: ${s.code}',
                        style: GoogleFonts.cairo(
                            fontSize: 12, color: AppTheme.textMuted)),
                    onTap: () => Navigator.pop(ctx, s),
                  )),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductsScreen(barberId: picked.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة تحكم المدير'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.people_rounded),
            tooltip: 'إدارة المستخدمين',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const UserManagementScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.shopping_bag_outlined),
            onPressed: _openProductsPicker,
            tooltip: 'إدارة المنتجات',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _logout,
            tooltip: 'تسجيل الخروج',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showActions,
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('إجراء جديد',
            style: GoogleFonts.cairo(
                fontWeight: FontWeight.w700, color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  // ─── Stats Header ──────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(24),
                        bottomRight: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.admin_panel_settings_rounded,
                              color: AppTheme.accent, size: 32),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'مرحباً بالمدير',
                          style: GoogleFonts.cairo(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // ─── Stats Row ───────────────
                        Row(
                          children: [
                            _StatTile(
                              icon: Icons.store_rounded,
                              label: 'صالونات',
                              value: '${_stats['shops'] ?? 0}',
                            ),
                            _StatTile(
                              icon: Icons.content_cut_rounded,
                              label: 'حلاقون',
                              value: '${_stats['barbers'] ?? 0}',
                            ),
                            _StatTile(
                              icon: Icons.people_rounded,
                              label: 'عملاء',
                              value: '${_stats['customers'] ?? 0}',
                            ),
                            _StatTile(
                              icon: Icons.queue_rounded,
                              label: 'في الطابور',
                              value: '${_stats['inQueue'] ?? 0}',
                              highlight: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ─── Section Title ─────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'الصالونات (${_shops.length})',
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ─── Shop Cards ────────────────────
                  if (_shops.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.store_outlined,
                                size: 64,
                                color: AppTheme.textMuted.withOpacity(0.3)),
                            const SizedBox(height: 12),
                            Text(
                              'لا توجد صالونات بعد\nاضغط "إضافة صالون" للبدء',
                              style: GoogleFonts.cairo(
                                  color: AppTheme.textMuted, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...List.generate(_shops.length, (index) {
                      final shop = _shops[index];
                      return _ShopCard(
                        shop: shop,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  BarberDetailScreen(shop: shop),
                            ),
                          );
                          _loadData();
                        },
                        onToggle: () => _toggleActive(shop),
                        onDelete: () => _deleteShop(shop),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

// ─── Stat Tile Widget ─────────────────────────────────────────
class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: highlight
              ? AppTheme.accent.withOpacity(0.15)
              : Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: highlight ? AppTheme.accent : Colors.white60,
                size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.cairo(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: highlight ? AppTheme.accent : Colors.white,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.cairo(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shop Card Widget ─────────────────────────────────────────
class _ShopCard extends StatelessWidget {
  final ShopModel shop;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _ShopCard({
    required this.shop,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: shop.isActive
                ? AppTheme.divider
                : AppTheme.danger.withOpacity(0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // ─── Photo ─────────────────────────
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: shop.isActive
                      ? AppTheme.accent.withOpacity(0.3)
                      : AppTheme.textMuted.withOpacity(0.2),
                  width: 2,
                ),
                image: shop.imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(shop.imageUrl!),
                        fit: BoxFit.cover,
                        colorFilter: shop.isActive
                            ? null
                            : const ColorFilter.mode(
                                Colors.grey, BlendMode.saturation),
                      )
                    : null,
                color: AppTheme.surface,
              ),
              child: shop.imageUrl == null
                  ? Icon(Icons.store_rounded,
                      color: AppTheme.textMuted, size: 28)
                  : null,
            ),
            const SizedBox(width: 14),

            // ─── Info ──────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          shop.name,
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: shop.isActive
                                ? AppTheme.primary
                                : AppTheme.textMuted,
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (shop.vipEnabled)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB300)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
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
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFFFB300),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (shop.prepaymentEnabled)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.accent
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.payment_rounded,
                                      size: 11, color: AppTheme.accent),
                                  const SizedBox(width: 3),
                                  Text(
                                    'دفع',
                                    style: GoogleFonts.cairo(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: shop.isActive
                                  ? AppTheme.success.withValues(alpha: 0.1)
                                  : AppTheme.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              shop.isActive ? 'نشط' : 'معطل',
                              style: GoogleFonts.cairo(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: shop.isActive
                                    ? AppTheme.success
                                    : AppTheme.danger,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'الرمز: ${shop.code}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  if (shop.address != null)
                    Text(
                      shop.address!,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // ─── Actions ───────────────────────
            Column(
              children: [
                IconButton(
                  icon: Icon(
                    shop.isActive
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                    color: shop.isActive
                        ? AppTheme.textMuted
                        : AppTheme.success,
                    size: 24,
                  ),
                  onPressed: onToggle,
                  tooltip: shop.isActive ? 'تعطيل' : 'تفعيل',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppTheme.danger, size: 22),
                  onPressed: onDelete,
                  tooltip: 'حذف',
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Action Tile Widget (used in quick-actions bottom sheet) ──
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.cairo(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        style: GoogleFonts.cairo(
                            fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  size: 16, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
