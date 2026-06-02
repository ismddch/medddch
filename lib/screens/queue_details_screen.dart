import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';
import 'payment_booking_screen.dart';
import 'service_selection_screen.dart';

const int _kMinutesPerPerson = 45;

class QueueDetailsScreen extends StatefulWidget {
  final BarberModel barber;

  const QueueDetailsScreen({super.key, required this.barber});

  @override
  State<QueueDetailsScreen> createState() => _QueueDetailsScreenState();
}

class _QueueDetailsScreenState extends State<QueueDetailsScreen> {
  final SupabaseService _service = SupabaseService();
  List<QueueEntryModel> _queue = [];
  List<String> _portfolioUrls = [];
  List<BarberMenuItemModel> _menuItems = [];
  ShopModel? _shop;
  BarberModel? _barberState;
  bool _loading = true;
  bool _portfolioLoading = true;
  bool _joining = false;
  bool _leaving = false;
  bool _inQueue = false;
  bool _inOtherQueue = false;
  int? _myPosition;
  int? _prevPosition; // tracks last known position to detect drops
  String? _myQueueType;
  PaymentRequestModel? _pendingPayment;
  RealtimeChannel? _subscription;
  RealtimeChannel? _paymentStatusChannel;

  @override
  void initState() {
    super.initState();
    _loadQueue();
    _subscription = _service.subscribeToQueues(_loadQueue);
  }

  @override
  void dispose() {
    if (_subscription          != null) _service.unsubscribe(_subscription!);
    if (_paymentStatusChannel  != null) _service.unsubscribe(_paymentStatusChannel!);
    super.dispose();
  }

  Future<void> _loadQueue() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;

