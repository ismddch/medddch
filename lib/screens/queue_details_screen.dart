import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';

const int _kMinutesPerPerson = 45;

class QueueDetailsScreen extends StatefulWidget {
  final ChairModel chair;

  const QueueDetailsScreen({super.key, required this.chair});

  @override
  State<QueueDetailsScreen> createState() => _QueueDetailsScreenState();
}

class _QueueDetailsScreenState extends State<QueueDetailsScreen> {
  final SupabaseService _service = SupabaseService();
  List<QueueEntryModel> _queue = [];
  BarberModel? _barber;
  bool _loading = true;
  bool _joining = false;
  bool _leaving = false;
  bool _inQueue = false;
  bool _inOtherQueue = false;
  int? _myPosition;
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    _loadQueue();
    _subscription = _service.subscribeToQueues(_loadQueue);
  }

  @override
  void dispose() {
    if (_subscription != null) _service.unsubscribe(_subscription!);
    super.dispose();
  }

  Future<void> _loadQueue() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    try {
      final queue = await _service.getQueueForChair(widget.chair.id);
      final inAnyQueue = await _service.isUserInQueue(user.id);
      final pos =
          await _service.getUserPositionInChair(user.id, widget.chair.id);
      if (_barber == null && user.barberId != null) {
        _barber = await _service.getBarberById(user.barberId!);
      }

      if (mounted) {
        setState(() {
          _queue = queue;
          _myPosition = pos;
          _inQueue = pos != null;
          _inOtherQueue = !_inQueue && inAnyQueue;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _joinQueue() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    setState(() => _joining = true);
    try {
      await _service.joinQueue(widget.chair.id, user.id);
      await _loadQueue();
      if (mounted) _showSnack('تم الانضمام للطابور بنجاح', AppTheme.success);
    } catch (e) {
      if (mounted) {
        _showSnack(
          e.toString().replaceAll('Exception: ', ''),
          AppTheme.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _leaveQueue() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('مغادرة الطابور',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text('هل أنت متأكد أنك تريد مغادرة الطابور؟',
              style: GoogleFonts.cairo()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              child: Text('مغادرة', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _leaving = true);
    try {
      await _service.leaveQueue(user.id);
      await _loadQueue();
      if (mounted) _showSnack('تم مغادرة الطابور', AppTheme.success);
    } catch (e) {
      if (mounted) {
        _showSnack(
          e.toString().replaceAll('Exception: ', ''),
          AppTheme.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  void _showSnack(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: GoogleFonts.cairo()),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  String _formatWaitTime(int minutes) {
    if (minutes <= 0) return 'دورك الآن!';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '$h ساعة و $m دقيقة';
    if (h > 0) return '$h ساعة';
    return '$m دقيقة';
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final inThisQueue = _myPosition != null;
    final peopleAhead = inThisQueue ? (_myPosition! - 1) : _queue.length;
    final estimatedMinutes = peopleAhead * _kMinutesPerPerson;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.chair.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // ─── Header: Barber + Chair ───────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Barber + Chair images
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_barber != null)
                              _ProfileCircle(
                                imageUrl: _barber!.imageUrl,
                                label: _barber!.name,
                                fallbackIcon: Icons.content_cut_rounded,
                                isCircle: true,
                              ),
                            if (_barber != null) const SizedBox(width: 24),
                            _ProfileCircle(
                              imageUrl: widget.chair.imageUrl,
                              label: widget.chair.name,
                              fallbackIcon: Icons.chair_rounded,
                              isCircle: false,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ─── Queue Status Card ────────────────
                  if (inThisQueue) ...[
                    // YOU ARE IN QUEUE
                    _buildInQueueView(peopleAhead, estimatedMinutes),
                  ] else ...[
                    // NOT IN QUEUE
                    _buildNotInQueueView(estimatedMinutes),
                  ],

                  const SizedBox(height: 24),

                  // ─── Action Buttons ────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        if (inThisQueue) ...[
                          // Leave Queue button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: _leaving ? null : _leaveQueue,
                              icon: _leaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.exit_to_app_rounded,
                                      size: 20),
                              label: Text(
                                'مغادرة الطابور',
                                style: GoogleFonts.cairo(
                                    fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.danger,
                                side: const BorderSide(color: AppTheme.danger),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Join Queue button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed:
                                  (_joining || _inOtherQueue) ? null : _joinQueue,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _inOtherQueue
                                    ? AppTheme.textMuted
                                    : AppTheme.accent,
                              ),
                              child: _joining
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      _inOtherQueue
                                          ? 'أنت في طابور كرسي آخر'
                                          : 'انضم للطابور',
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  // ─── In-Queue View ──────────────────────────────────────────
  Widget _buildInQueueView(int peopleAhead, int estimatedMinutes) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Status icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppTheme.success, size: 36),
            ),
            const SizedBox(height: 14),
            Text(
              'أنت في الطابور',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            // Position + Wait Time + People Ahead
            Row(
              children: [
                Expanded(
                  child: _InfoTile(
                    icon: Icons.tag_rounded,
                    title: 'ترتيبك',
                    value: '$_myPosition',
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoTile(
                    icon: Icons.access_time_rounded,
                    title: 'وقت الانتظار',
                    value: _formatWaitTime(estimatedMinutes),
                    color: estimatedMinutes == 0
                        ? AppTheme.success
                        : AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoTile(
              icon: Icons.people_outline_rounded,
              title: 'أمامك',
              value: peopleAhead == 0 ? 'لا أحد! — دورك الآن' : '$peopleAhead أشخاص',
              color: peopleAhead == 0
                  ? AppTheme.success
                  : AppTheme.textMuted,
            ),
            if (peopleAhead == 0) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'دورك الآن! توجه للكرسي',
                  style: GoogleFonts.cairo(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Not-In-Queue View ──────────────────────────────────────
  Widget _buildNotInQueueView(int estimatedMinutes) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.queue_rounded,
                  color: AppTheme.primary.withOpacity(0.4), size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              _queue.isEmpty
                  ? 'الطابور فارغ — انضم الآن!'
                  : 'يمكنك الانضمام للطابور',
              style: GoogleFonts.cairo(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
            if (_queue.isNotEmpty) ...[
              const SizedBox(height: 10),
              _InfoTile(
                icon: Icons.access_time_rounded,
                title: 'وقت الانتظار المتوقع',
                value: _formatWaitTime(estimatedMinutes),
                color: AppTheme.primary,
              ),
            ],
            if (_inOtherQueue) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'أنت مسجل في طابور كرسي آخر',
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Profile Circle Widget ────────────────────────────────────
class _ProfileCircle extends StatelessWidget {
  final String? imageUrl;
  final String label;
  final IconData fallbackIcon;
  final bool isCircle;

  const _ProfileCircle({
    required this.imageUrl,
    required this.label,
    required this.fallbackIcon,
    required this.isCircle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : BorderRadius.circular(16),
            border: Border.all(
              color: isCircle ? AppTheme.accent : Colors.white38,
              width: 2.5,
            ),
            image: imageUrl != null
                ? DecorationImage(
                    image: NetworkImage(imageUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
            color: isCircle
                ? AppTheme.accent.withOpacity(0.2)
                : Colors.white.withOpacity(0.1),
          ),
          child: imageUrl == null
              ? Icon(fallbackIcon,
                  color: isCircle ? AppTheme.accent : Colors.white54, size: 26)
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 11,
            color: Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Info Tile Widget ─────────────────────────────────────────
class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 11,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
