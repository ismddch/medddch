import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'queue_details_screen.dart';

class AllBarbersScreen extends StatefulWidget {
  const AllBarbersScreen({super.key});
  @override
  State<AllBarbersScreen> createState() => _AllBarbersScreenState();
}

class _AllBarbersScreenState extends State<AllBarbersScreen> {
  final SupabaseService _service = SupabaseService();
  List<BarberModel> _barbers = [];
  String? _likedBarberId;
  Set<String> _savedIds = {};
  bool _loading = true;
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
    _subscription = _service.subscribeToQueues(() { if (mounted) _load(); });
  }

  @override
  void dispose() {
    if (_subscription != null) _service.unsubscribe(_subscription!);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().user?.id;
    try {
      final results = await Future.wait([
        _service.getAllBarbersRanked(),
        if (userId != null) _service.getUserLikedBarberId(userId),
        if (userId != null) _service.getFavoriteBarberIds(userId),
      ]);
      final barbers  = results[0] as List<BarberModel>;
      final liked    = userId != null ? results[1] as String?    : null;
      final savedIds = userId != null ? results[2] as Set<String> : <String>{};
      if (mounted) {
        setState(() {
          _barbers       = barbers;
          _likedBarberId = liked;
          _savedIds      = savedIds;
          _loading       = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike(BarberModel barber) async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    final wasLiked  = _likedBarberId == barber.id;
    final prevLiked = _likedBarberId;
    setState(() {
      if (wasLiked) {
        _likedBarberId = null;
        final idx = _barbers.indexWhere((b) => b.id == barber.id);
        if (idx >= 0) _barbers[idx].likeCount = (_barbers[idx].likeCount - 1).clamp(0, 999999);
      } else {
        if (_likedBarberId != null) {
          final old = _barbers.indexWhere((b) => b.id == _likedBarberId);
          if (old >= 0) _barbers[old].likeCount = (_barbers[old].likeCount - 1).clamp(0, 999999);
        }
        _likedBarberId = barber.id;
        final idx = _barbers.indexWhere((b) => b.id == barber.id);
        if (idx >= 0) _barbers[idx].likeCount++;
      }
      _barbers.sort((a, b) => b.likeCount.compareTo(a.likeCount));
    });
    try {
      await _service.toggleBarberLike(userId, barber.id);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _likedBarberId = prevLiked;
        if (wasLiked) {
          final idx = _barbers.indexWhere((b) => b.id == barber.id);
          if (idx >= 0) _barbers[idx].likeCount++;
        } else {
          final idx = _barbers.indexWhere((b) => b.id == barber.id);
          if (idx >= 0) _barbers[idx].likeCount = (_barbers[idx].likeCount - 1).clamp(0, 999999);
          if (prevLiked != null) {
            final old = _barbers.indexWhere((b) => b.id == prevLiked);
            if (old >= 0) _barbers[old].likeCount++;
          }
        }
        _barbers.sort((a, b) => b.likeCount.compareTo(a.likeCount));
      });
    }
  }

  Future<void> _toggleSave(BarberModel barber) async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('يجب تسجيل الدخول أولاً', style: GoogleFonts.cairo()),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final wasSaved = _savedIds.contains(barber.id);
    setState(() {
      if (wasSaved) { _savedIds.remove(barber.id); } else { _savedIds.add(barber.id); }
    });
    try {
      await _service.toggleFavoriteBarber(userId, barber.id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (wasSaved) { _savedIds.add(barber.id); } else { _savedIds.remove(barber.id); }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('تعذّر الحفظ: $e', style: GoogleFonts.cairo()),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _showDetails(BarberModel barber, int rank) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetailsSheet(
        barber: barber,
        rank: rank,
        isLiked: _likedBarberId == barber.id,
        onLike: () { Navigator.pop(context); _toggleLike(barber); },
        onBook: barber.isClosed ? null : () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (_) => QueueDetailsScreen(barber: barber)));
        },
      ),
    );
  }

  void _book(BarberModel barber) {
    if (barber.isClosed) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => QueueDetailsScreen(barber: barber)));
  }

  BarberModel? get _fav {
    if (_likedBarberId == null) return null;
    try { return _barbers.firstWhere((b) => b.id == _likedBarberId); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final fav  = _fav;
    final top3 = _barbers.take(3).toList();
    final rest = _barbers.length > 3 ? _barbers.sublist(3) : <BarberModel>[];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F0),
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // ─── AppBar ───────────────────────────────────────────
            SliverAppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              floating: true,
              centerTitle: true,
              leading: const Icon(Icons.menu_rounded, color: AppTheme.primary),
              actions: const [
                Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: Icon(Icons.person_outline_rounded, color: AppTheme.primary),
                ),
              ],
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.content_cut_rounded, color: AppTheme.accent, size: 17),
                      const SizedBox(width: 5),
                      Text('حلاقك',
                          style: GoogleFonts.cairo(
                              fontSize: 20, fontWeight: FontWeight.w900, color: AppTheme.primary)),
                    ],
                  ),
                  Text('الرئيسية',
                      style: GoogleFonts.cairo(fontSize: 10, color: AppTheme.textMuted)),
                ],
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: AppTheme.divider),
              ),
            ),

            // ─── Loading / Empty / Content ────────────────────────
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_barbers.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.content_cut_outlined, size: 64,
                          color: AppTheme.textMuted.withValues(alpha: 0.25)),
                      const SizedBox(height: 14),
                      Text('لا يوجد حلاقون بعد',
                          style: GoogleFonts.cairo(fontSize: 15, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              )
            else ...[
              // ─── Vote Banner ────────────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverToBoxAdapter(child: _VoteBanner(favName: fav?.name)),
              ),

              // ─── Top rated section ───────────────────────────────
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _TopSection(
                    barbers: top3,
                    likedId: _likedBarberId,
                    savedIds: _savedIds,
                    onLike: _toggleLike,
                    onSave: _toggleSave,
                    onBook: _book,
                    onDetails: (b, r) => _showDetails(b, r),
                  ),
                ),
              ),

              // ─── Rest grid ───────────────────────────────────────
              if (rest.isNotEmpty) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: Text('حلاقون آخرون',
                        style: GoogleFonts.cairo(
                            fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 258,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _GridCard(
                        barber: rest[i],
                        rank: i + 4,
                        isLiked: _likedBarberId == rest[i].id,
                        isSaved: _savedIds.contains(rest[i].id),
                        onTap: () => _showDetails(rest[i], i + 4),
                        onSave: () => _toggleSave(rest[i]),
                        onBook: () => _book(rest[i]),
                      ),
                      childCount: rest.length,
                    ),
                  ),
                ),
              ],

              // ─── Favourite section ───────────────────────────────
              if (fav != null) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        const Icon(Icons.favorite_rounded, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Text('حلاقك المفضل',
                            style: GoogleFonts.cairo(
                                fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  sliver: SliverToBoxAdapter(
                    child: _FavCard(
                      barber: fav,
                      rank: _barbers.indexWhere((b) => b.id == fav.id) + 1,
                      onBook: fav.isClosed ? null : () => _book(fav),
                      onDetails: () => _showDetails(fav, _barbers.indexWhere((b) => b.id == fav.id) + 1),
                      onRemove: () => _toggleLike(fav),
                    ),
                  ),
                ),
              ] else
                const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Vote Banner ──────────────────────────────────────────────
class _VoteBanner extends StatelessWidget {
  final String? favName;
  const _VoteBanner({required this.favName});

  @override
  Widget build(BuildContext context) {
    final voted = favName != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: voted ? Colors.red.withValues(alpha: 0.05) : AppTheme.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: voted ? Colors.red.withValues(alpha: 0.2) : AppTheme.accent.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(voted ? Icons.how_to_vote_rounded : Icons.info_outline_rounded,
              color: voted ? Colors.red : AppTheme.accent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: voted
                ? RichText(
                    text: TextSpan(
                      style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.primary),
                      children: [
                        const TextSpan(text: 'صوتك الحالي: '),
                        TextSpan(
                          text: favName,
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.red),
                        ),
                        const TextSpan(text: ' — يمكنك تغييره في أي وقت'),
                      ],
                    ),
                  )
                : Text('اضغط ❤️ لتختار حلاقك المفضل — صوت واحد لكل عميل',
                    style: GoogleFonts.cairo(
                        fontSize: 12, color: AppTheme.primary.withValues(alpha: 0.7))),
          ),
        ],
      ),
    );
  }
}

