import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _service = SupabaseService();
  final _picker = ImagePicker();
  bool _saving = false;
  bool _uploadingImage = false;

  BarberModel? _currentBarber;
  List<BarberCodeHistoryModel> _barberHistory = [];
  bool _loadingBarber = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nameCtrl.text = user?.name ?? '';
    if (user != null && !user.isBarber && !user.isAdmin) {
      _loadBarberInfo(user);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBarberInfo(UserModel user) async {
    setState(() => _loadingBarber = true);
    try {
      final barber = user.barberId != null
          ? await _service.getBarberById(user.barberId!)
          : null;
      final history = await _service.getBarberCodeHistory(user.id);
      if (mounted) {
        setState(() {
          _currentBarber = barber;
          _barberHistory = history;
        });
      }
    } finally {
      if (mounted) setState(() => _loadingBarber = false);
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400,
      maxHeight: 400,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      final imageUrl = await _service.uploadImage(
        bytes,
        fileExt: ext.isNotEmpty ? ext : 'jpg',
        folder: 'profiles',
      );
      await context.read<AuthProvider>().updateProfile(imageUrl: imageUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'فشل تحميل الصورة: ${e.toString().replaceAll('Exception: ', '')}',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _removeImage() async {
    setState(() => _uploadingImage = true);
    try {
      await context.read<AuthProvider>().removeProfileImage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'فشل حذف الصورة: ${e.toString().replaceAll('Exception: ', '')}',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _saveProfile() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await context.read<AuthProvider>().updateProfile(name: name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('تم تحديث الملف الشخصي', style: GoogleFonts.cairo()),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التحديث', style: GoogleFonts.cairo())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showChangeBarberDialog() async {
    final codeCtrl = TextEditingController();
    bool changing = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: !changing,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('تغيير رمز الحلاق',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'أدخل الرمز الجديد للحلاق الذي تريد الانتساب إليه',
                style: GoogleFonts.cairo(
                    fontSize: 13, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'رمز الحلاق',
                  labelStyle: GoogleFonts.cairo(),
                  prefixIcon: const Icon(Icons.qr_code_rounded,
                      color: AppTheme.accent),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                style: GoogleFonts.cairo(
                    fontWeight: FontWeight.w700, letterSpacing: 2),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  changing ? null : () => Navigator.pop(ctx),
              child:
                  Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: changing
                  ? null
                  : () async {
                      final code = codeCtrl.text.trim();
                      if (code.isEmpty) return;
                      setDialogState(() => changing = true);
                      try {
                        final barber = await context
                            .read<AuthProvider>()
                            .changeBarberCode(code);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          setState(() {
                            _currentBarber = barber;
                          });
                          _reloadHistory();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'تم الانتساب إلى ${barber.name} بنجاح',
                                style: GoogleFonts.cairo(),
                              ),
                              backgroundColor: AppTheme.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => changing = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                e
                                    .toString()
                                    .replaceAll('Exception: ', ''),
                                style: GoogleFonts.cairo(),
                              ),
                              backgroundColor: AppTheme.danger,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent),
              child: changing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text('تأكيد',
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    codeCtrl.dispose();
  }

  Future<void> _reloadHistory() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final history = await _service.getBarberCodeHistory(user.id);
    if (mounted) setState(() => _barberHistory = history);
  }

  void _logout() {
    context.read<AuthProvider>().logout();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف الحساب',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content: Text(
          'هل أنت متأكد أنك تريد حذف حسابك نهائياً؟ لا يمكن التراجع عن هذا الإجراء.',
          style: GoogleFonts.cairo(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('حذف',
                style: GoogleFonts.cairo(
                    color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success =
        await context.read<AuthProvider>().deleteCurrentUserAccount();
    if (success && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الملف الشخصي'),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<AuthProvider>(
        builder: (_, auth, __) {
          final user = auth.user;
          if (user == null) return const SizedBox.shrink();
          final isCustomer = !user.isBarber && !user.isAdmin;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 16),

                // ─── Avatar ─────────────────────────────────
                GestureDetector(
                  onTap: _uploadingImage ? null : _pickAndUploadImage,
                  child: Stack(
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppTheme.accent, width: 3),
                          color: AppTheme.accent.withOpacity(0.1),
                          image: user.imageUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(user.imageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _uploadingImage
                            ? const Padding(
                                padding: EdgeInsets.all(28),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5),
                              )
                            : user.imageUrl == null
                                ? const Icon(Icons.person_rounded,
                                    size: 52, color: AppTheme.accent)
                                : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              size: 16, color: Colors.white),
                        ),
                      ),
                      if (user.imageUrl != null && !_uploadingImage)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: GestureDetector(
                            onTap: _removeImage,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppTheme.danger,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  user.isAdmin
                      ? 'مدير'
                      : user.isBarber
                          ? 'حلاق'
                          : 'عميل',
                  style: GoogleFonts.cairo(
                      color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 32),

                // ─── Name field ──────────────────────────────
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الاسم',
                    prefixIcon:
                        Icon(Icons.person_outline, color: AppTheme.accent),
                  ),
                ),
                const SizedBox(height: 16),

                // ─── Phone (read-only) ───────────────────────
                TextField(
                  readOnly: true,
                  controller: TextEditingController(text: user.phone),
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon:
                        Icon(Icons.phone_outlined, color: AppTheme.accent),
                  ),
                ),
                const SizedBox(height: 24),

                // ─── Save button ─────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveProfile,
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text('حفظ التغييرات',
                            style: GoogleFonts.cairo(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),

                // ─── Barber Section (customers only) ─────────
                if (isCustomer) ...[
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'الحلاق المرتبط',
                      style: GoogleFonts.cairo(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingBarber)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    _CurrentBarberCard(barber: _currentBarber),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showChangeBarberDialog,
                      icon: const Icon(Icons.qr_code_rounded,
                          color: AppTheme.accent),
                      label: Text(
                        'تغيير رمز الحلاق',
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.accent),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.accent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (_barberHistory.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'سجل الحلاقين المستخدمين',
                        style: GoogleFonts.cairo(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...(_barberHistory
                        .map((h) => _BarberHistoryTile(entry: h))),
                  ],
                ],

                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),

                // ─── Logout ──────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout_rounded,
                        color: AppTheme.primary),
                    label: Text('تسجيل الخروج',
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ─── Delete Account ──────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _confirmDeleteAccount,
                    icon: const Icon(Icons.delete_forever_rounded,
                        color: Colors.red),
                    label: Text('حذف الحساب',
                        style: GoogleFonts.cairo(
                            fontWeight: FontWeight.w600,
                            color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Current Barber Card ──────────────────────────────────
class _CurrentBarberCard extends StatelessWidget {
  final BarberModel? barber;
  const _CurrentBarberCard({required this.barber});

  @override
  Widget build(BuildContext context) {
    if (barber == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.textMuted.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.content_cut_rounded,
                color: AppTheme.textMuted, size: 28),
            const SizedBox(width: 12),
            Text('لا يوجد حلاق مرتبط',
                style: GoogleFonts.cairo(color: AppTheme.textMuted)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppTheme.accent.withOpacity(0.15),
            backgroundImage: barber!.imageUrl != null
                ? NetworkImage(barber!.imageUrl!)
                : null,
            child: barber!.imageUrl == null
                ? const Icon(Icons.content_cut_rounded,
                    color: AppTheme.accent, size: 22)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  barber!.name,
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  'الرمز: ${barber!.code}',
                  style: GoogleFonts.cairo(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                      letterSpacing: 1),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'مرتبط',
              style: GoogleFonts.cairo(
                  color: AppTheme.success,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Barber History Tile ──────────────────────────────────
class _BarberHistoryTile extends StatelessWidget {
  final BarberCodeHistoryModel entry;
  const _BarberHistoryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final formatted =
        DateFormat('yyyy/MM/dd – HH:mm').format(entry.changedAt.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.content_cut_rounded,
                size: 18, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.barberName,
                  style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  'الرمز: ${entry.barberCode}',
                  style: GoogleFonts.cairo(
                      color: AppTheme.textMuted,
                      fontSize: 12,
                      letterSpacing: 1),
                ),
              ],
            ),
          ),
          Text(
            formatted,
            style: GoogleFonts.cairo(
                color: AppTheme.textMuted, fontSize: 11),
            textAlign: TextAlign.end,
          ),
        ],
      ),
    );
  }
}
