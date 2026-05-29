import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'shop_barbers_screen.dart';

class ShopsListScreen extends StatefulWidget {
  const ShopsListScreen({super.key});

  @override
  State<ShopsListScreen> createState() => _ShopsListScreenState();
}

class _ShopsListScreenState extends State<ShopsListScreen> {
  final SupabaseService _service = SupabaseService();
  final _searchCtrl = TextEditingController();
  List<ShopModel> _shops = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final shops = await _service.getActiveShops();
      if (mounted) setState(() { _shops = shops; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ShopModel> get _filtered {
    if (_search.isEmpty) return _shops;
    final q = _search.toLowerCase();
    return _shops
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            (s.address?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final userName = context.watch<AuthProvider>().user?.name ?? '';

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // ─── Hero Header ────────────────────────────────────────
            SliverToBoxAdapter(child: _HeroHeader(userName: userName, shopCount: _shops.length, loading: _loading)),

            // ─── Search Bar ─────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              sliver: SliverToBoxAdapter(
                child: _SearchBar(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _search = v),
                  onClear: () { _searchCtrl.clear(); setState(() => _search = ''); },
                ),
              ),
            ),

            // ─── Section label ──────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              sliver: SliverToBoxAdapter(child: _SectionLabel(filtered: _filtered.length, search: _search)),
            ),

            // ─── Content ────────────────────────────────────────────
            if (_loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (_filtered.isEmpty)
              SliverFillRemaining(child: _EmptyState(search: _search))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: _ShopCard(
                        shop: _filtered[i],
                        index: i,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShopBarbersScreen(shopId: _filtered[i].id),
                          ),
                        ),
                      ),
                    ),
                    childCount: _filtered.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Hero Header ──────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final String userName;
  final int shopCount;
  final bool loading;
  const _HeroHeader({required this.userName, required this.shopCount, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 20, 24, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1B2838), Color(0xFF253448)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.storefront_rounded, color: AppTheme.accent, size: 26),
              ),
              const Spacer(),
              if (!loading)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.store_rounded, color: AppTheme.accent, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        '$shopCount صالون',
                        style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            userName.isNotEmpty ? 'أهلاً، $userName 👋' : 'أهلاً بك',
            style: GoogleFonts.cairo(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            'اختر صالونك المفضل وابدأ الحجز الآن',
            style: GoogleFonts.cairo(fontSize: 13, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

// ─── Search Bar ───────────────────────────────────────────────
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  const _SearchBar({required this.controller, required this.onChanged, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.07),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: GoogleFonts.cairo(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'ابحث عن صالون...',
          hintStyle: GoogleFonts.cairo(color: AppTheme.textMuted, fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 22),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                  onPressed: onClear,
                )
              : null,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

// ─── Section Label ────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final int filtered;
  final String search;
  const _SectionLabel({required this.filtered, required this.search});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.auto_awesome_rounded, color: AppTheme.accent, size: 18),
        const SizedBox(width: 8),
        Text(
          'الصالونات المتاحة',
          style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w800, color: AppTheme.primary),
        ),
        const Spacer(),
        if (search.isNotEmpty)
          Text(
            '$filtered نتيجة',
            style: GoogleFonts.cairo(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final String search;
  const _EmptyState({required this.search});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, size: 72, color: AppTheme.textMuted.withValues(alpha: 0.25)),
          const SizedBox(height: 16),
          Text(
            search.isEmpty ? 'لا توجد صالونات متاحة حالياً' : 'لا نتائج لـ "$search"',
            style: GoogleFonts.cairo(fontSize: 15, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}

// ─── Shop Card ────────────────────────────────────────────────
class _ShopCard extends StatelessWidget {
  final ShopModel shop;
  final int index;
  final VoidCallback onTap;
  const _ShopCard({required this.shop, required this.index, required this.onTap});

  static const _gradients = [
    [Color(0xFF1B2838), Color(0xFF34495E)],
    [Color(0xFF0F3460), Color(0xFF533483)],
    [Color(0xFF2C3E50), Color(0xFF4A6741)],
    [Color(0xFF1A1A2E), Color(0xFF16213E)],
    [Color(0xFF2D1B69), Color(0xFF553C9A)],
    [Color(0xFF1a3a4a), Color(0xFF2e5f6b)],
  ];

  @override
  Widget build(BuildContext context) {
    final hasImage = shop.imageUrl != null && shop.imageUrl!.isNotEmpty;
    final colors = _gradients[index % _gradients.length];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 210,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ─── Background image or gradient ────────────────
              hasImage
                  ? Image.network(
                      shop.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _GradientBg(colors: colors),
                    )
                  : _GradientBg(colors: colors),

              // ─── Dark gradient overlay ────────────────────────
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.22),
                      Colors.black.withValues(alpha: 0.78),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),

              // ─── Top-right badges ─────────────────────────────
              Positioned(
                top: 14,
                right: 14,
                child: Row(
                  children: [
                    if (shop.vipEnabled) ...[
                      _OverlayBadge(label: 'VIP', icon: Icons.star_rounded, color: const Color(0xFFFFB300)),
                      const SizedBox(width: 6),
                    ],
                    if (shop.prepaymentEnabled)
                      _OverlayBadge(label: 'دفع مسبق', icon: Icons.payment_rounded, color: AppTheme.success),
                  ],
                ),
              ),

              // ─── Bottom info section ──────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        shop.name,
                        style: GoogleFonts.cairo(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (shop.address != null) ...[
                            const Icon(Icons.navigation_rounded, color: Colors.white54, size: 13),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                shop.address!,
                                style: GoogleFonts.cairo(fontSize: 12, color: Colors.white60),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ] else
                            const Spacer(),
                          if (shop.mapsUrl != null && shop.mapsUrl!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () async {
                                final uri = Uri.tryParse(shop.mapsUrl!);
                                if (uri != null && await canLaunchUrl(uri)) {
                                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.map_rounded, color: Colors.white, size: 12),
                                    const SizedBox(width: 4),
                                    Text('خريطة',
                                        style: GoogleFonts.cairo(
                                            fontSize: 10,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          // ─── CTA button ──────────────────────
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.accent.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'دخول',
                                  style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_back_ios_rounded, size: 12, color: Colors.white),
                              ],
                            ),
                          ),
                        ],
                      ),
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

class _GradientBg extends StatelessWidget {
  final List<Color> colors;
  const _GradientBg({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Center(
        child: Icon(Icons.storefront_rounded, size: 88, color: Colors.white.withValues(alpha: 0.07)),
      ),
    );
  }
}

// ─── Overlay Badge (on card image) ───────────────────────────
class _OverlayBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _OverlayBadge({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
