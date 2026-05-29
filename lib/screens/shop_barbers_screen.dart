import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'queue_details_screen.dart';

class ShopBarbersScreen extends StatefulWidget {
  final String shopId;
  const ShopBarbersScreen({super.key, required this.shopId});

  @override
  State<ShopBarbersScreen> createState() => _ShopBarbersScreenState();
}

class _ShopBarbersScreenState extends State<ShopBarbersScreen> {
  final SupabaseService _service = SupabaseService();
  List<BarberModel> _barbers = [];
  ShopModel? _shop;
  String? _likedBarberId;
  bool _loading = true;
  RealtimeChannel? _subscription;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadData);
    _subscription = _service.subscribeToQueues(() { if (mounted) _loadData(); });
  }

  @override
  void dispose() {
    if (_subscription != null) _service.unsubscribe(_subscription!);
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final userId = context.read<AuthProvider>().user?.id;
    try {
      final results = await Future.wait([
        _service.getBarbersWithLikes(widget.shopId),
        _service.getShopById(widget.shopId),
        if (userId != null) _service.getUserLikedBarberId(userId),
      ]);
      final barbers = results[0] as List<BarberModel>;
      final shop    = results[1] as ShopModel?;
      final liked   = userId != null ? results[2] as String? : null;

      // Sort by likes desc within the shop
      barbers.sort((a, b) => b.likeCount.compareTo(a.likeCount));

      if (mounted) {
        setState(() {
          _barbers       = barbers;
          _shop          = shop;
          _likedBarberId = liked;
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

  @override
  Widget build(BuildContext context) {
    final shop = _shop;
    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            // ─── Shop Banner Header ──────────────────────────────
            SliverToBoxAdapter(child: _ShopBanner(shop: shop)),

            // ─── Barbers Label ───────────────────────────────────
            if (!_loading && _barbers.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      const Icon(Icons.content_cut_rounded, color: AppTheme.accent, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'اختر حلاقك',
                        style: GoogleFonts.cairo(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.primary),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_barbers.length} حلاق',
                          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ─── Content ─────────────────────────────────────────
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_barbers.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.content_cut_outlined, size: 64, color: AppTheme.textMuted.withValues(alpha: 0.25)),
                      const SizedBox(height: 14),
                      Text('لا يوجد حلاقون متاحون حالياً',
                          style: GoogleFonts.cairo(fontSize: 15, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final barber  = _barbers[i];
                      final isLiked = _likedBarberId == barber.id;
                      final rank    = i + 1;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _BarberCard(
                          barber:  barber,
                          rank:    rank,
                          isLiked: isLiked,
                          onLike:  () => _toggleLike(barber),
                          onTap:   barber.isClosed
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => QueueDetailsScreen(barber: barber),
                                    ),
                                  ),
                        ),
                      );
                    },
                    childCount: _barbers.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Shop Banner ──────────────────────────────────────────────
class _ShopBanner extends StatelessWidget {
  final ShopModel? shop;
  const _ShopBanner({required this.shop});

  @override
  Widget build(BuildContext context) {
    final hasImage = shop?.imageUrl != null && shop!.imageUrl!.isNotEmpty;

    return Stack(
      children: [
        // ─── Background ─────────────────────────────────────
        Container(
          height: 220,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1B2838), Color(0xFF253448)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            image: hasImage
                ? DecorationImage(
                    image: NetworkImage(shop!.imageUrl!),
                    fit: BoxFit.cover,
                    colorFilter: const ColorFilter.mode(
                      Color(0x99000000),
                      BlendMode.darken,
                    ),
                  )
                : null,
          ),
        ),

        // ─── Back button ────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 16,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),

        // ─── Shop info overlay ───────────────────────────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (shop != null) ...[
                  Text(
                    shop!.name,
                    style: GoogleFonts.cairo(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  if (shop!.address != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.navigation_rounded, color: Colors.white54, size: 13),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            shop!.address!,
                            style: GoogleFonts.cairo(fontSize: 12, color: Colors.white60),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (shop!.mapsUrl != null && shop!.mapsUrl!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        final uri = Uri.tryParse(shop!.mapsUrl!);
                        if (uri != null && await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.map_rounded, color: Colors.white, size: 15),
                            const SizedBox(width: 6),
                            Text(
                              'عرض على الخريطة',
                              style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // VIP / prepayment badges
                  Row(
                    children: [
                      if (shop!.vipEnabled) ...[
                        _BannerBadge(label: 'VIP', icon: Icons.star_rounded, color: const Color(0xFFFFB300)),
                        const SizedBox(width: 8),
                      ],
                      if (shop!.prepaymentEnabled)
                        _BannerBadge(label: 'دفع مسبق', icon: Icons.payment_rounded, color: AppTheme.success),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BannerBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _BannerBadge({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

// ─── Barber Card ──────────────────────────────────────────────
class _BarberCard extends StatelessWidget {
  final BarberModel barber;
  final int rank;
  final bool isLiked;
  final VoidCallback? onTap;
  final VoidCallback onLike;

  const _BarberCard({
    required this.barber,
    required this.rank,
    required this.isLiked,
    required this.onTap,
    required this.onLike,
  });

  bool get _isTop3 => rank <= 3;

  Color get _medalColor {
    if (rank == 1) return const Color(0xFFFFD700);
    if (rank == 2) return const Color(0xFFC0C0C0);
    if (rank == 3) return const Color(0xFFCD7F32);
    return AppTheme.divider;
  }

  String get _medalEmoji {
    if (rank == 1) return '🥇';
    if (rank == 2) return '🥈';
    if (rank == 3) return '🥉';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isClosed   = barber.isClosed;
    final queueCount = barber.queueLength;
    final statusColor = isClosed
        ? AppTheme.textMuted
        : queueCount == 0
            ? AppTheme.success
            : queueCount > 3
                ? AppTheme.danger
                : AppTheme.accent;
    final statusLabel = isClosed
        ? 'مغلق'
        : queueCount == 0
            ? 'متاح الآن'
            : '$queueCount في الطابور';

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isClosed ? 0.7 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: _isTop3
                ? Border.all(color: _medalColor.withValues(alpha: 0.5), width: 1.5)
                : Border.all(color: AppTheme.divider),
            boxShadow: [
              BoxShadow(
                color: _isTop3
                    ? _medalColor.withValues(alpha: 0.10)
                    : AppTheme.primary.withValues(alpha: 0.04),
                blurRadius: _isTop3 ? 14 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // ─── Main row ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    // Photo
                    Stack(
                      children: [
                        Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _isTop3 ? _medalColor : AppTheme.divider,
                              width: _isTop3 ? 2.5 : 1.5,
                            ),
                            color: AppTheme.surface,
                            image: barber.imageUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(barber.imageUrl!),
                                    fit: BoxFit.cover,
                                    colorFilter: isClosed
                                        ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                                        : null,
                                  )
                                : null,
                          ),
                          child: barber.imageUrl == null
                              ? Center(
                                  child: Icon(
                                    isClosed ? Icons.lock_rounded : Icons.content_cut_rounded,
                                    color: statusColor.withValues(alpha: 0.35),
                                    size: 30,
                                  ),
                                )
                              : null,
                        ),
                        // Medal overlay on photo
                        if (_isTop3)
                          Positioned(
                            bottom: -2,
                            left: -2,
                            child: Text(_medalEmoji, style: const TextStyle(fontSize: 18)),
                          ),
                      ],
                    ),
                    const SizedBox(width: 14),

                    // Name + status
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            barber.name,
                            style: GoogleFonts.cairo(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isClosed ? AppTheme.textMuted : AppTheme.primary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                statusLabel,
                                style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Like button
                    _LikeButton(isLiked: isLiked, count: barber.likeCount, onTap: onLike),
                  ],
                ),
              ),

              // ─── Action button (join queue) ─────────────────
              if (!isClosed)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        textStyle: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      icon: const Icon(Icons.queue_rounded, size: 18),
                      label: Text(
                        queueCount == 0 ? 'انضم فوراً' : 'انضم للطابور',
                        style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Container(
                    width: double.infinity,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.divider),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_rounded, size: 16, color: AppTheme.textMuted),
                        const SizedBox(width: 8),
                        Text('غير متاح حالياً',
                            style: GoogleFonts.cairo(fontSize: 13, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Animated Like Button ─────────────────────────────────────
class _LikeButton extends StatefulWidget {
  final bool isLiked;
  final int count;
  final VoidCallback onTap;

  const _LikeButton({required this.isLiked, required this.count, required this.onTap});

  @override
  State<_LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<_LikeButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _scale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handle() {
    _ctrl.forward(from: 0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _scale,
              builder: (_, __) => Transform.scale(
                scale: _scale.value,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    widget.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    key: ValueKey(widget.isLiked),
                    color: widget.isLiked ? Colors.red : AppTheme.textMuted,
                    size: 26,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.isLiked ? Colors.red : AppTheme.textMuted,
              ),
              child: Text('${widget.count}'),
            ),
          ],
        ),
      ),
    );
  }
}
