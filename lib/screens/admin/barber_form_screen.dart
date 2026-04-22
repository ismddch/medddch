import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/models.dart';
import '../../services/supabase_service.dart';
import '../../utils/theme.dart';

class BarberFormScreen extends StatefulWidget {
  final BarberModel? barber;

  const BarberFormScreen({super.key, this.barber});

  @override
  State<BarberFormScreen> createState() => _BarberFormScreenState();
}

class _BarberFormScreenState extends State<BarberFormScreen> {
  final SupabaseService _service = SupabaseService();
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;

  bool _isEdit = false;
  bool _saving = false;
  bool _uploading = false;

  Uint8List? _pickedBytes;
  String? _pickedExt;
  String? _imageUrl;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.barber != null;
    _nameCtrl = TextEditingController(text: widget.barber?.name ?? '');
    _codeCtrl = TextEditingController(text: widget.barber?.code ?? '');
    _phoneCtrl = TextEditingController(text: widget.barber?.phone ?? '');
    _addressCtrl = TextEditingController(text: widget.barber?.address ?? '');
    _imageUrl = widget.barber?.imageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );

    if (picked != null) {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.split('.').last.toLowerCase();
      setState(() {
        _pickedBytes = bytes;
        _pickedExt = ext.isNotEmpty ? ext : 'jpg';
        _imageUrl = null; // clear old URL since we have new local image
      });
    }
  }

  void _removeImage() {
    setState(() {
      _pickedBytes = null;
      _pickedExt = null;
      _imageUrl = null;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      String? finalImageUrl = _imageUrl;
      if (_pickedBytes != null) {
        setState(() => _uploading = true);
        finalImageUrl = await _service.uploadImage(
          _pickedBytes!,
          fileExt: _pickedExt ?? 'jpg',
          folder: 'barbers',
        );
        setState(() => _uploading = false);
      }

      if (_isEdit) {
        await _service.updateBarber(
          barberId: widget.barber!.id,
          name: _nameCtrl.text.trim(),
          imageUrl: finalImageUrl,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        );
      } else {
        await _service.createBarber(
          name: _nameCtrl.text.trim(),
          code: _codeCtrl.text.trim().toUpperCase(),
          imageUrl: finalImageUrl,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEdit ? 'تم تحديث الصالون بنجاح' : 'تم إنشاء الصالون بنجاح',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', ''),
                style: GoogleFonts.cairo()),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() { _saving = false; _uploading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLocal = _pickedBytes != null;
    final hasNetwork = _imageUrl != null && _imageUrl!.isNotEmpty;
    final hasAnyImage = hasLocal || hasNetwork;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تعديل الصالون' : 'إضافة صالون جديد'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Image Picker ──────────────────
              Center(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppTheme.accent, width: 3),
                          color: AppTheme.primary.withOpacity(0.05),
                          image: hasLocal
                              ? DecorationImage(
                                  image: MemoryImage(_pickedBytes!),
                                  fit: BoxFit.cover,
                                )
                              : hasNetwork
                                  ? DecorationImage(
                                      image: NetworkImage(_imageUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                        ),
                        child: !hasAnyImage
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.add_a_photo_rounded,
                                      color: AppTheme.accent, size: 36),
                                  const SizedBox(height: 6),
                                  Text('اضغط لاختيار صورة',
                                      style: GoogleFonts.cairo(
                                          fontSize: 11,
                                          color: AppTheme.textMuted)),
                                ],
                              )
                            : null,
                      ),
                    ),
                    if (hasAnyImage)
                      Positioned(
                        top: -4, left: -4,
                        child: GestureDetector(
                          onTap: _removeImage,
                          child: Container(
                            width: 32, height: 32,
                            decoration: const BoxDecoration(
                              color: AppTheme.danger,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                      ),
                    if (_uploading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 3),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              _buildLabel('اسم الصالون'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  hintText: 'مثال: صالون أحمد',
                  prefixIcon: Icon(Icons.store_rounded, color: AppTheme.accent),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'أدخل اسم الصالون' : null,
              ),
              const SizedBox(height: 20),

              _buildLabel('رمز الحلاق'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _codeCtrl,
                enabled: !_isEdit,
                textDirection: TextDirection.ltr,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'مثال: BARBER003',
                  prefixIcon: const Icon(Icons.qr_code_rounded,
                      color: AppTheme.accent),
                  fillColor: _isEdit ? AppTheme.surface : Colors.white,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'أدخل رمز الحلاق';
                  if (v.trim().length < 3) return 'الرمز قصير جداً';
                  return null;
                },
              ),
              if (_isEdit)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('لا يمكن تغيير الرمز بعد الإنشاء',
                      style: GoogleFonts.cairo(
                          fontSize: 11, color: AppTheme.textMuted)),
                ),
              const SizedBox(height: 20),

              _buildLabel('رقم الهاتف (اختياري)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  hintText: '05XXXXXXXX',
                  prefixIcon: Icon(Icons.phone_outlined, color: AppTheme.accent),
                ),
              ),
              const SizedBox(height: 20),

              _buildLabel('العنوان (اختياري)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  hintText: 'مثال: شارع الملك فهد، الرياض',
                  prefixIcon:
                      Icon(Icons.location_on_outlined, color: AppTheme.accent),
                ),
              ),
              const SizedBox(height: 36),

              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            ),
                            if (_uploading) ...[
                              const SizedBox(width: 12),
                              Text('جاري رفع الصورة...',
                                  style: GoogleFonts.cairo(
                                      fontSize: 14, color: Colors.white70)),
                            ],
                          ],
                        )
                      : Text(_isEdit ? 'حفظ التعديلات' : 'إنشاء الصالون'),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(text,
        style: GoogleFonts.cairo(
            fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary));
  }
}
