import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'queue_details_screen.dart';

class ChairsScreen extends StatefulWidget {
  const ChairsScreen({super.key});

  @override
  State<ChairsScreen> createState() => _ChairsScreenState();
}

class _ChairsScreenState extends State<ChairsScreen> {
  final SupabaseService _service = SupabaseService();
  List<ChairModel> _chairs = [];
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
      if (mounted) setState(() { _chairs = chairs; _barber = barber; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الكراسي المتاحة'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          // ─── Barber Info Banner ─────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                // ─── Barber Photo + Name ──────────
                if (_barber != null) ...[
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.accent, width: 3),
                      image: _barber!.imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(_barber!.imageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                      color: AppTheme.accent.withOpacity(0.2),
                    ),
                    child: _barber!.imageUrl == null
                        ? const Icon(Icons.content_cut_rounded,
                            color: AppTheme.accent, size: 36)
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
                  if (_barber!.address != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_on_outlined,
                            color: Colors.white54, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _barber!.address!,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
                Text(
                  'أهلاً ${user?.name ?? ''} — اختر كرسي',
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          // ─── Chairs Grid ──────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _chairs.isEmpty
                    ? Center(
                        child: Text(
                          'لا توجد كراسي متاحة',
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: GridView.builder(
                          padding: const EdgeInsets.all(20),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: _chairs.length,
                          itemBuilder: (context, index) {
                            final chair = _chairs[index];
                            return _ChairCard(
                              chair: chair,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        QueueDetailsScreen(chair: chair),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ChairCard extends StatelessWidget {
  final ChairModel chair;
  final VoidCallback onTap;

  const _ChairCard({required this.chair, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final bool isClosed = chair.isClosed;
    final bool isBusy = chair.queueLength > 3;
    final bool isEmpty = chair.queueLength == 0;
    final Color statusColor = isClosed
        ? AppTheme.textMuted
        : isEmpty
            ? AppTheme.success
            : isBusy
                ? AppTheme.danger
                : AppTheme.accent;

    return GestureDetector(
      onTap: isClosed ? null : onTap,
      child: Opacity(
        opacity: isClosed ? 0.6 : 1.0,
        child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.divider),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─── Chair Image (large) ─────────────
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.06),
                      image: chair.imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(chair.imageUrl!),
                              fit: BoxFit.cover,
                              colorFilter: isClosed
                                  ? const ColorFilter.mode(
                                      Colors.grey, BlendMode.saturation)
                                  : null,
                            )
                          : null,
                    ),
                    child: chair.imageUrl == null
                        ? Center(
                            child: Icon(
                              isClosed
                                  ? Icons.lock_rounded
                                  : Icons.chair_rounded,
                              size: 52,
                              color: statusColor.withOpacity(0.4),
                            ),
                          )
                        : null,
                  ),
                  if (isClosed)
                    Container(
                      color: Colors.black.withOpacity(0.3),
                      child: const Center(
                        child: Icon(Icons.lock_rounded,
                            color: Colors.white70, size: 36),
                      ),
                    ),
                ],
              ),
            ),

            // ─── Name + Queue Badge ──────────────
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      chair.name,
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isClosed
                            ? AppTheme.textMuted
                            : AppTheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isClosed
                            ? 'مغلق'
                            : isEmpty
                                ? 'متاح'
                                : 'مشغول',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
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
