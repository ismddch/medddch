import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';

class MyBookingScreen extends StatefulWidget {
  const MyBookingScreen({super.key});
  @override
  State<MyBookingScreen> createState() => _MyBookingScreenState();
}

class _MyBookingScreenState extends State<MyBookingScreen> {
  final SupabaseService _service = SupabaseService();
  QueueEntryModel? _entry;
  bool _loading = true;
  bool _leaving = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    if (_channel != null) _service.unsubscribe(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final entry = await _service.getMyActiveQueueEntry(userId);
      if (!mounted) return;
      setState(() {
        _entry = entry;
        _loading = false;
      });
      _subscribeLive(userId);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _subscribeLive(String userId) {
    _channel?.unsubscribe();
    _channel = _service.subscribeToQueues(() {
      if (mounted) _load();
    });
  }

  Future<void> _leaveQueue() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('مغادرة الطابور', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text('هل تريد مغادرة الطابور؟', style: GoogleFonts.cairo()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('مغادرة', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _leaving = true);
    try {
      await _service.leaveQueue(userId);
      if (mounted) setState(() { _entry = null; _leaving = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _leaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', ''), style: GoogleFonts.cairo()),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStandalone = ModalRoute.of(context)?.canPop ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text('حجزي', style: GoogleFonts.cairo(fontWeight: FontWeight.w800)),
        centerTitle: true,
        leading: isStandalone
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _entry == null ? _buildEmpty() : _buildActive(),
            ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_available_rounded,
                    size: 54, color: AppTheme.accent),
              ),
              const SizedBox(height: 24),
              Text('لا يوجد حجز حالي',
                  style: GoogleFonts.cairo(
                      fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.primary)),
              const SizedBox(height: 8),
              Text('أنت لست في أي طابور الآن',
                  style: GoogleFonts.cairo(fontSize: 14, color: AppTheme.textMuted)),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () {
                  if (ModalRoute.of(context)?.canPop == true) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.content_cut_rounded, size: 18),
                label: Text('تصفح الحلاقين', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActive() {
    final e = _entry!;
    final pos = e.position;
    final queueType = e.queueType == 'vip' ? 'VIP' : 'عادي';
    final waitMin = pos * 45;
    final waitLabel = waitMin == 0
        ? 'أنت التالي!'
        : waitMin < 60
            ? 'وقت الانتظار ~$waitMin دقيقة'
            : 'وقت الانتظار ~${(waitMin / 60).toStringAsFixed(1)} ساعة';

    final posColor = pos == 1
        ? AppTheme.success
        : pos <= 3
            ? AppTheme.accent
            : AppTheme.primary;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ─── Status card ────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.25),
              blurRadius: 20, offset: const Offset(0, 8),
            )],
          ),
          child: Column(
            children: [
              Text('مرتبتك في الطابور',
                  style: GoogleFonts.cairo(fontSize: 13, color: Colors.white60)),
              const SizedBox(height: 8),
              Text('$pos',
                  style: GoogleFonts.cairo(
                      fontSize: 72, fontWeight: FontWeight.w900, color: Colors.white,
                      height: 1)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: posColor.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  pos == 1 ? 'حان دورك — توجه الآن!' : waitLabel,
                  style: GoogleFonts.cairo(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ─── Barber info card ────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent.withValues(alpha: 0.12),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3), width: 2),
                ),
                child: const Icon(Icons.content_cut_rounded, color: AppTheme.accent, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (e.barberName != null)
                      Text(e.barberName!,
                          style: GoogleFonts.cairo(
                              fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                    if (e.shopName != null) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.storefront_rounded, size: 13, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Text(e.shopName!,
                            style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textMuted)),
                      ]),
                    ],
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('طابور $queueType',
                          style: GoogleFonts.cairo(
                              fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.accent)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ─── Queue position chips ────────────────────────────────
        Row(children: [
          _InfoChip(
            icon: Icons.people_rounded,
            label: '$pos في الطابور',
            color: posColor,
          ),
          const SizedBox(width: 12),
          _InfoChip(
            icon: Icons.access_time_rounded,
            label: waitMin == 0 ? 'الآن' : '~$waitMin د',
            color: AppTheme.accent,
          ),
        ]),

        const SizedBox(height: 28),

        // ─── Leave queue button ──────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _leaving ? null : _leaveQueue,
            icon: _leaving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.danger))
                : const Icon(Icons.exit_to_app_rounded, color: AppTheme.danger),
            label: Text('مغادرة الطابور',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700, color: AppTheme.danger)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.danger),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}
