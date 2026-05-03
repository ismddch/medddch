import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'chair_dashboard_screen.dart';
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
  BarberModel? _barber;
  bool _loading = true;
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
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = context.read<AuthProvider>().user;
    if (user == null || user.barberId == null) return;
    try {
      final chairs = await _service.getChairs(user.barberId!);
      final barber = await _service.getBarberById(user.barberId!);
      final Map<String, List<QueueEntryModel>> queues = {};
      for (final chair in chairs) {
        queues[chair.id] = await _service.getQueueForChair(chair.id);
      }
      if (mounted) {
        setState(() {
          _chairs = chairs;
          _barber = barber;
          _queuesByChair = queues;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectChair(ChairModel chair) async {
    if (_barber == null) return;

    if (chair.isClosed) {
      final confirmed = await _showConfirm(
        'فتح الكرسي',
        'الكرسي "${chair.name}" مغلق، هل تريد فتحه والعمل عليه؟',
      );
      if (!confirmed || !mounted) return;
      await _service.toggleChairClosed(chair.id, false);
      await _loadData();
      if (!mounted) return;
      // Re-fetch updated chair
      final updated = _chairs.cast<ChairModel?>().firstWhere(
            (c) => c!.id == chair.id,
            orElse: () => null,
          );
      if (updated == null) return;
      chair = updated;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChairDashboardScreen(
          chair: chair,
          barber: _barber!,
        ),
      ),
    );
    // Refresh queue counts when returning
    _loadData();
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
                  backgroundColor: AppTheme.accent),
              child: Text('فتح وعمل', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
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
          'هل أنت متأكد أنك تريد حذف حسابك نهائياً؟ لا يمكن التراجع عن هذا الإجراء.',
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
    final success =
        await context.read<AuthProvider>().deleteCurrentUserAccount();
    if (success && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: Text('اختر كرسيك', style: GoogleFonts.cairo()),
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'logout') _logout();
              if (v == 'delete') _confirmDeleteAccount();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'logout',
                child: Row(children: [
                  const Icon(Icons.logout_rounded, size: 20),
                  const SizedBox(width: 10),
                  Text('تسجيل الخروج',
                      style: GoogleFonts.cairo(fontSize: 14)),
                ]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  const Icon(Icons.delete_forever_rounded,
                      size: 20, color: Colors.red),
                  const SizedBox(width: 10),
                  Text('حذف الحساب',
                      style: GoogleFonts.cairo(
                          fontSize: 14, color: Colors.red)),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ─── Header ──────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(28),
                      bottomRight: Radius.circular(28),
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
                                    image:
                                        NetworkImage(_barber!.imageUrl!),
                                    fit: BoxFit.cover)
                                : null,
                            color: AppTheme.accent.withValues(alpha: 0.2),
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
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        'مرحباً ${user?.name ?? ''} — اختر الكرسي الذي ستعمل عليه',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // ─── Chair Grid ───────────────────────────────
                Expanded(
                  child: _chairs.isEmpty
                      ? Center(
                          child: Text(
                            'لا توجد كراسي — تواصل مع المدير',
                            style: GoogleFonts.cairo(
                                color: AppTheme.textMuted, fontSize: 15),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.all(20),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 1.05,
                          ),
                          itemCount: _chairs.length,
                          itemBuilder: (_, i) {
                            final chair = _chairs[i];
                            final count =
                                _queuesByChair[chair.id]?.length ?? 0;
                            return GestureDetector(
                              onTap: () => _selectChair(chair),
                              child: Opacity(
                                opacity: chair.isClosed ? 0.7 : 1.0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(20),
                                    border: Border.all(
                                        color: AppTheme.divider),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primary
                                            .withValues(alpha: 0.05),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: chair.isClosed
                                              ? AppTheme.textMuted
                                                  .withValues(alpha: 0.1)
                                              : AppTheme.accent
                                                  .withValues(alpha: 0.1),
                                          image: chair.imageUrl != null
                                              ? DecorationImage(
                                                  image: NetworkImage(
                                                      chair.imageUrl!),
                                                  fit: BoxFit.cover)
                                              : null,
                                        ),
                                        child: chair.imageUrl == null
                                            ? Icon(
                                                chair.isClosed
                                                    ? Icons.lock_rounded
                                                    : Icons.chair_rounded,
                                                color: chair.isClosed
                                                    ? AppTheme.textMuted
                                                    : AppTheme.accent,
                                                size: 30,
                                              )
                                            : null,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        chair.name,
                                        style: GoogleFonts.cairo(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                          color: chair.isClosed
                                              ? AppTheme.textMuted
                                              : AppTheme.primary,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: chair.isClosed
                                              ? AppTheme.danger
                                                  .withValues(alpha: 0.08)
                                              : AppTheme.success
                                                  .withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          chair.isClosed
                                              ? 'مغلق'
                                              : '$count في الانتظار',
                                          style: GoogleFonts.cairo(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: chair.isClosed
                                                ? AppTheme.danger
                                                : AppTheme.success,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
