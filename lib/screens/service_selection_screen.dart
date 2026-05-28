import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/models.dart';
import '../utils/theme.dart';

/// Dedicated full-page service selector — single selection.
///
/// Returns via Navigator.pop:
///   {'service': Map<String,dynamic>, 'price': double}
/// Returns null if user pressed the back button without selecting.
class ServiceSelectionScreen extends StatefulWidget {
  final BarberModel barber;
  final List<BarberMenuItemModel> menuItems;
  final String queueType; // 'vip' | 'normal'

  const ServiceSelectionScreen({
    super.key,
    required this.barber,
    required this.menuItems,
    required this.queueType,
  });

  @override
  State<ServiceSelectionScreen> createState() =>
      _ServiceSelectionScreenState();
}

class _ServiceSelectionScreenState extends State<ServiceSelectionScreen> {
  String? _selectedId; // only one service selected at a time

  bool get _isVip => widget.queueType == 'vip';
  Color get _accent => _isVip ? const Color(0xFFFFB300) : AppTheme.accent;

  BarberMenuItemModel? get _selected =>
      _selectedId == null
          ? null
          : widget.menuItems.firstWhere((i) => i.id == _selectedId);

  void _select(String id) => setState(() => _selectedId = id);

  String _fmt(double price) => price == price.roundToDouble()
      ? '${price.toInt()} MRU'
      : '${price.toStringAsFixed(2)} MRU';

  void _confirm() {
    final item = _selected;
    if (item == null) return;
    Navigator.pop(context, {
      'services': [item.toSelectedJson()],
      'price': item.price,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        body: Column(
          children: [
            _buildHeader(),
            // Hint
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  Icon(Icons.touch_app_rounded,
                      size: 15,
                      color: AppTheme.textMuted.withValues(alpha: 0.7)),
                  const SizedBox(width: 6),
                  Text(
                    'اختر خدمة واحدة للمتابعة إلى الدفع',
                    style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: AppTheme.textMuted.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
            // Service list
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                itemCount: widget.menuItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final item = widget.menuItems[i];
                  final isSelected = _selectedId == item.id;
                  return _ServiceCard(
                    item: item,
                    isSelected: isSelected,
                    accent: _accent,
                    onTap: () => _select(item.id),
                  );
                },
              ),
            ),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ── Gradient header ────────────────────────────────────────
  Widget _buildHeader() {
    final sel = _selected;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Nav row
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded,
                        color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      'قائمة الخدمات',
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Barber info
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _accent.withValues(alpha: 0.6), width: 2.5),
                    image: widget.barber.imageUrl != null
                        ? DecorationImage(
                            image: NetworkImage(widget.barber.imageUrl!),
                            fit: BoxFit.cover)
                        : null,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                  child: widget.barber.imageUrl == null
                      ? const Icon(Icons.content_cut_rounded,
                          color: Colors.white, size: 26)
                      : null,
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.barber.name,
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isVip
                                ? Icons.star_rounded
                                : Icons.people_rounded,
                            color: _accent,
                            size: 13,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _isVip ? 'طابور VIP' : 'طابور عادي',
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Selected service pill
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: sel != null
                    ? _accent.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: sel != null
                      ? _accent.withValues(alpha: 0.4)
                      : Colors.white.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    sel != null
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: sel != null ? _accent : Colors.white38,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        sel != null ? sel.name : 'لم تختر خدمة بعد',
                        key: ValueKey(sel?.id ?? 'none'),
                        style: GoogleFonts.cairo(
                          fontSize: 14,
                          color: sel != null ? Colors.white : Colors.white54,
                          fontWeight: sel != null
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (sel != null) ...[
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _fmt(sel.price),
                        key: ValueKey(sel.id),
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: _accent,
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────
  Widget _buildBottomBar() {
    final sel = _selected;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          onPressed: sel != null ? _confirm : null,
          icon: const Icon(Icons.arrow_forward_rounded, size: 20),
          label: Text(
            sel != null
                ? 'متابعة — ${_fmt(sel.price)}'
                : 'اختر خدمة للمتابعة',
            style: GoogleFonts.cairo(
                fontSize: 16, fontWeight: FontWeight.w700),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppTheme.divider,
            disabledForegroundColor: AppTheme.textMuted,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
    );
  }
}

// ─── Service Card ──────────────────────────────────────────────
class _ServiceCard extends StatelessWidget {
  final BarberMenuItemModel item;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.item,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final priceStr = item.price == item.price.roundToDouble()
        ? '${item.price.toInt()} MRU'
        : '${item.price.toStringAsFixed(2)} MRU';

    return GestureDetector(
      onTap: item.isAvailable ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color:
              isSelected ? accent.withValues(alpha: 0.07) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? accent : AppTheme.divider,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Row(
          children: [
            // Radio circle
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? accent : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? accent
                      : AppTheme.textMuted.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 16),

            // Name + availability tag
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: GoogleFonts.cairo(
                      fontSize: 16,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: item.isAvailable
                          ? AppTheme.primary
                          : AppTheme.textMuted,
                    ),
                  ),
                  if (!item.isAvailable) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppTheme.danger,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'غير متاحة حالياً',
                          style: GoogleFonts.cairo(
                              fontSize: 11, color: AppTheme.danger),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // Price badge
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: 0.12)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                priceStr,
                style: GoogleFonts.cairo(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? accent : AppTheme.textMuted,
                ),
                textDirection: TextDirection.ltr,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