// ─── Top Section (podium) ─────────────────────────────────────
class _TopSection extends StatelessWidget {
  final List<BarberModel> barbers;
  final String? likedId;
  final Set<String> savedIds;
  final Function(BarberModel) onLike;
  final Function(BarberModel) onSave;
  final Function(BarberModel) onBook;
  final Function(BarberModel, int) onDetails;

  const _TopSection({
    required this.barbers,
    required this.likedId,
    required this.savedIds,
    required this.onLike,
    required this.onSave,
    required this.onBook,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('أعلى الحلاقين تقييماً',
                style: GoogleFonts.cairo(
                    fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.primary)),
            const Spacer(),
            const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD700), size: 26),
          ],
        ),
        const SizedBox(height: 14),
        if (barbers.isEmpty) const SizedBox.shrink()
        else if (barbers.length == 1)
          _BigCard(barber: barbers[0], rank: 1, isLiked: likedId == barbers[0].id,
              isSaved: savedIds.contains(barbers[0].id),
              onLike: () => onLike(barbers[0]), onSave: () => onSave(barbers[0]),
              onBook: () => onBook(barbers[0]), onDetails: () => onDetails(barbers[0], 1))
        else if (barbers.length == 2)
          Row(children: [
            Expanded(child: _BigCard(barber: barbers[0], rank: 1, isLiked: likedId == barbers[0].id,
                isSaved: savedIds.contains(barbers[0].id),
                onLike: () => onLike(barbers[0]), onSave: () => onSave(barbers[0]),
                onBook: () => onBook(barbers[0]), onDetails: () => onDetails(barbers[0], 1))),
            const SizedBox(width: 10),
            Expanded(child: _BigCard(barber: barbers[1], rank: 2, isLiked: likedId == barbers[1].id,
                isSaved: savedIds.contains(barbers[1].id),
                onLike: () => onLike(barbers[1]), onSave: () => onSave(barbers[1]),
                onBook: () => onBook(barbers[1]), onDetails: () => onDetails(barbers[1], 2))),
          ])
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 55,
                child: _BigCard(barber: barbers[0], rank: 1, isLiked: likedId == barbers[0].id,
                    isSaved: savedIds.contains(barbers[0].id),
                    onLike: () => onLike(barbers[0]), onSave: () => onSave(barbers[0]),
                    onBook: () => onBook(barbers[0]), onDetails: () => onDetails(barbers[0], 1)),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 45,
                child: Column(
                  children: [
                    _SmallCard(barber: barbers[1], rank: 2, isLiked: likedId == barbers[1].id,
                        isSaved: savedIds.contains(barbers[1].id),
                        onLike: () => onLike(barbers[1]), onSave: () => onSave(barbers[1]),
                        onBook: () => onBook(barbers[1]), onDetails: () => onDetails(barbers[1], 2)),
                    const SizedBox(height: 10),
                    _SmallCard(barber: barbers[2], rank: 3, isLiked: likedId == barbers[2].id,
                        isSaved: savedIds.contains(barbers[2].id),
                        onLike: () => onLike(barbers[2]), onSave: () => onSave(barbers[2]),
                        onBook: () => onBook(barbers[2]), onDetails: () => onDetails(barbers[2], 3)),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// ─── Stars row helper ─────────────────────────────────────────
Widget _stars(int rank, double size) {
  final filled = rank == 1 ? 5 : rank == 2 ? 4 : 3;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      5,
      (i) => Icon(
        i < filled ? Icons.star_rounded : Icons.star_outline_rounded,
        size: size,
        color: i < filled ? const Color(0xFFFFB300) : const Color(0xFFD9D9D9),
      ),
    ),
  );
}

