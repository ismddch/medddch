import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/models.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final SupabaseService _service = SupabaseService();
  final TextEditingController _searchCtrl = TextEditingController();

  List<UserModel> _all = [];
  List<UserModel> _filtered = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await _service.getAllCustomers();
      if (mounted) {
        setState(() {
          _all      = users;
          _filtered = users;
          _loading  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _all
          : _all.where((u) =>
              u.name.toLowerCase().contains(q) ||
              u.phone.contains(q)).toList();
    });
  }

  Future<void> _toggleBlock(UserModel user) async {
    final action = user.isBlocked ? 'إلغاء الحظر' : 'حظر';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('$action المستخدم',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text(
            'هل تريد $action "${user.name}"؟',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    user.isBlocked ? AppTheme.success : AppTheme.danger,
              ),
              child: Text(action, style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      if (user.isBlocked) {
        await _service.unblockUser(user.id);
      } else {
        await _service.blockUser(user.id);
      }
      await _load();
      if (mounted) {
        _showSnack(
          user.isBlocked ? 'تم إلغاء الحظر' : 'تم حظر المستخدم',
          user.isBlocked ? AppTheme.success : AppTheme.danger,
        );
      }
    } catch (e) {
      if (mounted) _showSnack('حدث خطأ', AppTheme.danger);
    }
  }

  Future<void> _deleteUser(UserModel user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('حذف المستخدم',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text(
            'سيتم حذف حساب "${user.name}" نهائياً.\nلا يمكن التراجع عن هذا الإجراء.',
            style: GoogleFonts.cairo(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              child: Text('حذف نهائي', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteUser(user.id);
      await _load();
      if (mounted) _showSnack('تم حذف المستخدم', AppTheme.success);
    } catch (e) {
      if (mounted) _showSnack('حدث خطأ أثناء الحذف', AppTheme.danger);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.cairo()),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final blocked  = _all.where((u) => u.isBlocked).length;
    final active   = _all.length - blocked;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F5F0),
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        title: Text('إدارة المستخدمين',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Stats bar ─────────────────────────────────────────
          Container(
            color: AppTheme.primary,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Row(
              children: [
                _StatChip(
                  label: 'إجمالي',
                  value: '${_all.length}',
                  color: Colors.white24,
                ),
                const SizedBox(width: 10),
                _StatChip(
                  label: 'نشطون',
                  value: '$active',
                  color: AppTheme.success.withValues(alpha: 0.25),
                ),
                const SizedBox(width: 10),
                _StatChip(
                  label: 'محظورون',
                  value: '$blocked',
                  color: AppTheme.danger.withValues(alpha: 0.25),
                ),
              ],
            ),
          ),

          // ── Search box ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: TextField(
              controller: _searchCtrl,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو رقم الهاتف...',
                hintStyle: GoogleFonts.cairo(color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilter();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),

          // ── List ──────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.isNotEmpty
                              ? 'لا توجد نتائج'
                              : 'لا يوجد مستخدمون',
                          style: GoogleFonts.cairo(
                              color: AppTheme.textMuted, fontSize: 15),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _UserCard(
                            user: _filtered[i],
                            onBlock: () => _toggleBlock(_filtered[i]),
                            onDelete: () => _deleteUser(_filtered[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Stat chip ──────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.cairo(
                    fontSize: 22, fontWeight: FontWeight.w900,
                    color: Colors.white)),
            Text(label,
                style: GoogleFonts.cairo(fontSize: 11, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

// ── User card ──────────────────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onBlock;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.onBlock,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isBlocked = user.isBlocked;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: isBlocked
            ? Border.all(color: AppTheme.danger.withValues(alpha: 0.35), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isBlocked
                    ? AppTheme.danger.withValues(alpha: 0.12)
                    : AppTheme.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: user.imageUrl != null
                  ? ClipOval(
                      child: Image.network(user.imageUrl!, fit: BoxFit.cover))
                  : Icon(
                      isBlocked
                          ? Icons.block_rounded
                          : Icons.person_rounded,
                      color: isBlocked ? AppTheme.danger : AppTheme.accent,
                      size: 26,
                    ),
            ),
            const SizedBox(width: 14),

            // Name + phone + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          user.name,
                          style: GoogleFonts.cairo(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isBlocked
                                ? AppTheme.textMuted
                                : AppTheme.primary,
                            decoration: isBlocked
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isBlocked) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('محظور',
                              style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.danger)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user.phone,
                    style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                        letterSpacing: 0.5),
                  ),
                ],
              ),
            ),

            // Action buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Block / Unblock
                _ActionBtn(
                  icon: isBlocked
                      ? Icons.lock_open_rounded
                      : Icons.block_rounded,
                  color: isBlocked ? AppTheme.success : AppTheme.danger,
                  tooltip: isBlocked ? 'إلغاء الحظر' : 'حظر',
                  onTap: onBlock,
                ),
                const SizedBox(width: 8),
                // Delete
                _ActionBtn(
                  icon: Icons.delete_rounded,
                  color: AppTheme.danger,
                  tooltip: 'حذف',
                  onTap: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
