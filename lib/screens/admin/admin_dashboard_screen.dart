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

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final SupabaseService _service = SupabaseService();
  List<BarberModel> _barbers = [];
  Map<String, int> _stats = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final barbers = await _service.getAllBarbers();
      final stats = await _service.getAdminStats();
      if (mounted) {
        setState(() {
          _barbers = barbers;
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

  Future<void> _deleteBarber(BarberModel barber) async {
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
            'هل أنت متأكد من حذف "${barber.name}"؟\nسيتم حذف جميع الكراسي والطوابير المرتبطة.',
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
      await _service.deleteBarber(barber.id);
      _loadData();
    }
  }

  Future<void> _toggleActive(BarberModel barber) async {
    await _service.toggleBarberActive(barber.id, !barber.isActive);
    _loadData();
  }

  Future<void> _openProductsPicker() async {
    if (_barbers.isEmpty) return;
    if (_barbers.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductsScreen(barberId: _barbers.first.id),
        ),
      );
      return;
    }
    final picked = await showModalBottomSheet<BarberModel>(
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
              ..._barbers.map((b) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.accent.withOpacity(0.1),
                      backgroundImage: b.imageUrl != null
                          ? NetworkImage(b.imageUrl!)
                          : null,
                      child: b.imageUrl == null
                          ? const Icon(Icons.content_cut_rounded,
                              color: AppTheme.accent, size: 20)
                          : null,
                    ),
                    title: Text(b.name,
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                    subtitle: Text('الرمز: ${b.code}',
                        style: GoogleFonts.cairo(
                            fontSize: 12, color: AppTheme.textMuted)),
                    onTap: () => Navigator.pop(ctx, b),
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
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BarberFormScreen()),
          );
          _loadData();
        },
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: Text('إضافة صالون',
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
                              value: '${_stats['barbers'] ?? 0}',
                            ),
                            _StatTile(
                              icon: Icons.people_rounded,
                              label: 'عملاء',
                              value: '${_stats['customers'] ?? 0}',
                            ),
                            _StatTile(
                              icon: Icons.chair_rounded,
                              label: 'كراسي',
                              value: '${_stats['chairs'] ?? 0}',
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
                      'الصالونات (${_barbers.length})',
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ─── Barber Cards ──────────────────
                  if (_barbers.isEmpty)
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
                    ...List.generate(_barbers.length, (index) {
                      final barber = _barbers[index];
                      return _BarberCard(
                        barber: barber,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  BarberDetailScreen(barber: barber),
                            ),
                          );
                          _loadData();
                        },
                        onToggle: () => _toggleActive(barber),
                        onDelete: () => _deleteBarber(barber),
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

// ─── Barber Card Widget ───────────────────────────────────────
class _BarberCard extends StatelessWidget {
  final BarberModel barber;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _BarberCard({
    required this.barber,
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
            color: barber.isActive
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
                  color: barber.isActive
                      ? AppTheme.accent.withOpacity(0.3)
                      : AppTheme.textMuted.withOpacity(0.2),
                  width: 2,
                ),
                image: barber.imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(barber.imageUrl!),
                        fit: BoxFit.cover,
                        colorFilter: barber.isActive
                            ? null
                            : const ColorFilter.mode(
                                Colors.grey, BlendMode.saturation),
                      )
                    : null,
                color: AppTheme.surface,
              ),
              child: barber.imageUrl == null
                  ? Icon(Icons.content_cut_rounded,
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
                          barber.name,
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: barber.isActive
                                ? AppTheme.primary
                                : AppTheme.textMuted,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: barber.isActive
                              ? AppTheme.success.withOpacity(0.1)
                              : AppTheme.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          barber.isActive ? 'نشط' : 'معطل',
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: barber.isActive
                                ? AppTheme.success
                                : AppTheme.danger,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'الرمز: ${barber.code}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  if (barber.address != null)
                    Text(
                      barber.address!,
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
                    barber.isActive
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                    color: barber.isActive
                        ? AppTheme.textMuted
                        : AppTheme.success,
                    size: 24,
                  ),
                  onPressed: onToggle,
                  tooltip: barber.isActive ? 'تعطيل' : 'تفعيل',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 36, minHeight: 36),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: AppTheme.danger, size: 22),
                  onPressed: onDelete,
                  tooltip: 'حذف',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