    try {
      // Run all network calls in parallel
      final results = await Future.wait([
        _service.getQueueForBarber(widget.barber.id),
        _service.isUserInQueue(user.id),
        _service.getBarberById(widget.barber.id),
        _service.getShopById(widget.barber.shopId),
        _service.getUserPendingPayment(user.id, widget.barber.id),
        _service.getBarberPortfolio(widget.barber.id),
        _service.getAvailableBarberMenu(widget.barber.id),
      ]);
      final entry = await _service.getUserQueueEntry(user.id, widget.barber.id);

      if (mounted) {
        setState(() {
          _queue         = results[0] as List<QueueEntryModel>;
          final inAny   = results[1] as bool;
          _barberState   = results[2] as BarberModel?;
          _shop          = results[3] as ShopModel?;
          _pendingPayment = results[4] as PaymentRequestModel?;
          _portfolioUrls = results[5] as List<String>;
          _menuItems     = results[6] as List<BarberMenuItemModel>;
          _portfolioLoading = false;

          final oldPos = _prevPosition;
          if (entry != null) {
            _myPosition  = entry['position']   as int?;
            _myQueueType = entry['queue_type'] as String?;
          } else {
            _myPosition  = null;
            _myQueueType = null;
          }
          _prevPosition = _myPosition;
          _inQueue      = entry != null;
          _inOtherQueue = !_inQueue && inAny;
          _loading      = false;

          // Notify customer when position drops to 3, 2, or 1 (skip initial load)
          if (oldPos != null && _myPosition != null && _myPosition! < oldPos) {
            final barberName = _barberState?.name ?? '';
            if (_myPosition! == 3) {
              NotificationService.notifyCustomerPositionThree(
                  barberName: barberName);
            } else if (_myPosition! <= 2) {
              NotificationService.notifyCustomerPosition(_myPosition!,
                  barberName: barberName);
            }
          }
        });

        // Subscribe to this user's payment status once we know their userId.
        // Re-subscribe only if not already watching (avoid duplicate channels).
        _paymentStatusChannel ??= _service.subscribeToUserPaymentStatus(
            user.id, _onPaymentStatusChanged);
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _portfolioLoading = false; });
    }
  }

  Future<void> _onPaymentStatusChanged(
      Map<String, dynamic> record) async {
    if (!mounted) return;
    final status     = record['status'] as String? ?? '';
    final barberName = _barberState?.name ?? _pendingPayment?.barberName ?? '';

    if (status == 'approved') {
      final userId    = context.read<AuthProvider>().user?.id ?? '';
      int   position  = 1;
      try {
        final entry = await _service.getUserQueueEntry(
            userId, widget.barber.id);
        position = (entry?['position'] as int?) ?? 1;
      } catch (_) {}
      NotificationService.notifyCustomerBookingApproved(barberName, position);
    } else if (status == 'rejected') {
      NotificationService.notifyCustomerBookingRejected(barberName);
    }

    // Reload so the pending-payment widget disappears / queue appears
    if (mounted) _loadQueue();
  }

  /// Unified handler for all join/book buttons.
  ///
  /// Both flows:  service menu (filtered by type) → booking code
  ///              → payment screen (if shop.prepaymentEnabled) OR direct join
  Future<void> _handleJoin(String queueType) async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    if (_shop == null) return;

    final barber = _barberState ?? widget.barber;

    // ── Step 1: Service menu (both VIP and Normal, filtered by item type) ──
    // VIP sees VIP + 'both' items; Normal sees Normal + 'both' items.
    // Payment only applies to VIP (Step 3).
    final applicableItems = _menuItems.where((item) =>
        item.queueType == 'both' || item.queueType == queueType).toList();

    List<Map<String, dynamic>>? selectedServices;
    double? servicesTotal;

    if (applicableItems.isNotEmpty) {
      final menuResult = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceSelectionScreen(
            barber: barber,
            menuItems: applicableItems,
            queueType: queueType,
          ),
        ),
      );
      if (menuResult == null) return; // user pressed back
      final svcs = menuResult['services'] as List?;
      if (svcs != null && svcs.isNotEmpty) {
        selectedServices = svcs.cast<Map<String, dynamic>>();
      }
      servicesTotal = (menuResult['price'] as num?)?.toDouble();
      if (servicesTotal == 0) servicesTotal = null;
    }

    // ── Step 2: Booking code ────────────────────────────────────
    String? bookingCode;
    if (barber.bookingCodeEnabled) {
      bookingCode = await _showBookingCodeDialog();
      if (bookingCode == null) return; // cancelled
    }

    if (!mounted) return;

    // ── Step 3: payment screen (if shop requires prepayment) for ALL types ─
    // FIX (Bug 2): removed `queueType == 'vip'` guard — both VIP and Regular
    // customers must go through the payment/booking screen when the shop has
    // prepayment enabled.  The queue_type label (vip/normal) is still passed
    // through so the barber can see which tier each customer booked under.
    if (_shop!.prepaymentEnabled) {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentBookingScreen(
            barber: _barberState ?? widget.barber,
            shop: _shop!,
            queueType: queueType,
            prefilledAmount: servicesTotal,
            selectedServices: selectedServices,
          ),
        ),
      );
      if (result == true && mounted) {
        await _loadQueue();
        _showSnack('تم إرسال طلب الحجز، انتظر الموافقة', AppTheme.accent);
      }
    } else {
      setState(() => _joining = true);
      try {
        await _service.joinQueue(
          widget.barber.id,
          user.id,
          queueType: queueType,
          bookingCode: bookingCode,
          selectedServices: selectedServices,
          servicesTotal: servicesTotal,
        );
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
  }

  /// Shows a dialog prompting the customer to enter the barber's booking code.
  /// Returns the entered code string, or null if cancelled.
  Future<String?> _showBookingCodeDialog() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.vpn_key_rounded,
                    color: AppTheme.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'رمز الحجز مطلوب',
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'هذا الحلاق يتطلب رمزاً خاصاً للحجز.\nأدخل الرمز الذي حصلت عليه.',
                style: GoogleFonts.cairo(
                    fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6),
                decoration: InputDecoration(
                  hintText: 'XXXX',
                  hintStyle: GoogleFonts.cairo(
                      fontSize: 22,
                      color: AppTheme.textMuted.withValues(alpha: 0.4),
                      letterSpacing: 6),
                  prefixIcon: const Icon(Icons.lock_outline_rounded,
                      color: AppTheme.accent),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final code = ctrl.text.trim();
                if (code.isNotEmpty) Navigator.pop(ctx, code);
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text('تأكيد', style: GoogleFonts.cairo()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
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
    final barber = _barberState ?? widget.barber;
    final vipCount    = _queue.where((e) => e.queueType == 'vip').length;
    final inThisQueue = _myPosition != null;
    final peopleAhead = inThisQueue ? (_myPosition! - 1) : _queue.length;
    final estimatedMinutes = peopleAhead * _kMinutesPerPerson;

    final tiktokUrl = barber.tiktokUrl;
    final mapsUrl   = _shop?.mapsUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.barber.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (mapsUrl != null && mapsUrl.isNotEmpty)
            IconButton(
              tooltip: 'الموقع على الخريطة',
              icon: const Icon(Icons.map_rounded),
              onPressed: () async {
                final uri = Uri.tryParse(mapsUrl);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
          if (tiktokUrl != null && tiktokUrl.isNotEmpty)
            IconButton(
              tooltip: 'TikTok',
              icon: const FaIcon(FontAwesomeIcons.tiktok, size: 20),
              onPressed: () async {
                final uri = Uri.tryParse(tiktokUrl);
                if (uri != null && await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  // ─── Header: Shop + Barber ────────────
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
                        // Shop + Barber images
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_shop != null)
                              _ProfileCircle(
                                imageUrl: _shop!.imageUrl,
                                label: _shop!.name,
                                fallbackIcon: Icons.store_rounded,
                                isCircle: true,
                              ),
                            if (_shop != null) const SizedBox(width: 24),
                            _ProfileCircle(
                              imageUrl: widget.barber.imageUrl,
                              label: widget.barber.name,
                              fallbackIcon: Icons.content_cut_rounded,
                              isCircle: false,
                              onTap: widget.barber.imageUrl != null
                                  ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => _PortfolioViewer(
                                            photos: [widget.barber.imageUrl!],
                                            initialIndex: 0,
                                            barberId: widget.barber.id,
                                            barberName: widget.barber.name,
                                          ),
                                        ),
                                      )
                                  : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        // Combined queue count + VIP indicator
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _QueueCountBadge(
                              label: 'الطابور',
                              count: _queue.length,
                              icon: Icons.people_rounded,
                              color: AppTheme.accent,
                            ),
                            if (vipCount > 0) ...[
                              const SizedBox(width: 10),
                              _QueueCountBadge(
                                label: 'VIP',
                                count: vipCount,
                                icon: Icons.star_rounded,
                                color: const Color(0xFFFFB300),
                              ),
                            ],
                          ],
                        ),
                        // Booking-code required badge
                        if (barber.bookingCodeEnabled) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.vpn_key_rounded,
                                    color: Colors.orange, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  'يتطلب رمز حجز خاص',
                                  style: GoogleFonts.cairo(
                                    fontSize: 12,
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
                        ] else if (_inOtherQueue) ...[
                          // Already in another queue
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppTheme.danger.withValues(alpha: 0.2)),
                            ),
                            child: Text(
                              'أنت في طابور حلاق آخر',
                              style: GoogleFonts.cairo(
                                color: AppTheme.danger,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ] else if (_shop?.prepaymentEnabled == true &&
                            _pendingPayment != null) ...[
                          // Pending payment review state
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: AppTheme.accent.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: AppTheme.accent),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'طلب الحجز قيد المراجعة',
                                  style: GoogleFonts.cairo(
                                    color: AppTheme.accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // ── Two booking buttons: VIP + Regular ────────
                          Row(
                            children: [
                              Expanded(
                                child: _buildJoinButton(
                                  label: 'احجز VIP',
                                  icon: Icons.star_rounded,
                                  isLocked: barber.isVipLocked,
                                  lockedLabel: 'VIP مغلق',
                                  color: const Color(0xFFFFB300),
                                  onPressed: () => _handleJoin('vip'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildJoinButton(
                                  label: 'طابور عادي',
                                  icon: Icons.people_rounded,
                                  isLocked: barber.isNormalLocked,
                                  lockedLabel: 'مغلق',
                                  color: AppTheme.accent,
                                  onPressed: () => _handleJoin('normal'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ─── Menu Preview Section ──────────────────────
                  // Show menu preview whenever items exist
                  if (_menuItems.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    _buildMenuPreview(),
                  ],

                  // ─── Portfolio Section ─────────────────────────
                  if (_portfolioLoading) ...[
                    const SizedBox(height: 28),
                    const SizedBox(
                      height: 28,
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ] else if (_portfolioUrls.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    // ─── App logo above work images ───────────
                    Center(
                      child: Image.asset(
                        'assets/logo.png',
                        height: 56,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: AppTheme.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.photo_library_rounded,
                                    color: AppTheme.accent, size: 18),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'معرض أعمال الحلاق',
                                style: GoogleFonts.cairo(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_portfolioUrls.length} صور',
                                style: GoogleFonts.cairo(
                                    fontSize: 12, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 150,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              itemCount: _portfolioUrls.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, i) => GestureDetector(
                                onTap: () => _openPortfolioPhoto(i),
                                child: Hero(
                                  tag: 'portfolio_${widget.barber.id}_$i',
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: Image.network(
                                      _portfolioUrls[i],
                                      width: 150,
                                      height: 150,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        width: 150,
                                        height: 150,
                                        decoration: BoxDecoration(
                                          color: AppTheme.divider,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: const Icon(
                                            Icons.broken_image_rounded,
                                            color: AppTheme.textMuted,
                                            size: 32),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 36),
                ],
              ),
            ),
    );
  }

  void _openPortfolioPhoto(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PortfolioViewer(
          photos: _portfolioUrls,
          initialIndex: initialIndex,
          barberId: widget.barber.id,
          barberName: widget.barber.name,
        ),
      ),
    );
  }

  Widget _buildJoinButton({
    required String label,
    required IconData icon,
    required bool isLocked,
    required String lockedLabel,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: (_joining || isLocked) ? null : onPressed,
        icon: _joining
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(isLocked ? Icons.lock_rounded : icon, size: 20),
        label: Text(
          isLocked ? lockedLabel : label,
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isLocked ? AppTheme.textMuted : color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  // ─── In-Queue View ──────────────────────────────────────────
  Widget _buildInQueueView(int peopleAhead, int estimatedMinutes) {
    final isVip = _myQueueType == 'vip';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
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
            const SizedBox(height: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isVip
                    ? const Color(0xFFFFB300).withValues(alpha: 0.12)
                    : AppTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVip ? Icons.star_rounded : Icons.people_rounded,
                    size: 16,
                    color: isVip ? const Color(0xFFFFB300) : AppTheme.accent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isVip ? 'طابور VIP' : 'طابور عادي',
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color:
                          isVip ? const Color(0xFFFFB300) : AppTheme.accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isVip
                    ? const Color(0xFFFFB300).withValues(alpha: 0.12)
                    : AppTheme.accent.withValues(alpha: 0.1),
                border: Border.all(
                  color: isVip ? const Color(0xFFFFB300) : AppTheme.accent,
                  width: 3.5,
                ),
              ),
              child: Center(
                child: Text(
                  '$_myPosition',
                  style: GoogleFonts.cairo(
                    fontSize: 72,
                    fontWeight: FontWeight.w900,
                    color: isVip ? const Color(0xFFFFB300) : AppTheme.accent,
                    height: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'رقمك في الطابور',
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: AppTheme.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
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
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoTile(
                    icon: Icons.people_outline_rounded,
                    title: 'أمامك',
                    value: peopleAhead == 0 ? 'دورك الآن!' : '$peopleAhead أشخاص',
                    color: peopleAhead == 0 ? AppTheme.success : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
            if (peopleAhead == 0) ...[
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'دورك الآن! توجه للحلاق',
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
                color: AppTheme.primary.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.queue_rounded,
                  color: AppTheme.primary.withValues(alpha: 0.4), size: 32),
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
                  color: AppTheme.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'أنت مسجل في طابور حلاق آخر',
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

  // ─── Menu Preview ───────────────────────────────────────────
  // Shown so customers can browse services before booking.
  // Items are split into VIP and Regular sections by their queue_type.
  Widget _buildMenuPreview() {
    final vipItems    = _menuItems.where((i) => i.queueType == 'vip' || i.queueType == 'both').toList();
    final normalItems = _menuItems.where((i) => i.queueType == 'normal' || i.queueType == 'both').toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ──────────────────────────────
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.menu_book_rounded,
                    color: AppTheme.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'قائمة الخدمات',
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── VIP services ────────────────────────────────
          if (vipItems.isNotEmpty) ...[
            const _MenuSectionLabel(
              label: 'خدمات VIP',
              icon: Icons.star_rounded,
              color: Color(0xFFFFB300),
            ),
            const SizedBox(height: 8),
            _MenuServiceGroup(items: vipItems, accentColor: const Color(0xFFFFB300)),
            const SizedBox(height: 16),
          ],

          // ── Regular services ─────────────────────────────
          if (normalItems.isNotEmpty) ...[
            const _MenuSectionLabel(
              label: 'خدمات عادية',
              icon: Icons.people_rounded,
              color: AppTheme.accent,
            ),
            const SizedBox(height: 8),
            _MenuServiceGroup(items: normalItems, accentColor: AppTheme.accent),
          ],
        ],
      ),
    );
  }

}

// ─── Menu Section Label ───────────────────────────────────────
class _MenuSectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _MenuSectionLabel({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Menu Service Group ───────────────────────────────────────
class _MenuServiceGroup extends StatelessWidget {
  final List<BarberMenuItemModel> items;
  final Color accentColor;

  const _MenuServiceGroup({
    required this.items,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _ServiceRow(item: items[i], accentColor: accentColor),
          ],
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final BarberMenuItemModel item;
  final Color accentColor;

  const _ServiceRow({required this.item, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final available = item.isAvailable;
    final priceStr  = item.price == item.price.roundToDouble()
        ? '${item.price.toInt()} MRU'
        : '${item.price.toStringAsFixed(2)} MRU';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: available ? AppTheme.success : AppTheme.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.name,
              style: GoogleFonts.cairo(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: available ? AppTheme.primary : AppTheme.textMuted,
                decoration: available ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: available
                  ? accentColor.withValues(alpha: 0.1)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              priceStr,
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: available ? accentColor : AppTheme.textMuted,
              ),
              textDirection: TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Queue Count Badge ────────────────────────────────────────
class _QueueCountBadge extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _QueueCountBadge({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            '$label: $count',
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
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
  final VoidCallback? onTap;

  const _ProfileCircle({
    required this.imageUrl,
    required this.label,
    required this.fallbackIcon,
    required this.isCircle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
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
            ? AppTheme.accent.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.1),
      ),
      child: imageUrl == null
          ? Icon(fallbackIcon,
              color: isCircle ? AppTheme.accent : Colors.white54, size: 26)
          : null,
    );

    return Column(
      children: [
        // Tappable only when there's an image and a handler
        onTap != null && imageUrl != null
            ? GestureDetector(
                onTap: onTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    avatar,
                    // Small "expand" hint badge
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.zoom_in_rounded,
                            color: Colors.white, size: 12),
                      ),
                    ),
                  ],
                ),
              )
            : avatar,
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
        color: color.withValues(alpha: 0.06),
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

// ─── Full-screen portfolio photo viewer ───────────────────────────────────────
class _PortfolioViewer extends StatefulWidget {
  final List<String> photos;
  final int initialIndex;
  final String barberId;
  final String barberName;

  const _PortfolioViewer({
    required this.photos,
    required this.initialIndex,
    required this.barberId,
    required this.barberName,
  });

  @override
  State<_PortfolioViewer> createState() => _PortfolioViewerState();
}

class _PortfolioViewerState extends State<_PortfolioViewer> {
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
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.barberName,
              style: GoogleFonts.cairo(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${_current + 1} / ${widget.photos.length}',
              style: GoogleFonts.cairo(color: Colors.white60, fontSize: 12),
            ),
          ],
        ),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => Hero(
          tag: 'portfolio_${widget.barberId}_$i',
          child: InteractiveViewer(
            child: Center(
              child: Image.network(
                widget.photos[i],
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

