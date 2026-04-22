import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/models.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';
import 'barber_form_screen.dart';

class BarberDetailScreen extends StatefulWidget {
  final BarberModel barber;

  const BarberDetailScreen({super.key, required this.barber});

  @override
  State<BarberDetailScreen> createState() => _BarberDetailScreenState();
}

class _BarberDetailScreenState extends State<BarberDetailScreen> {
  final SupabaseService _service = SupabaseService();
  BarberModel? _barber;
  List<ChairModel> _chairs = [];
  List<QueueEntryModel> _queueEntries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final barber = await _service.getBarberById(widget.barber.id);
      final chairs = await _service.getChairs(widget.barber.id);
      final queue = await _service.getBarberQueue(widget.barber.id);
      if (mounted) {
        setState(() {
          _barber = barber ?? widget.barber;
          _chairs = chairs;
          _queueEntries = queue;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addChair() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => const _ChairFormDialog(),
    );
    if (result != null) {
      await _service.addChair(
        widget.barber.id,
        result['name']!,
        imageUrl: result['image_url']?.isEmpty == true ? null : result['image_url'],
      );
      _loadData();
    }
  }

  Future<void> _editChair(ChairModel chair) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _ChairFormDialog(chair: chair),
    );
    if (result != null) {
      await _service.updateChair(
        chair.id,
        name: result['name']!,
        imageUrl: result['image_url']?.isEmpty == true ? null : result['image_url'],
      );
      _loadData();
    }
  }

  Future<void> _deleteChair(ChairModel chair) async {
    final confirmed = await _showConfirmDialog(
      title: 'حذف الكرسي',
      message: 'هل تريد حذف "${chair.name}"؟ سيتم حذف الطابور المرتبط.',
    );
    if (confirmed) {
      await _service.deleteChair(chair.id);
      _loadData();
    }
  }

  Future<void> _createBarberAccount() async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _CreateBarberAccountDialog(barberName: _barber!.name),
    );
    if (result != null) {
      try {
        await _service.createBarberUser(
          name: result['name']!,
          phone: result['phone']!,
          password: result['password']!,
          barberId: widget.barber.id,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('تم إنشاء حساب الحلاق بنجاح', style: GoogleFonts.cairo()),
              backgroundColor: AppTheme.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e.toString().replaceAll('Exception: ', ''),
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
    }
  }

  Future<String?> _showTextDialog({
    required String title,
    required String hint,
  }) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title:
              Text(title, style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text('إضافة', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title:
              Text(title, style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
          content: Text(message, style: GoogleFonts.cairo()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              child: Text('حذف', style: GoogleFonts.cairo()),
            ),
          ],
        ),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final barber = _barber ?? widget.barber;

    return Scaffold(
      appBar: AppBar(
        title: Text(barber.name),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'تعديل',
            onPressed: () async {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BarberFormScreen(barber: barber),
                ),
              );
              if (updated == true) _loadData();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  // ─── Barber Profile Header ─────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    decoration: const BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(28),
                        bottomRight: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Photo
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppTheme.accent, width: 3),
                            image: barber.imageUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(barber.imageUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                            color: AppTheme.accent.withOpacity(0.2),
                          ),
                          child: barber.imageUrl == null
                              ? const Icon(Icons.content_cut_rounded,
                                  color: AppTheme.accent, size: 44)
                              : null,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          barber.name,
                          style: GoogleFonts.cairo(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'الرمز: ${barber.code}',
                            style: GoogleFonts.cairo(
                              fontSize: 13,
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Info row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (barber.phone != null) ...[
                              const Icon(Icons.phone_outlined,
                                  color: Colors.white54, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                barber.phone!,
                                style: GoogleFonts.cairo(
                                    fontSize: 12, color: Colors.white54),
                                textDirection: TextDirection.ltr,
                              ),
                              const SizedBox(width: 16),
                            ],
                            if (barber.address != null) ...[
                              const Icon(Icons.location_on_outlined,
                                  color: Colors.white54, size: 14),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  barber.address!,
                                  style: GoogleFonts.cairo(
                                      fontSize: 12, color: Colors.white54),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Quick stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _MiniStat(
                              icon: Icons.chair_rounded,
                              value: '${_chairs.length}',
                              label: 'كراسي',
                            ),
                            const SizedBox(width: 24),
                            _MiniStat(
                              icon: Icons.people_rounded,
                              value: '${_queueEntries.length}',
                              label: 'في الطابور',
                            ),
                            const SizedBox(width: 24),
                            _MiniStat(
                              icon: barber.isActive
                                  ? Icons.check_circle_rounded
                                  : Icons.cancel_rounded,
                              value: barber.isActive ? 'نشط' : 'معطل',
                              label: 'الحالة',
                              color: barber.isActive
                                  ? AppTheme.success
                                  : AppTheme.danger,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ─── Chairs Section ────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'الكراسي (${_chairs.length})',
                            style: GoogleFonts.cairo(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _addChair,
                          icon: const Icon(Icons.add_rounded,
                              size: 20, color: AppTheme.accent),
                          label: Text('إضافة',
                              style: GoogleFonts.cairo(
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_chairs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'لا توجد كراسي — اضغط "إضافة"',
                          style: GoogleFonts.cairo(
                              fontSize: 14, color: AppTheme.textMuted),
                        ),
                      ),
                    )
                  else
                    ...List.generate(_chairs.length, (i) {
                      final chair = _chairs[i];
                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 5),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Row(
                          children: [
                            // ─── Chair Image ─────────────
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: AppTheme.accent.withOpacity(0.3),
                                  width: 2,
                                ),
                                image: chair.imageUrl != null
                                    ? DecorationImage(
                                        image: NetworkImage(chair.imageUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                                color: AppTheme.accent.withOpacity(0.1),
                              ),
                              child: chair.imageUrl == null
                                  ? const Icon(Icons.chair_rounded,
                                      color: AppTheme.accent, size: 24)
                                  : null,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    chair.name,
                                    style: GoogleFonts.cairo(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  Text(
                                    '${chair.queueLength} في الانتظار',
                                    style: GoogleFonts.cairo(
                                      fontSize: 12,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: AppTheme.accent, size: 20),
                              onPressed: () => _editChair(chair),
                              tooltip: 'تعديل',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: AppTheme.danger, size: 22),
                              onPressed: () => _deleteChair(chair),
                              tooltip: 'حذف الكرسي',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                  minWidth: 36, minHeight: 36),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 28),

                  // ─── Barber Account Section ────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'حساب الحلاق',
                      style: GoogleFonts.cairo(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _createBarberAccount,
                        icon: const Icon(Icons.person_add_alt_1_rounded,
                            size: 20),
                        label: Text('إنشاء حساب حلاق لهذا الصالون',
                            style: GoogleFonts.cairo(
                                fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          side: const BorderSide(color: AppTheme.accent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─── Mini Stat Widget ─────────────────────────────────────────
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color ?? Colors.white70, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: color ?? Colors.white,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.cairo(fontSize: 11, color: Colors.white54),
        ),
      ],
    );
  }
}

// ─── Create Barber Account Dialog ─────────────────────────────
class _CreateBarberAccountDialog extends StatefulWidget {
  final String barberName;

  const _CreateBarberAccountDialog({required this.barberName});

  @override
  State<_CreateBarberAccountDialog> createState() =>
      _CreateBarberAccountDialogState();
}

class _CreateBarberAccountDialogState
    extends State<_CreateBarberAccountDialog> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.barberName;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('إنشاء حساب حلاق',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    hintText: 'اسم الحلاق',
                    prefixIcon: const Icon(Icons.person_outline,
                        color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'أدخل الاسم' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    hintText: 'رقم الهاتف',
                    prefixIcon: const Icon(Icons.phone_outlined,
                        color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'أدخل رقم الهاتف' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  decoration: InputDecoration(
                    hintText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline,
                        color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
                    if (v.length < 4) return 'كلمة المرور قصيرة';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, {
                  'name': _nameCtrl.text.trim(),
                  'phone': _phoneCtrl.text.trim(),
                  'password': _passCtrl.text.trim(),
                });
              }
            },
            child: Text('إنشاء', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }
}

// ─── Chair Form Dialog (Add / Edit) with Image Upload ─────
class _ChairFormDialog extends StatefulWidget {
  final ChairModel? chair;

  const _ChairFormDialog({this.chair});

  @override
  State<_ChairFormDialog> createState() => _ChairFormDialogState();
}

class _ChairFormDialogState extends State<_ChairFormDialog> {
  final SupabaseService _service = SupabaseService();
  final _picker = ImagePicker();
  late final TextEditingController _nameCtrl;
  final _formKey = GlobalKey<FormState>();

  Uint8List? _pickedBytes;
  String? _pickedExt;
  String? _existingImageUrl;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.chair?.name ?? '');
    _existingImageUrl = widget.chair?.imageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 80,
    );

    if (picked != null) {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      setState(() {
        _pickedBytes = bytes;
        _pickedExt = ext.isNotEmpty ? ext : 'jpg';
        _existingImageUrl = null;
      });
    }
  }

  void _removeImage() {
    setState(() {
      _pickedBytes = null;
      _pickedExt = null;
      _existingImageUrl = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    String? imageUrl = _existingImageUrl;

    // Upload if new image picked
    if (_pickedBytes != null) {
      setState(() => _uploading = true);
      try {
        imageUrl = await _service.uploadImage(
          _pickedBytes!,
          fileExt: _pickedExt ?? 'jpg',
          folder: 'chairs',
        );
      } catch (e) {
        setState(() => _uploading = false);
        return;
      }
      setState(() => _uploading = false);
    }

    if (mounted) {
      Navigator.pop(context, {
        'name': _nameCtrl.text.trim(),
        'image_url': imageUrl ?? '',
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.chair != null;
    final hasLocal = _pickedBytes != null;
    final hasNetwork =
        _existingImageUrl != null && _existingImageUrl!.isNotEmpty;
    final hasImage = hasLocal || hasNetwork;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isEdit ? 'تعديل الكرسي' : 'إضافة كرسي',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ─── Image Picker ──────────────
                Stack(
                  children: [
                    GestureDetector(
                      onTap: _uploading ? null : _pickImage,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppTheme.accent, width: 2.5),
                          color: AppTheme.primary.withOpacity(0.05),
                          image: hasLocal
                              ? DecorationImage(
                                  image: MemoryImage(_pickedBytes!),
                                  fit: BoxFit.cover,
                                )
                              : hasNetwork
                                  ? DecorationImage(
                                      image:
                                          NetworkImage(_existingImageUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                        ),
                        child: !hasImage
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_a_photo_rounded,
                                      color: AppTheme.accent, size: 28),
                                  const SizedBox(height: 4),
                                  Text(
                                    'اختر صورة',
                                    style: GoogleFonts.cairo(
                                        fontSize: 10,
                                        color: AppTheme.textMuted),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                    if (hasImage && !_uploading)
                      Positioned(
                        top: -4,
                        left: -4,
                        child: GestureDetector(
                          onTap: _removeImage,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: AppTheme.danger,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    if (_uploading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                // ─── Name Field ────────────────
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: !hasImage,
                  decoration: InputDecoration(
                    hintText: 'اسم الكرسي (مثال: كرسي 4)',
                    prefixIcon: const Icon(Icons.chair_rounded,
                        color: AppTheme.accent),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'أدخل اسم الكرسي'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _uploading ? null : () => Navigator.pop(context),
            child: Text('إلغاء', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: _uploading ? null : _submit,
            child: _uploading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    isEdit ? 'حفظ' : 'إضافة',
                    style: GoogleFonts.cairo(),
                  ),
          ),
        ],
      ),
    );
  }
}