// ─── Big Card (#1, or #2 when only 2 barbers) ─────────────────
class _BigCard extends StatelessWidget {
  final BarberModel barber;
  final int rank;
  final bool isLiked;
  final bool isSaved;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onBook;
  final VoidCallback onDetails;

  const _BigCard({
    required this.barber, required this.rank,
    required this.isLiked, required this.isSaved,
    required this.onLike, required this.onSave,
    required this.onBook, required this.onDetails,
  });

  Color get _rankColor {
    if (rank == 1) return const Color(0xFFFFD700);
    if (rank == 2) return const Color(0xFFC0C0C0);
    return const Color(0xFFCD7F32);
  }

  @override
  Widget build(BuildContext context) {
    final isClosed   = barber.isClosed;
    final queueCount = barber.queueLength;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.09), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(22), topRight: Radius.circular(22)),
                child: SizedBox(
                  height: 195,
                  width: double.infinity,
                  child: barber.imageUrl != null
                      ? Image.network(barber.imageUrl!, fit: BoxFit.cover,
                          color: isClosed ? Colors.grey : null,
                          colorBlendMode: isClosed ? BlendMode.saturation : null,
                          errorBuilder: (_, __, ___) => _PhotoPlaceholder(isClosed: isClosed, name: barber.name))
                      : _PhotoPlaceholder(isClosed: isClosed, name: barber.name),
                ),
              ),
              // Gradient overlay
              ClipRRect(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(22), topRight: Radius.circular(22)),
                child: Container(
                  height: 195,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.50)],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      stops: const [0.45, 1.0],
                    ),
                  ),
                ),
              ),
              // Crown for #1
              if (rank == 1)
                const Positioned(
                  top: 8, left: 0, right: 0,
                  child: Center(child: Text('👑', style: TextStyle(fontSize: 26))),
                ),
              // Rank badge
              Positioned(
                top: 10, right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _rankColor, borderRadius: BorderRadius.circular(8)),
                  child: Text('#$rank',
                      style: GoogleFonts.cairo(
                          fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              // Like + bookmark buttons
              Positioned(
                top: 10, left: 10,
                child: Row(
                  children: [
                    _PhotoLikeBtn(isLiked: isLiked, onTap: onLike),
                    const SizedBox(width: 6),
                    _PhotoBookmarkBtn(isSaved: isSaved, onTap: onSave),
                  ],
                ),
              ),
            ],
          ),

          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stars(rank, 14),
                const SizedBox(height: 6),
                Text(barber.name,
                    style: GoogleFonts.cairo(
                        fontSize: 17, fontWeight: FontWeight.w900, color: AppTheme.primary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (barber.shopName != null) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    const Icon(Icons.storefront_rounded, size: 12, color: AppTheme.textMuted),
                    const SizedBox(width: 4),
                    Flexible(child: Text(barber.shopName!,
                        style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textMuted),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.favorite_rounded, size: 13, color: Colors.red),
                  const SizedBox(width: 4),
                  Text('${barber.likeCount} تصويت',
                      style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (!isClosed)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (queueCount == 0 ? AppTheme.success
                            : queueCount > 3 ? AppTheme.danger : AppTheme.accent)
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 5, height: 5,
                          decoration: BoxDecoration(
                            color: queueCount == 0 ? AppTheme.success
                                : queueCount > 3 ? AppTheme.danger : AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          queueCount == 0 ? 'متاح الآن' : '$queueCount في الطابور',
                          style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w700,
                              color: queueCount == 0 ? AppTheme.success
                                  : queueCount > 3 ? AppTheme.danger : AppTheme.accent),
                        ),
                      ]),
                    ),
                ]),
                const SizedBox(height: 12),
                // Buttons
                Row(children: [
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: isClosed ? null : onBook,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent, foregroundColor: Colors.white,
                          elevation: 0, padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          disabledBackgroundColor: AppTheme.divider,
                        ),
                        icon: Icon(isClosed ? Icons.lock_rounded : Icons.queue_rounded, size: 15),
                        label: Text(isClosed ? 'مغلق' : 'احجز الآن',
                            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: onDetails,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.divider),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.info_outline_rounded, size: 15),
                      label: Text('تفاصيل',
                          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Small Card (#2 and #3, stacked) ─────────────────────────
class _SmallCard extends StatelessWidget {
  final BarberModel barber;
  final int rank;
  final bool isLiked;
  final bool isSaved;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback onBook;
  final VoidCallback onDetails;

  const _SmallCard({
    required this.barber, required this.rank,
    required this.isLiked, required this.isSaved,
    required this.onLike, required this.onSave,
    required this.onBook, required this.onDetails,
  });

  Color get _rankColor =>
      rank == 2 ? const Color(0xFFC0C0C0) : const Color(0xFFCD7F32);

  @override
  Widget build(BuildContext context) {
    final isClosed   = barber.isClosed;
    final queueCount = barber.queueLength;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18), topRight: Radius.circular(18)),
                child: SizedBox(
                  height: 115,
                  width: double.infinity,
                  child: barber.imageUrl != null
                      ? Image.network(barber.imageUrl!, fit: BoxFit.cover,
                          color: isClosed ? Colors.grey : null,
                          colorBlendMode: isClosed ? BlendMode.saturation : null,
                          errorBuilder: (_, __, ___) => _PhotoPlaceholder(isClosed: isClosed, name: barber.name))
                      : _PhotoPlaceholder(isClosed: isClosed, name: barber.name),
                ),
              ),
              ClipRRect(
                borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18), topRight: Radius.circular(18)),
                child: Container(
                  height: 115,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.40)],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      stops: const [0.45, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 6, right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: _rankColor, borderRadius: BorderRadius.circular(6)),
                  child: Text('#$rank',
                      style: GoogleFonts.cairo(
                          fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ),
              Positioned(
                top: 6, left: 6,
                child: Row(
                  children: [
                    _PhotoLikeBtn(isLiked: isLiked, onTap: onLike, size: 26),
                    const SizedBox(width: 4),
                    _PhotoBookmarkBtn(isSaved: isSaved, onTap: onSave),
                  ],
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stars(rank, 12),
                const SizedBox(height: 4),
                Text(barber.name,
                    style: GoogleFonts.cairo(
                        fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.primary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (barber.shopName != null)
                  Text(barber.shopName!,
                      style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.favorite_rounded, size: 11, color: Colors.red),
                  const SizedBox(width: 3),
                  Text('${barber.likeCount}',
                      style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted,
                          fontWeight: FontWeight.w600)),
                  if (!isClosed) ...[
                    const Spacer(),
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: queueCount == 0 ? AppTheme.success
                            : queueCount > 3 ? AppTheme.danger : AppTheme.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: ElevatedButton(
                        onPressed: isClosed ? null : onBook,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent, foregroundColor: Colors.white,
                          elevation: 0, padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                          disabledBackgroundColor: AppTheme.divider,
                        ),
                        child: Text(isClosed ? 'مغلق' : 'احجز',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 32,
                    child: OutlinedButton(
                      onPressed: onDetails,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.divider),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      ),
                      child: Text('تفاصيل', style: GoogleFonts.cairo(fontSize: 11)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grid Card (rank 4+, 2-column) ───────────────────────────
class _GridCard extends StatelessWidget {
  final BarberModel barber;
  final int rank;
  final bool isLiked;
  final bool isSaved;
  final VoidCallback onTap;
  final VoidCallback onSave;
  final VoidCallback onBook;

  const _GridCard({
    required this.barber, required this.rank,
    required this.isLiked, required this.isSaved,
    required this.onTap, required this.onSave, required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    final isClosed   = barber.isClosed;
    final queueCount = barber.queueLength;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.07), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Photo (fills all space not taken by the info section) ──
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18), topRight: Radius.circular(18)),
                  child: SizedBox.expand(
                    child: barber.imageUrl != null
                        ? Image.network(barber.imageUrl!, fit: BoxFit.cover,
                            color: isClosed ? Colors.grey : null,
                            colorBlendMode: isClosed ? BlendMode.saturation : null,
                            errorBuilder: (_, __, ___) =>
                                _PhotoPlaceholder(isClosed: isClosed, name: barber.name))
                        : _PhotoPlaceholder(isClosed: isClosed, name: barber.name),
                  ),
                ),
                Positioned(
                  top: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text('#$rank',
                        style: GoogleFonts.cairo(
                            fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
                Positioned(
                  top: 8, left: 8,
                  child: _PhotoBookmarkBtn(isSaved: isSaved, onTap: onSave),
                ),
                if (!isClosed)
                  Positioned(
                    bottom: 8, right: 8,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: queueCount == 0 ? AppTheme.success
                            : queueCount > 3 ? AppTheme.danger : AppTheme.accent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Info (fixed height content) ──────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(barber.name,
                    style: GoogleFonts.cairo(
                        fontSize: 13, fontWeight: FontWeight.w900, color: AppTheme.primary),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                if (barber.shopName != null)
                  Text(barber.shopName!,
                      style: GoogleFonts.cairo(fontSize: 11, color: AppTheme.textMuted),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.favorite_rounded, size: 12,
                      color: isLiked ? Colors.red : AppTheme.textMuted),
                  const SizedBox(width: 3),
                  Text('${barber.likeCount}',
                      style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: isLiked ? Colors.red : AppTheme.textMuted,
                          fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 7),
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 30,
                      child: ElevatedButton(
                        onPressed: isClosed ? null : onBook,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent, foregroundColor: Colors.white,
                          elevation: 0, padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                          disabledBackgroundColor: AppTheme.divider,
                        ),
                        child: Text(isClosed ? 'مغلق' : 'احجز',
                            style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 30,
                    child: OutlinedButton(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.divider),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                      ),
                      child: Text('تفاصيل', style: GoogleFonts.cairo(fontSize: 11)),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Favourite Card ────────────────────────────────────────────
class _FavCard extends StatelessWidget {
  final BarberModel barber;
  final int rank;
  final VoidCallback? onBook;
  final VoidCallback onDetails;
  final VoidCallback onRemove;

  const _FavCard({
    required this.barber, required this.rank,
    required this.onBook, required this.onDetails, required this.onRemove,
  });

  String get _rankLabel {
    if (rank == 1) return '🥇 الأول';
    if (rank == 2) return '🥈 الثاني';
    if (rank == 3) return '🥉 الثالث';
    return 'المركز $rank';
  }

  @override
  Widget build(BuildContext context) {
    final isClosed   = barber.isClosed;
    final queueCount = barber.queueLength;
    final statusColor = isClosed ? AppTheme.textMuted
        : queueCount == 0 ? AppTheme.success
        : queueCount > 3  ? AppTheme.danger
        : AppTheme.accent;
    final statusLabel = isClosed ? 'مغلق'
        : queueCount == 0 ? 'متاح الآن'
        : '$queueCount في الطابور';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.red.withValues(alpha: 0.35), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.red.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(21), topRight: Radius.circular(21)),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite_rounded, color: Colors.red, size: 14),
                const SizedBox(width: 6),
                Text('صوّتَ لـ',
                    style: GoogleFonts.cairo(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(_rankLabel,
                    style: GoogleFonts.cairo(
                        fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.red.withValues(alpha: 0.4), width: 2),
                    color: AppTheme.surface,
                    image: barber.imageUrl != null
                        ? DecorationImage(image: NetworkImage(barber.imageUrl!), fit: BoxFit.cover)
                        : null,
                  ),
                  child: barber.imageUrl == null
                      ? const Icon(Icons.content_cut_rounded, color: AppTheme.accent, size: 26)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(barber.name,
                          style: GoogleFonts.cairo(
                              fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.primary),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (barber.shopName != null)
                        Text(barber.shopName!,
                            style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textMuted)),
                      const SizedBox(height: 5),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(statusLabel,
                              style: GoogleFonts.cairo(
                                  fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.favorite_rounded, size: 11, color: Colors.red),
                        const SizedBox(width: 3),
                        Text('${barber.likeCount} صوت',
                            style: GoogleFonts.cairo(
                                fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onRemove,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.favorite_rounded, color: Colors.red, size: 28),
                      const SizedBox(height: 2),
                      Text('إلغاء',
                          style: GoogleFonts.cairo(
                              fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: onDetails,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.divider),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.info_outline_rounded, size: 16),
                      label: Text('تفاصيل',
                          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 42,
                    child: isClosed
                        ? OutlinedButton.icon(
                            onPressed: null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textMuted,
                              side: const BorderSide(color: AppTheme.divider),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.lock_rounded, size: 16),
                            label: Text('غير متاح', style: GoogleFonts.cairo(fontSize: 13)),
                          )
                        : ElevatedButton.icon(
                            onPressed: onBook,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent, foregroundColor: Colors.white,
                              elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            icon: const Icon(Icons.queue_rounded, size: 16),
                            label: Text(
                              queueCount == 0 ? 'احجز الآن' : 'انضم للطابور',
                              style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700),
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

// ─── Details Bottom Sheet ─────────────────────────────────────
class _DetailsSheet extends StatefulWidget {
  final BarberModel barber;
  final int rank;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback? onBook;

  const _DetailsSheet({
    required this.barber, required this.rank,
    required this.isLiked, required this.onLike, required this.onBook,
  });

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  final _service = SupabaseService();
  List<String> _photos = [];
  bool _photosLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    final photos = await _service.getBarberPortfolio(widget.barber.id);
    if (mounted) setState(() { _photos = photos; _photosLoading = false; });
  }

  void _openPhoto(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoViewer(photos: _photos, initialIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final barber = widget.barber;
    final isClosed   = barber.isClosed;
    final queueCount = barber.queueLength;
    final statusColor = isClosed ? AppTheme.textMuted
        : queueCount == 0 ? AppTheme.success
        : queueCount > 3  ? AppTheme.danger : AppTheme.accent;
    final waitMin = queueCount * 45;
    final waitLabel = queueCount == 0 ? 'ادخل مباشرة — لا انتظار'
        : waitMin < 60 ? 'وقت الانتظار ~$waitMin دقيقة'
        : 'وقت الانتظار ~${(waitMin / 60).toStringAsFixed(1)} ساعة';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28), topRight: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).padding.bottom + 24),
              child: Column(
                children: [
                  // ── Profile photo ──────────────────────────────
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.rank <= 3
                            ? [const Color(0xFFFFD700), const Color(0xFFC0C0C0), const Color(0xFFCD7F32)][widget.rank - 1]
                            : AppTheme.divider,
                        width: widget.rank <= 3 ? 3 : 2,
                      ),
                      color: AppTheme.surface,
                      image: barber.imageUrl != null
                          ? DecorationImage(image: NetworkImage(barber.imageUrl!), fit: BoxFit.cover)
                          : null,
                    ),
                    child: barber.imageUrl == null
                        ? const Icon(Icons.content_cut_rounded, size: 40, color: AppTheme.accent)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  if (widget.rank <= 3) _stars(widget.rank, 18),
                  const SizedBox(height: 8),
                  Text(barber.name,
                      style: GoogleFonts.cairo(
                          fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.primary),
                      textAlign: TextAlign.center),
                  if (barber.shopName != null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.storefront_rounded, size: 13, color: AppTheme.textMuted),
                        const SizedBox(width: 4),
                        Text(barber.shopName!,
                            style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textMuted)),
                      ],
                    ),
                  const SizedBox(height: 18),
                  // ── Stats chips ───────────────────────────────
                  Row(children: [
                    _Chip(
                      icon: Icons.emoji_events_rounded,
                      label: 'المركز ${widget.rank}',
                      color: widget.rank <= 3
                          ? [const Color(0xFFFFD700), const Color(0xFFC0C0C0), const Color(0xFFCD7F32)][widget.rank - 1]
                          : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 10),
                    _Chip(
                      icon: Icons.favorite_rounded,
                      label: '${barber.likeCount} تصويت',
                      color: Colors.red,
                    ),
                  ]),
                  const SizedBox(height: 10),
                  // ── Queue status ──────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: statusColor.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isClosed ? Icons.lock_rounded
                                  : queueCount == 0 ? Icons.check_circle_rounded : Icons.people_rounded,
                              color: statusColor, size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isClosed ? 'مغلق حالياً'
                                  : queueCount == 0 ? 'متاح الآن'
                                  : 'طابور: $queueCount شخص',
                              style: GoogleFonts.cairo(
                                  fontSize: 14, fontWeight: FontWeight.w700, color: statusColor),
                            ),
                          ],
                        ),
                        if (!isClosed) ...[
                          const SizedBox(height: 4),
                          Text(waitLabel,
                              style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textMuted)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ── Vote toggle ───────────────────────────────
                  GestureDetector(
                    onTap: widget.onLike,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: widget.isLiked ? Colors.red.withValues(alpha: 0.05) : AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: widget.isLiked ? Colors.red.withValues(alpha: 0.3) : AppTheme.divider),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(widget.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: widget.isLiked ? Colors.red : AppTheme.textMuted, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            widget.isLiked ? 'إلغاء صوتك لهذا الحلاق' : 'صوّت لهذا الحلاق',
                            style: GoogleFonts.cairo(
                                fontSize: 13, fontWeight: FontWeight.w700,
                                color: widget.isLiked ? Colors.red : AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // ── Book button ───────────────────────────────
                  SizedBox(
                    width: double.infinity, height: 52,
                    child: isClosed
                        ? OutlinedButton.icon(
                            onPressed: null,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textMuted,
                              side: const BorderSide(color: AppTheme.divider),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.lock_rounded),
                            label: Text('الحلاق غير متاح حالياً',
                                style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600)),
                          )
                        : ElevatedButton.icon(
                            onPressed: widget.onBook,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent, foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.queue_rounded, size: 20),
                            label: Text(
                              queueCount == 0 ? 'احجز مكانك الآن' : 'انضم للطابور',
                              style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                          ),
                  ),

                  // ── Work photos gallery ───────────────────────
                  if (_photosLoading) ...[
                    const SizedBox(height: 24),
                    const SizedBox(height: 36, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                  ] else if (_photos.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(children: [
                      const Icon(Icons.photo_library_rounded, color: AppTheme.accent, size: 16),
                      const SizedBox(width: 6),
                      Text('أعمال الحلاق',
                          style: GoogleFonts.cairo(
                              fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.primary)),
                      const Spacer(),
                      Text('${_photos.length} صور',
                          style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textMuted)),
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 120,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _photos.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => _openPhoto(i),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              _photos[i],
                              width: 120, height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 120, height: 120,
                                decoration: BoxDecoration(
                                  color: AppTheme.divider,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.broken_image_rounded,
                                    color: AppTheme.textMuted),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Full-screen Photo Viewer ─────────────────────────────────
class _PhotoViewer extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;
  const _PhotoViewer({required this.photos, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.photos.length}',
            style: GoogleFonts.cairo(color: Colors.white)),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: Image.network(
              widget.photos[i],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.cairo(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

// ─── Photo Like Button (on card image overlay) ─────────────────
class _PhotoLikeBtn extends StatelessWidget {
  final bool isLiked;
  final VoidCallback onTap;
  final double size;
  const _PhotoLikeBtn({required this.isLiked, required this.onTap, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: isLiked ? Colors.red : Colors.white,
          size: size * 0.53,
        ),
      ),
    );
  }
}

// ─── Photo Bookmark Button (on card image overlay) ─────────────
class _PhotoBookmarkBtn extends StatelessWidget {
  final bool isSaved;
  final VoidCallback onTap;
  const _PhotoBookmarkBtn({required this.isSaved, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: isSaved
              ? AppTheme.accent.withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          color: Colors.white,
          size: 16,
        ),
      ),
    );
  }
}

// ─── Photo Placeholder (colored initials) ─────────────────────
class _PhotoPlaceholder extends StatelessWidget {
  final bool isClosed;
  final String name;
  const _PhotoPlaceholder({required this.isClosed, required this.name});

  static const _palette = [
    Color(0xFF1565C0), Color(0xFF2E7D32), Color(0xFF6A1B9A),
    Color(0xFFC62828), Color(0xFF00695C), Color(0xFF283593),
    Color(0xFF4E342E), Color(0xFF0277BD), Color(0xFF558B2F),
  ];

  @override
  Widget build(BuildContext context) {
    if (isClosed) {
      return Container(
        color: Colors.grey.shade300,
        child: const Center(child: Icon(Icons.lock_rounded, size: 32, color: Colors.white54)),
      );
    }
    final initial = name.isNotEmpty ? name[0] : '؟';
    final color = name.isEmpty
        ? _palette[0]
        : _palette[name.codeUnitAt(0) % _palette.length];
    return Container(
      color: color,
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            fontSize: 38, fontWeight: FontWeight.w800, color: Colors.white,
          ),
        ),
      ),
    );
  }
}
