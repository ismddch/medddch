import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'queue_details_screen.dart';

class MyBarberScreen extends StatefulWidget {
  const MyBarberScreen({super.key});
  @override
  State<MyBarberScreen> createState() => _MyBarberScreenState();
}

class _MyBarberScreenState extends State<MyBarberScreen> {
  final SupabaseService _service = SupabaseService();
  List<BarberModel> _favorites = [];
  String? _likedBarberId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final results = await Future.wait([
        _service.getUserFavoriteBarbers(userId),
        _service.getUserLikedBarberId(userId),
      ]);
      if (mounted) {
        setState(() {
          _favorites      = results[0] as List<BarberModel>;
          _likedBarberId  = results[1] as String?;
          _loading        = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _remove(BarberModel barber) async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    final removed = barber;
    final idx = _favorites.indexOf(barber);
    setState(() => _favorites.remove(barber));
    try {
      await _service.toggleFavoriteBarber(userId, barber.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _favorites.insert(idx.clamp(0, _favorites.length), removed));
    }
  }

  void _book(BarberModel barber) {
    if (barber.isClosed) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => QueueDetailsScreen(barber: barber)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F0),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // ─── AppBar ──────────────────────────────────────────
            SliverAppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              floating: true,
              centerTitle: true,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bookmark_rounded, color: AppTheme.accent, size: 17),
                      const SizedBox(width: 5),
                      Text('حلاقي',
                          style: GoogleFonts.cairo(
                              fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.primary)),
                    ],
                  ),
                  Text('حلاقوني المحفوظون',
                      style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textMuted)),
                ],
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: AppTheme.divider),
              ),
            ),

            // ─── Content ─────────────────────────────────────────
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_favorites.isEmpty)
              SliverFillRemaining(child: _EmptyState())
            else ...[
              // Count chip
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      const Icon(Icons.bookmark_rounded, color: AppTheme.accent, size: 16),
                      const SizedBox(width: 6),
                      Text('${_favorites.length} حلاق محفوظ',
                          style: GoogleFonts.cairo(
                              fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                      const Spacer(),
                      Text('اضغط على البطاقة للحجز',
                          style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ),

              // List
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _BarberBusinessCard(
                        barber: _favorites[i],
                        isVoted: _likedBarberId == _favorites[i].id,
                        onBook: () => _book(_favorites[i]),
                        onRemove: () => _remove(_favorites[i]),
                      ),
                    ),
                    childCount: _favorites.length,
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

// ─── Empty State ──────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.bookmark_border_rounded,
                  size: 48, color: AppTheme.accent),
            ),
            const SizedBox(height: 20),
            Text('لا توجد حلاقون محفوظون',
                style: GoogleFonts.cairo(
                    fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primary),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'احفظ حلاقك المفضل من الصفحة الرئيسية باستخدام زر 🔖',
              style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textMuted, height: 1.6),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Barber Business Card ─────────────────────────────────────
class _BarberBusinessCard extends StatelessWidget {
  final BarberModel barber;
  final bool isVoted;
  final VoidCallback onBook;
  final VoidCallback onRemove;

  const _BarberBusinessCard({
    required this.barber,
    required this.isVoted,
    required this.onBook,
    required this.onRemove,
  });

