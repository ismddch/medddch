import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';

class ProductsScreen extends StatefulWidget {
  final String? barberId;
  const ProductsScreen({super.key, this.barberId});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _service = SupabaseService();
  List<ProductModel> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final effectiveBarberId = widget.barberId ??
        context.read<AuthProvider>().user?.barberId;
    if (effectiveBarberId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final products = await _service.getProducts(effectiveBarberId);
      if (mounted) setState(() { _products = products; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في تحميل المنتجات: ${e.toString().replaceAll('Exception: ', '')}',
              style: GoogleFonts.cairo(),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  Future<void> _showAddProduct(String barberId) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddProductSheet(
        barberId: barberId,
        service: _service,
        onAdded: _load,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final effectiveBarberId = widget.barberId ?? user?.barberId;
    final canPost = widget.barberId != null ||
        user?.isAdmin == true ||
        user?.isBarber == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('المنتجات'),
        automaticallyImplyLeading: widget.barberId != null,
      ),
      floatingActionButton: (canPost && effectiveBarberId != null)
          ? FloatingActionButton.extended(
              onPressed: () => _showAddProduct(effectiveBarberId),
              backgroundColor: AppTheme.accent,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text('إضافة منتج',
                  style: GoogleFonts.cairo(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _products.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shopping_bag_outlined,
                          size: 72, color: AppTheme.textMuted),
                      const SizedBox(height: 12),
                      Text('لا توجد منتجات بعد',
                          style: GoogleFonts.cairo(
                              color: AppTheme.textMuted, fontSize: 16)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _products.length,
                    itemBuilder: (_, i) => _ProductCard(
                      product: _products[i],
                      canEdit: canPost,
                      service: _service,
                      onChanged: _load,
                    ),
                  ),
                ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final bool canEdit;
  final SupabaseService service;
  final VoidCallback onChanged;

  const _ProductCard({
    required this.product,
    required this.canEdit,
    required this.service,
    required this.onChanged,
  });

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف المنتج',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
        content:
            Text('هل تريد حذف هذا المنتج؟', style: GoogleFonts.cairo()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('إلغاء', style: GoogleFonts.cairo())),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('حذف',
                  style: GoogleFonts.cairo(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await service.deleteProduct(product.id);
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: product.imageUrl != null
                  ? Image.network(product.imageUrl!,
                      width: 80, height: 80, fit: BoxFit.cover)
                  : Container(
                      width: 80,
                      height: 80,
                      color: AppTheme.accent.withOpacity(0.1),
                      child: const Icon(Icons.image_outlined,
                          color: AppTheme.accent, size: 36),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: GoogleFonts.cairo(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  if (product.description != null &&
                      product.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(product.description!,
                        style: GoogleFonts.cairo(
                            color: AppTheme.textMuted, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (product.price != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${product.price!.toStringAsFixed(0)} MRU',
                      style: GoogleFonts.cairo(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppTheme.danger),
                onPressed: () => _delete(context),
              ),
          ],
        ),
      ),
    );
  }
}

class _AddProductSheet extends StatefulWidget {
  final String barberId;
  final SupabaseService service;
  final VoidCallback onAdded;

  const _AddProductSheet({
    required this.barberId,
    required this.service,
    required this.onAdded,
  });

  @override
  State<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<_AddProductSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _picker = ImagePicker();
  Uint8List? _imageBytes;
  String? _imageExt;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageExt = picked.name.split('.').last.toLowerCase();
    });
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      String? imageUrl;
      if (_imageBytes != null) {
        imageUrl = await widget.service.uploadImage(
          _imageBytes!,
          fileExt: _imageExt ?? 'jpg',
          folder: 'products',
        );
      }
      await widget.service.addProduct(
        barberId: widget.barberId,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        price: _priceCtrl.text.isEmpty
            ? null
            : double.tryParse(_priceCtrl.text),
        imageUrl: imageUrl,
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onAdded();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'فشل إضافة المنتج: ${e.toString().replaceAll('Exception: ', '')}',
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text('إضافة منتج',
                style: GoogleFonts.cairo(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),

            // Image picker
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                ),
                child: _imageBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_photo_alternate_outlined,
                              color: AppTheme.accent, size: 32),
                          const SizedBox(height: 8),
                          Text('إضافة صورة',
                              style:
                                  GoogleFonts.cairo(color: AppTheme.accent)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم المنتج',
                prefixIcon:
                    Icon(Icons.label_outline, color: AppTheme.accent),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'الوصف (اختياري)',
                prefixIcon: Icon(Icons.description_outlined,
                    color: AppTheme.accent),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'السعر (اختياري)',
                prefixIcon:
                    Icon(Icons.attach_money_rounded, color: AppTheme.accent),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      )
                    : Text('حفظ المنتج',
                        style: GoogleFonts.cairo(
                            fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