  static const _palette = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
    Color(0xFFC62828), Color(0xFF00695C), Color(0xFF283593),
    Color(0xFF4E342E), Color(0xFF0277BD), Color(0xFF558B2F),
  ];

  Color get _bgColor {
    if (barber.name.isEmpty) return _palette[0];
    return _palette[barber.name.codeUnitAt(0) % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final isClosed   = barber.isClosed;
    final queueCount = barber.queueLength;
    final waitMin    = queueCount * 45;

    final statusColor = isClosed ? AppTheme.textMuted
        : queueCount == 0 ? AppTheme.success
        : queueCount > 3  ? AppTheme.danger
        : AppTheme.accent;

    final statusLabel = isClosed ? 'مغلق حالياً'
        : queueCount == 0 ? 'متاح الآن'
        : '$queueCount في الطابور';

    final waitLabel = isClosed ? ''
        : queueCount == 0 ? 'ادخل مباشرة'
        : waitMin < 60    ? '~$waitMin دقيقة انتظار'
        : '~${(waitMin / 60).toStringAsFixed(1)} ساعة انتظار';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20, offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Photo section ───────────────────────────────────
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24), topRight: Radius.circular(24),
                ),
                child: SizedBox(
                  height: 185,
                  width: double.infinity,
                  child: barber.imageUrl != null
                      ? Image.network(
                          barber.imageUrl!, fit: BoxFit.cover,
                          color: isClosed ? Colors.grey : null,
                          colorBlendMode: isClosed ? BlendMode.saturation : null,
                          errorBuilder: (_, __, ___) => _Placeholder(
                              bgColor: _bgColor, name: barber.name, isClosed: isClosed))
                      : _Placeholder(
                          bgColor: _bgColor, name: barber.name, isClosed: isClosed),
                ),
              ),
              // Gradient overlay — bottom 60%
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24), topRight: Radius.circular(24),
                ),
                child: Container(
                  height: 185,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      stops: const [0.4, 1.0],
                    ),
                  ),
                ),
              ),
              // Voted badge — top left
              if (isVoted)
                Positioned(
                  top: 12, left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.favorite_rounded, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text('صوّتَ له',
                          style: GoogleFonts.cairo(
                              fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                    ]),
                  ),
                ),
              // Remove (unsave) button — top right
              Positioned(
                top: 10, right: 10,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.38),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bookmark_remove_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ),
              // Status badge — bottom right on photo
              Positioned(
                bottom: 12, right: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 5, height: 5,
                      decoration: const BoxDecoration(
                          color: Colors.white, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                    Text(statusLabel,
                        style: GoogleFonts.cairo(
                            fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ]),
                ),
              ),
            ],
          ),

          // ─── Name + shop ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(barber.name,
                    style: GoogleFonts.cairo(
                        fontSize: 21, fontWeight: FontWeight.w900, color: AppTheme.primary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (barber.shopName != null) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    const Icon(Icons.storefront_rounded, size: 14, color: AppTheme.textMuted),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(barber.shopName!,
                          style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textMuted),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ],
                const SizedBox(height: 12),
                // Stats row
                Row(children: [
                  const Icon(Icons.favorite_rounded, size: 15, color: Colors.red),
                  const SizedBox(width: 5),
                  Text('${barber.likeCount} تصويت',
                      style: GoogleFonts.cairo(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted)),
                  if (waitLabel.isNotEmpty) ...[
                    const Spacer(),
                    const Icon(Icons.schedule_rounded, size: 13, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Text(waitLabel,
                        style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textMuted)),
                  ],
                ]),
              ],
            ),
          ),

          // ─── Divider ──────────────────────────────────────────
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Divider(height: 1),
          ),

          // ─── Action buttons ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Row(
              children: [
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: onRemove,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textMuted,
                      side: const BorderSide(color: AppTheme.divider),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.bookmark_remove_rounded, size: 17),
                    label: Text('إزالة',
                        style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: isClosed
                        ? OutlinedButton.icon(
                            onPressed: null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textMuted,
                              side: const BorderSide(color: AppTheme.divider),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.lock_rounded, size: 17),
                            label: Text('غير متاح',
                                style: GoogleFonts.cairo(fontSize: 14)),
                          )
                        : ElevatedButton.icon(
                            onPressed: onBook,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.queue_rounded, size: 17),
                            label: Text(
                              queueCount == 0 ? 'احجز الآن' : 'انضم للطابور',
                              style: GoogleFonts.cairo(
                                  fontSize: 14, fontWeight: FontWeight.w700),
                            ),
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

// ─── Photo Placeholder (colored initials) ─────────────────────
class _Placeholder extends StatelessWidget {
  final Color bgColor;
  final String name;
  final bool isClosed;
  const _Placeholder({required this.bgColor, required this.name, required this.isClosed});

  @override
  Widget build(BuildContext context) {
    if (isClosed) {
      return Container(
        color: Colors.grey.shade300,
        child: const Center(child: Icon(Icons.lock_rounded, size: 40, color: Colors.white54)),
      );
    }
    return Container(
      color: bgColor,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0] : '؟',
          style: const TextStyle(fontSize: 60, fontWeight: FontWeight.w900, color: Colors.white),
        ),
      ),
    );
  }
}
