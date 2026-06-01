import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';

class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  SupabaseClient get client => _client;

  // ─── IMAGE UPLOAD ───────────────────────────────────────

  /// Upload image bytes to Supabase Storage and return its public URL.
  /// Works on both web and mobile.
  Future<String> uploadImage(
    Uint8List bytes, {
    required String fileExt,
    String bucket = 'images',
    String folder = 'uploads',
  }) async {
    final fileName = '$folder/${DateTime.now().millisecondsSinceEpoch}.$fileExt';
    final mime = _mimeFromExt(fileExt);

    await _client.storage.from(bucket).uploadBinary(
      fileName,
      bytes,
      fileOptions: FileOptions(upsert: true, contentType: mime),
    );

    return _client.storage.from(bucket).getPublicUrl(fileName);
  }

  String _mimeFromExt(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':  return 'image/png';
      case 'webp': return 'image/webp';
      case 'gif':  return 'image/gif';
      case 'heic': return 'image/heic';
      case 'heif': return 'image/heif';
      default:     return 'image/jpeg';
    }
  }

  // ─── AUTH ─────────────────────────────────────────────────

  /// Get a user by ID (used for session restoration).
  Future<UserModel?> getUserById(String userId) async {
    final res = await _client
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();
    if (res == null) return null;
    return UserModel.fromMap(res);
  }

  /// Update user profile fields.
  Future<void> updateUser({
    required String userId,
    String? name,
    String? imageUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (imageUrl != null) updates['image_url'] = imageUrl;
    if (updates.isEmpty) return;
    await _client.from('users').update(updates).eq('id', userId);
  }

  /// Remove the profile image (set image_url to null).
  Future<void> removeProfileImage(String userId) async {
    await _client
        .from('users')
        .update({'image_url': null}).eq('id', userId);
  }

  /// Login with phone + password (custom table auth).
  Future<UserModel?> login(String phone, String password) async {
    final res = await _client
        .from('users')
        .select()
        .eq('phone', phone)
        .eq('password', password)
        .maybeSingle();

    if (res == null) return null;
    return UserModel.fromMap(res);
  }

  /// Register a new customer account (no shop code required).
  Future<UserModel> register({
    required String name,
    required String phone,
    required String password,
  }) async {
    // Check if phone already exists
    final existing = await _client
        .from('users')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();

    if (existing != null) {
      throw Exception('رقم الهاتف مسجل بالفعل');
    }

    // Insert user without a pre-assigned shop
    final res = await _client
        .from('users')
        .insert({
          'name': name,
          'phone': phone,
          'password': password,
          'role': 'customer',
        })
        .select()
        .single();

    return UserModel.fromMap(res);
  }

  // ─── SHOP CODE CHANGE ─────────────────────────────────────

  /// Change a customer's linked shop using a new shop code. Records history.
  Future<ShopModel> changeShopCode(String userId, String code) async {
    final shopRes = await _client
        .from('shops')
        .select()
        .eq('code', code.trim().toUpperCase())
        .maybeSingle();

    if (shopRes == null) throw Exception('رمز الصالون غير صحيح');
    final shop = ShopModel.fromMap(shopRes);

    // NOTE: After restructure, users.barber_id references barbers (staff),
    // not shops. Customers are no longer linked to a shop via barber_id.
    // We only record the history and return the shop info.

    await _client.from('barber_code_history').insert({
      'user_id': userId,
      'shop_id': shop.id,
      'shop_name': shop.name,
      'shop_code': shop.code,
      'changed_at': DateTime.now().toUtc().toIso8601String(),
    });

    return shop;
  }

  /// Fetch the last 3 distinct shops from a customer's code-change history.
  Future<List<ShopCodeHistoryModel>> getShopCodeHistory(String userId) async {
    final res = await _client
        .from('barber_code_history')
        .select()
        .eq('user_id', userId)
        .order('changed_at', ascending: false);

    final seen = <String>{};
    final unique = <ShopCodeHistoryModel>[];
    for (final row in res as List) {
      final entry = ShopCodeHistoryModel.fromMap(row);
      if (seen.add(entry.shopId)) {
        unique.add(entry);
        if (unique.length == 3) break;
      }
    }
    return unique;
  }

  // ─── BARBERS (individual staff) ──────────────────────────

  /// Get all barbers (staff) for a shop, with current queue length.
  Future<List<BarberModel>> getBarbers(String shopId) async {
    final res = await _client
        .from('barbers')
        .select('*, queues(count)')
        .eq('shop_id', shopId)
        .order('name');

    return (res as List).map((row) {
      final count =
          row['queues'] != null && (row['queues'] as List).isNotEmpty
              ? row['queues'][0]['count'] ?? 0
              : 0;
      return BarberModel(
        id: row['id'],
        shopId: row['shop_id'],
        name: row['name'],
        imageUrl: row['image_url'],
        isClosed: row['is_closed'] ?? false,
        isVipLocked: row['vip_locked'] ?? false,
        isNormalLocked: row['normal_locked'] ?? false,
        bookingCodeEnabled: row['booking_code_enabled'] ?? false,
        queueLength: count is int ? count : int.tryParse('$count') ?? 0,
        paymentNumber: row['payment_number'],
        walletNumbers: Map<String, String>.from(
          ((row['wallet_numbers'] as Map<String, dynamic>?) ?? {})
              .map((k, v) => MapEntry(k, v?.toString() ?? '')),
        ),
      );
    }).toList();
  }

  /// Get a single barber (staff) by ID.
  Future<BarberModel?> getBarberById(String barberId) async {
    final res = await _client
        .from('barbers')
        .select()
        .eq('id', barberId)
        .maybeSingle();
    if (res == null) return null;
    return BarberModel.fromMap(res);
  }

  // ─── QUEUE ────────────────────────────────────────────────

  /// Get queue entries for a specific barber ordered by join position (chronological).
  Future<List<QueueEntryModel>> getQueueForBarber(String barberId) async {
    final res = await _client
        .from('queues')
        .select('*, users(name, phone)')
        .eq('barber_id', barberId)
        .order('position', ascending: true); // global position = join order

    return (res as List).map((r) => QueueEntryModel.fromMap(r)).toList();
  }

  /// Get all queue entries across all barbers (staff) for a shop.
  Future<List<QueueEntryModel>> getShopQueue(String shopId) async {
    final barbersRes = await _client
        .from('barbers')
        .select('id')
        .eq('shop_id', shopId);

    final barberIds = (barbersRes as List).map((b) => b['id'] as String).toList();
    if (barberIds.isEmpty) return [];

    final res = await _client
        .from('queues')
        .select('*, users(name, phone)')
        .inFilter('barber_id', barberIds)
        .order('queue_type', ascending: false)
        .order('position', ascending: true);

    return (res as List).map((r) => QueueEntryModel.fromMap(r)).toList();
  }

  /// Get the user's current active queue entry with barber + shop info.
  Future<QueueEntryModel?> getMyActiveQueueEntry(String userId) async {
    final res = await _client
        .from('queues')
        .select('*, barbers(name, image_url, shop_id, shops(name, prepayment_enabled))')
        .eq('user_id', userId)
        .maybeSingle();
    if (res == null) return null;
    return QueueEntryModel.fromMap(res);
  }

  /// Check if user is already in any queue.
  Future<bool> isUserInQueue(String userId) async {
    final res = await _client
        .from('queues')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();

    return res != null;
  }

  /// Get user's current position in a barber's queue (null if not in queue).
  Future<int?> getUserPositionInBarber(String userId, String barberId) async {
    final res = await _client
        .from('queues')
        .select('position')
        .eq('user_id', userId)
        .eq('barber_id', barberId)
        .maybeSingle();

    return res?['position'] as int?;
  }

  /// Get user's queue entry (position + queue_type) for a specific barber.
  Future<Map<String, dynamic>?> getUserQueueEntry(
      String userId, String barberId) async {
    final res = await _client
        .from('queues')
        .select('position, queue_type')
        .eq('user_id', userId)
        .eq('barber_id', barberId)
        .maybeSingle();
    return res; // has keys 'position' (int) and 'queue_type' (String), or null
  }

  /// Join a queue with specified type (vip or normal).
  /// [bookingCode] is required when the barber has booking_code_enabled = true.
  /// [selectedServices] and [servicesTotal] capture menu selections made at booking time.
  Future<void> joinQueue(String barberId, String userId,
      {String queueType = 'normal',
      String? bookingCode,
      List<Map<String, dynamic>>? selectedServices,
      double? servicesTotal}) async {
    // Check if already in any queue
    final inQueue = await isUserInQueue(userId);
    if (inQueue) {
      throw Exception('أنت بالفعل في طابور');
    }

    // Check barber status, lock state, and booking code in a single query
    final barberRes = await _client
        .from('barbers')
        .select('is_closed, vip_locked, normal_locked, booking_code_enabled, booking_code')
        .eq('id', barberId)
        .single();

    if (barberRes['is_closed'] == true) throw Exception('الحلاق غير متاح حالياً');
    if (queueType == 'vip' && (barberRes['vip_locked'] ?? false)) {
      throw Exception('طابور VIP مغلق حالياً');
    }
    if (queueType == 'normal' && (barberRes['normal_locked'] ?? false)) {
      throw Exception('الطابور العادي مغلق حالياً');
    }

    // Validate booking code when required
    if (barberRes['booking_code_enabled'] == true) {
      final requiredCode = (barberRes['booking_code'] as String?)?.trim().toUpperCase();
      if (requiredCode != null && requiredCode.isNotEmpty) {
        final enteredCode = bookingCode?.trim().toUpperCase() ?? '';
        if (enteredCode != requiredCode) {
          throw Exception('رمز الحجز غير صحيح');
        }
      }
    }

    // Get next global position (shared across ALL queue types for this barber)
    final posRes = await _client
        .from('queues')
        .select('position')
        .eq('barber_id', barberId)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();

    final nextPosition =
        posRes != null ? (posRes['position'] as int) + 1 : 1;

    await _client.from('queues').insert({
      'barber_id':          barberId,
      'user_id':            userId,
      'position':           nextPosition,
      'queue_type':         queueType,
      if (selectedServices != null && selectedServices.isNotEmpty)
        'selected_services': selectedServices,
      if (servicesTotal != null) 'services_total': servicesTotal,
    });
  }

  /// Remove the next customer in queue (by global join position — no type priority).
  Future<void> removeNextInQueue(String barberId) async {
    final first = await _client
        .from('queues')
        .select('id, barber_id, user_id, position, queue_type')
        .eq('barber_id', barberId)
        .order('position', ascending: true)
        .limit(1)
        .maybeSingle();

    if (first != null) {
      await _saveDeletedEntry(first);
      await _client.from('queues').delete().eq('id', first['id']);
      await _reorderAllQueue(barberId);
    }
  }

  /// Remove a specific user from queue (barber action, saves for undo).
  Future<void> removeFromQueue(String queueId, String barberId) async {
    // Fetch entry before deleting for undo
    final entry = await _client
        .from('queues')
        .select('id, barber_id, user_id, position, queue_type')
        .eq('id', queueId)
        .maybeSingle();

    if (entry != null) {
      await _saveDeletedEntry(entry);
      await _client.from('queues').delete().eq('id', queueId);
      await _reorderAllQueue(barberId);
    }
  }

  /// Customer leaves the queue voluntarily.
  Future<void> leaveQueue(String userId) async {
    final entry = await _client
        .from('queues')
        .select('id, barber_id, queue_type')
        .eq('user_id', userId)
        .maybeSingle();

    if (entry == null) return;

    await _client.from('queues').delete().eq('id', entry['id']);
    await _reorderAllQueue(entry['barber_id'] as String);
  }

  /// Save a deleted entry for undo.
  Future<void> _saveDeletedEntry(Map<String, dynamic> entry) async {
    await _client.from('deleted_queue_entries').insert({
      'original_id': entry['id'],
      'barber_id': entry['barber_id'],
      'user_id': entry['user_id'],
      'position': entry['position'],
      'queue_type': entry['queue_type'] ?? 'normal',
    });
  }

  /// Undo the last deleted queue entry for a shop.
  Future<bool> undoLastDelete(String shopId) async {
    // Get barber IDs for this shop
    final barbersRes = await _client
        .from('barbers')
        .select('id')
        .eq('shop_id', shopId);
    final barberIds = (barbersRes as List).map((b) => b['id'] as String).toList();
    if (barberIds.isEmpty) return false;

    // Get the most recent deleted entry for any of this shop's barbers
    final lastDeleted = await _client
        .from('deleted_queue_entries')
        .select('*')
        .inFilter('barber_id', barberIds)
        .order('deleted_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (lastDeleted == null) return false;

    // Check if user is already in a queue
    final alreadyIn = await isUserInQueue(lastDeleted['user_id']);
    if (alreadyIn) return false;

    final originalPos = lastDeleted['position'] as int;
    final barberId = lastDeleted['barber_id'] as String;
    final queueType = lastDeleted['queue_type'] as String? ?? 'normal';

    // Shift all entries at or after the original position down by one (globally)
    final toShift = await _client
        .from('queues')
        .select('id, position')
        .eq('barber_id', barberId)
        .gte('position', originalPos)
        .order('position', ascending: false);

    for (final row in (toShift as List)) {
      await _client
          .from('queues')
          .update({'position': (row['position'] as int) + 1})
          .eq('id', row['id'] as String);
    }

    // Re-insert at original position
    await _client.from('queues').insert({
      'barber_id': barberId,
      'user_id': lastDeleted['user_id'],
      'position': originalPos,
      'queue_type': queueType,
    });

    // Remove from undo history
    await _client.from('deleted_queue_entries').delete().eq('id', lastDeleted['id']);
    return true;
  }

  /// Clear entire queue for a barber (staff member).
  Future<void> clearQueue(String barberId) async {
    await _client.from('queues').delete().eq('barber_id', barberId);
  }

  /// Clear all queues for a shop.
  Future<void> clearShopQueues(String shopId) async {
    final barbersRes = await _client
        .from('barbers')
        .select('id')
        .eq('shop_id', shopId);

    final barberIds = (barbersRes as List).map((b) => b['id'] as String).toList();
    if (barberIds.isEmpty) return;

    for (final bid in barberIds) {
      await _client.from('queues').delete().eq('barber_id', bid);
    }
  }

  /// Reorder all queue positions globally after a removal (across all types).
  Future<void> _reorderAllQueue(String barberId) async {
    final entries = await _client
        .from('queues')
        .select('id')
        .eq('barber_id', barberId)
        .order('position', ascending: true);

    int pos = 1;
    for (final entry in entries) {
      await _client
          .from('queues')
          .update({'position': pos})
          .eq('id', entry['id']);
      pos++;
    }
  }

  // ─── BARBER: STAFF CONTROLS ───────────────────────────────

  /// Toggle a single barber (staff) open/closed.
  Future<void> toggleBarberClosed(String barberId, bool isClosed) async {
    await _client
        .from('barbers')
        .update({'is_closed': isClosed})
        .eq('id', barberId);
  }

  /// Toggle VIP queue locked state for a barber (staff).
  Future<void> toggleBarberVipLocked(String barberId, bool isLocked) async {
    await _client.from('barbers').update({'vip_locked': isLocked}).eq('id', barberId);
  }

  /// Toggle Normal queue locked state for a barber (staff).
  Future<void> toggleBarberNormalLocked(String barberId, bool isLocked) async {
    await _client.from('barbers').update({'normal_locked': isLocked}).eq('id', barberId);
  }

  /// Close or open all barbers (staff) in a shop.
  Future<void> toggleShopClosed(String shopId, bool close) async {
    final barbersRes = await _client
        .from('barbers')
        .select('id')
        .eq('shop_id', shopId);
    final barberIds = (barbersRes as List).map((b) => b['id'] as String).toList();
    for (final bid in barberIds) {
      await _client.from('barbers').update({'is_closed': close}).eq('id', bid);
    }
  }

  /// Check if the entire shop is closed (all barbers/staff closed).
  Future<bool> isShopClosed(String shopId) async {
    final res = await _client
        .from('barbers')
        .select('is_closed')
        .eq('shop_id', shopId);
    if ((res as List).isEmpty) return false;
    return res.every((b) => b['is_closed'] == true);
  }

  /// Add a customer to a barber's queue by phone number (existing account).
  Future<void> addCustomerToQueue(String barberId, String phone,
      {String queueType = 'normal',
      List<Map<String, dynamic>>? selectedServices,
      double? servicesTotal}) async {
    final userRes = await _client
        .from('users')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();

    if (userRes == null) {
      throw Exception('لم يتم العثور على عميل بهذا الرقم');
    }

    final userId = userRes['id'] as String;

    final inQueue = await isUserInQueue(userId);
    if (inQueue) {
      throw Exception('العميل موجود بالفعل في طابور');
    }

    final posRes = await _client
        .from('queues')
        .select('position')
        .eq('barber_id', barberId)
        .eq('queue_type', queueType)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextPos = posRes != null ? (posRes['position'] as int) + 1 : 1;

    await _client.from('queues').insert({
      'barber_id':  barberId,
      'user_id':    userId,
      'position':   nextPos,
      'queue_type': queueType,
      if (selectedServices != null && selectedServices.isNotEmpty)
        'selected_services': selectedServices,
      if (servicesTotal != null) 'services_total': servicesTotal,
    });
  }

  /// Add a guest (no account) to a barber's queue by name + phone.
  /// Creates a temporary customer account then joins the queue.
  Future<void> addGuestToQueue({
    required String barberId,
    required String name,
    required String phone,
    required String shopId,
    String queueType = 'normal',
    List<Map<String, dynamic>>? selectedServices,
    double? servicesTotal,
  }) async {
    // Check if phone already exists
    final existing = await _client
        .from('users')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();

    String userId;

    if (existing != null) {
      userId = existing['id'] as String;
      // Check if already in a queue
      final inQueue = await isUserInQueue(userId);
      if (inQueue) {
        throw Exception('هذا الرقم موجود بالفعل في طابور');
      }
    } else {
      // Create a guest account (no password needed for guest).
      // NOTE: barber_id on users now references barbers (staff), not shops —
      // so we intentionally omit it for guests.
      final res = await _client
          .from('users')
          .insert({
            'name': name,
            'phone': phone,
            'password': 'guest_${DateTime.now().millisecondsSinceEpoch}',
            'role': 'customer',
          })
          .select()
          .single();
      userId = res['id'] as String;
    }

    // FIX (Bug 1): global position across all queue types — same fix as joinQueue
    // and approvePayment so every entry path respects chronological order.
    final posRes = await _client
        .from('queues')
        .select('position')
        .eq('barber_id', barberId)
        // removed: .eq('queue_type', queueType)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextPos = posRes != null ? (posRes['position'] as int) + 1 : 1;

    await _client.from('queues').insert({
      'barber_id':  barberId,
      'user_id':    userId,
      'position':   nextPos,
      'queue_type': queueType,
      if (selectedServices != null && selectedServices.isNotEmpty)
        'selected_services': selectedServices,
      if (servicesTotal != null) 'services_total': servicesTotal,
    });
  }

  /// Auto-remove: tries VIP first, then Normal.
  /// Returns true if someone was removed (chronologically first, no type priority).
  Future<bool> autoRemoveFirst(String barberId) async {
    final first = await _client
        .from('queues')
        .select('id, barber_id, user_id, position, queue_type')
        .eq('barber_id', barberId)
        .order('position', ascending: true)
        .limit(1)
        .maybeSingle();

    if (first != null) {
      await _saveDeletedEntry(first);
      await _client.from('queues').delete().eq('id', first['id']);
      await _reorderAllQueue(barberId);
      return true;
    }
    return false;
  }

  // ─── REALTIME ─────────────────────────────────────────────

  /// Subscribe to queue changes.
  RealtimeChannel subscribeToQueues(void Function() onChanged) {
    return _client.channel('queue-changes').onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'queues',
      callback: (payload) {
        onChanged();
      },
    ).subscribe();
  }

  /// Unsubscribe from a channel.
  void unsubscribe(RealtimeChannel channel) {
    _client.removeChannel(channel);
  }

  // ─── ADMIN: SHOP MANAGEMENT ───────────────────────────────

  /// Get all shops (for admin panel).
  Future<List<ShopModel>> getAllShops() async {
    final res = await _client
        .from('shops')
        .select()
        .order('created_at', ascending: false);
    return (res as List).map((r) => ShopModel.fromMap(r)).toList();
  }

  /// Get only active shops.
  Future<List<ShopModel>> getActiveShops() async {
    final res = await _client
        .from('shops')
        .select()
        .eq('is_active', true)
        .order('name');
    return (res as List).map((r) => ShopModel.fromMap(r)).toList();
  }

  /// Get a single shop by ID.
  Future<ShopModel?> getShopById(String shopId) async {
    final res = await _client
        .from('shops')
        .select()
        .eq('id', shopId)
        .maybeSingle();
    if (res == null) return null;
    return ShopModel.fromMap(res);
  }

  /// Get all shops with their barbers (staff).
  Future<List<ShopWithBarbers>> getAllShopsWithBarbers() async {
    final shops = await getAllShops();
    final result = <ShopWithBarbers>[];
    for (final shop in shops) {
      final barbers = await getBarbers(shop.id);
      result.add(ShopWithBarbers(shop: shop, barbers: barbers));
    }
    return result;
  }

  /// Create a new shop / salon.
  Future<ShopModel> createShop({
    required String name,
    required String code,
    String? imageUrl,
    String? phone,
    String? address,
    String? mapsUrl,
  }) async {
    // Ensure code uniqueness
    final existing = await _client
        .from('shops')
        .select('id')
        .eq('code', code.toUpperCase())
        .maybeSingle();
    if (existing != null) {
      throw Exception('رمز الصالون مستخدم بالفعل');
    }

    final res = await _client
        .from('shops')
        .insert({
          'name': name,
          'code': code.toUpperCase(),
          'image_url': imageUrl,
          'phone': phone,
          'address': address,
          'maps_url': mapsUrl,
          'is_active': true,
        })
        .select()
        .single();
    return ShopModel.fromMap(res);
  }

  /// Update shop details.
  Future<void> updateShop({
    required String shopId,
    required String name,
    String? imageUrl,
    String? phone,
    String? address,
    String? mapsUrl,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{
      'name': name,
      'maps_url': mapsUrl, // always written so it can be cleared
    };
    if (imageUrl != null) updates['image_url'] = imageUrl;
    if (phone != null) updates['phone'] = phone;
    if (address != null) updates['address'] = address;
    if (isActive != null) updates['is_active'] = isActive;

    await _client.from('shops').update(updates).eq('id', shopId);
  }

  /// Delete a shop and all related data.
  Future<void> deleteShop(String shopId) async {
    await _client.from('shops').delete().eq('id', shopId);
  }

  /// Toggle shop active state.
  Future<void> toggleShopActive(String shopId, bool isActive) async {
    await _client
        .from('shops')
        .update({'is_active': isActive})
        .eq('id', shopId);
  }

  /// Toggle VIP queue privilege for a shop.
  Future<void> toggleShopVip(String shopId, bool enabled) async {
    await _client
        .from('shops')
        .update({'vip_enabled': enabled})
        .eq('id', shopId);
  }

  /// Toggle prepayment for a shop.
  Future<void> toggleShopPrepayment(String shopId, bool enabled) async {
    await _client
        .from('shops')
        .update({'prepayment_enabled': enabled})
        .eq('id', shopId);
  }

  // ─── ADMIN: BARBER (STAFF) MANAGEMENT ────────────────────

  /// Add a barber (staff member) to a shop.
  Future<void> addBarber(String shopId, String name, {String? imageUrl, String? location}) async {
    await _client.from('barbers').insert({
      'shop_id': shopId,
      'name': name,
      'image_url': imageUrl,
      'location': location,
    });
  }

  /// Update a barber's (staff) name, image, and location.
  Future<void> updateBarber(String barberId, {required String name, String? imageUrl, String? location}) async {
    await _client.from('barbers').update({
      'name': name,
      'image_url': imageUrl,
      'location': location,
    }).eq('id', barberId);
  }

  /// Delete a barber (staff member).
  Future<void> deleteBarber(String barberId) async {
    await _client.from('barbers').delete().eq('id', barberId);
  }

  /// Returns the Set of barber IDs (for a given shop) that already have a
  /// linked login account in the users table (role = 'barber').
  Future<Set<String>> getBarberLinkedUserIds(String shopId) async {
    try {
      final barbers = await _client
          .from('barbers')
          .select('id')
          .eq('shop_id', shopId);
      final ids = (barbers as List).map((b) => b['id'] as String).toList();
      if (ids.isEmpty) return {};
      final users = await _client
          .from('users')
          .select('barber_id')
          .eq('role', 'barber')
          .inFilter('barber_id', ids);
      return (users as List)
          .map((u) => u['barber_id'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  /// Create a login account (users record) for an *existing* barber staff member.
  /// Throws if the phone is taken or the barber already has an account.
  Future<void> createUserForBarber({
    required String barberId,
    required String name,
    required String phone,
    required String password,
  }) async {
    final phoneExists = await _client
        .from('users')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();
    if (phoneExists != null) throw Exception('رقم الهاتف مسجل بالفعل');

    final alreadyLinked = await _client
        .from('users')
        .select('id')
        .eq('barber_id', barberId)
        .eq('role', 'barber')
        .maybeSingle();
    if (alreadyLinked != null) throw Exception('هذا الحلاق لديه حساب بالفعل');

    await _client.from('users').insert({
      'name': name,
      'phone': phone,
      'password': password,
      'role': 'barber',
      'barber_id': barberId,
    });
  }

  /// Create a barber staff member AND their user account in one operation.
  Future<BarberModel> createBarberWithUser({
    required String shopId,
    required String name,
    required String phone,
    required String password,
    String? imageUrl,
  }) async {
    // Check if phone already exists
    final existing = await _client
        .from('users')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();
    if (existing != null) {
      throw Exception('رقم الهاتف مسجل بالفعل');
    }

    // 1. Insert the barber (staff) record
    final barberRes = await _client
        .from('barbers')
        .insert({
          'shop_id': shopId,
          'name': name,
          'image_url': imageUrl,
          'phone': phone,
          'password': password,
        })
        .select()
        .single();

    final barber = BarberModel.fromMap(barberRes);

    // 2. Create the users record for login
    await _client.from('users').insert({
      'name': name,
      'phone': phone,
      'password': password,
      'role': 'barber',
      'barber_id': barber.id,
    });

    return barber;
  }

  // ─── BARBER FAVORITES (saved list) ──────────────────────

  /// Returns a Set of barber IDs the user has saved to their "My Barber" list.
  Future<Set<String>> getFavoriteBarberIds(String userId) async {
    try {
      final res = await _client
          .from('barber_favorites')
          .select('barber_id')
          .eq('user_id', userId);
      return Set<String>.from((res as List).map<String>((r) => r['barber_id'] as String));
    } catch (_) {
      return {};
    }
  }

  /// Returns full BarberModel list for the user's saved barbers (newest first).
  Future<List<BarberModel>> getUserFavoriteBarbers(String userId) async {
    try {
      List<dynamic> res;
      bool hasLikes = true;
      try {
        res = await _client
            .from('barber_favorites')
            .select('barbers(*, shops(name), barber_likes(count), queues(count))')
            .eq('user_id', userId)
            .order('created_at', ascending: false);
      } catch (_) {
        hasLikes = false;
        res = await _client
            .from('barber_favorites')
            .select('barbers(*, shops(name), queues(count))')
            .eq('user_id', userId)
            .order('created_at', ascending: false);
      }
      return res.map<BarberModel>((r) {
        final m        = r['barbers'] as Map<String, dynamic>;
        final shop     = m['shops']        as Map<String, dynamic>?;
        final likeList = hasLikes ? (m['barber_likes'] as List?) : null;
        final qList    = m['queues']       as List?;
        final rawLike  = (likeList != null && likeList.isNotEmpty) ? likeList[0]['count'] : 0;
        final rawQueue = (qList    != null && qList.isNotEmpty)    ? qList[0]['count']    : 0;
        return BarberModel(
          id:             m['id'],
          shopId:         m['shop_id'],
          name:           m['name'],
          imageUrl:       m['image_url'],
          isClosed:       m['is_closed']  ?? false,
          isVipLocked:    m['vip_locked'] ?? false,
          isNormalLocked: m['normal_locked'] ?? false,
          queueLength:   rawQueue is int ? rawQueue : int.tryParse('$rawQueue') ?? 0,
          likeCount:     rawLike  is int ? rawLike  : int.tryParse('$rawLike')  ?? 0,
          shopName:      shop?['name'],
          paymentNumber: m['payment_number'],
          walletNumbers: Map<String, String>.from(
            ((m['wallet_numbers'] as Map<String, dynamic>?) ?? {})
                .map((k, v) => MapEntry(k, v?.toString() ?? '')),
          ),
          location:      m['location'],
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Add or remove a barber from the user's saved list.
  Future<void> toggleFavoriteBarber(String userId, String barberId) async {
    try {
      final existing = await _client
          .from('barber_favorites')
          .select('id')
          .eq('user_id', userId)
          .eq('barber_id', barberId)
          .maybeSingle();
      if (existing != null) {
        await _client.from('barber_favorites').delete()
            .eq('user_id', userId).eq('barber_id', barberId);
      } else {
        await _client.from('barber_favorites').insert({
          'user_id': userId,
          'barber_id': barberId,
        });
      }
    } catch (e) {
      throw Exception('تعذّر تحديث المفضلة: $e');
    }
  }

  // ─── BARBER LIKES (customer voting) ──────────────────────

  /// Returns the barber_id the user currently votes for (null = no vote).
  Future<String?> getUserLikedBarberId(String userId) async {
    try {
      final res = await _client
          .from('barber_likes')
          .select('barber_id')
          .eq('user_id', userId)
          .maybeSingle();
      return res?['barber_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Toggle a like on [barberId] for [userId].
  /// A user can only have one active vote at a time — liking a new barber
  /// automatically removes the previous vote.
  /// Returns the newly liked barber_id, or null if the vote was removed.
  Future<String?> toggleBarberLike(String userId, String barberId) async {
    final current = await _client
        .from('barber_likes')
        .select('barber_id')
        .eq('user_id', userId)
        .maybeSingle();

    // Remove any existing vote first (works whether same or different barber)
    await _client.from('barber_likes').delete().eq('user_id', userId);

    if (current != null && current['barber_id'] == barberId) {
      // User tapped the same barber → unlike
      return null;
    }

    // Like the new barber
    await _client.from('barber_likes').insert({
      'user_id': userId,
      'barber_id': barberId,
    });
    return barberId;
  }

  /// Fetch ALL barbers across every shop with like counts, queue counts,
  /// and the shop name. Result is sorted by most-liked first.
  /// Falls back gracefully if the barber_likes table does not exist yet.
  Future<List<BarberModel>> getAllBarbersRanked() async {
    List<dynamic> res;
    bool hasLikes = true;

    try {
      res = await _client
          .from('barbers')
          .select('*, shops(name), barber_likes(count), queues(count)');
    } catch (_) {
      // barber_likes table missing — fall back to no-likes query
      hasLikes = false;
      res = await _client
          .from('barbers')
          .select('*, shops(name), queues(count)');
    }

    final barbers = res.map((row) {
      final shop      = row['shops']        as Map<String, dynamic>?;
      final likeList  = hasLikes ? (row['barber_likes'] as List?) : null;
      final queueList = row['queues']       as List?;
      final rawLike  = (likeList  != null && likeList.isNotEmpty)  ? likeList[0]['count']  : 0;
      final rawQueue = (queueList != null && queueList.isNotEmpty) ? queueList[0]['count'] : 0;

      return BarberModel(
        id:                 row['id'],
        shopId:             row['shop_id'],
        name:               row['name'],
        imageUrl:           row['image_url'],
        isClosed:           row['is_closed']           ?? false,
        isVipLocked:        row['vip_locked']          ?? false,
        isNormalLocked:     row['normal_locked']       ?? false,
        bookingCodeEnabled: row['booking_code_enabled'] ?? false,
        queueLength:   rawQueue is int ? rawQueue : int.tryParse('$rawQueue') ?? 0,
        likeCount:     rawLike  is int ? rawLike  : int.tryParse('$rawLike')  ?? 0,
        shopName:      shop?['name'],
        paymentNumber: row['payment_number'],
        walletNumbers: Map<String, String>.from(
          ((row['wallet_numbers'] as Map<String, dynamic>?) ?? {})
              .map((k, v) => MapEntry(k, v?.toString() ?? '')),
        ),
        location:      row['location'],
      );
    }).toList();

    barbers.sort((a, b) => b.likeCount.compareTo(a.likeCount));
    return barbers;
  }

  /// Fetch barbers for a single shop with like counts and queue counts.
  /// Falls back gracefully if the barber_likes table does not exist yet.
  Future<List<BarberModel>> getBarbersWithLikes(String shopId) async {
    List<dynamic> res;
    bool hasLikes = true;

    try {
      res = await _client
          .from('barbers')
          .select('*, barber_likes(count), queues(count)')
          .eq('shop_id', shopId)
          .order('name');
    } catch (_) {
      // barber_likes table missing — fall back to basic barbers query
      hasLikes = false;
      res = await _client
          .from('barbers')
          .select('*, queues(count)')
          .eq('shop_id', shopId)
          .order('name');
    }

    return res.map((row) {
      final likeList  = hasLikes ? (row['barber_likes'] as List?) : null;
      final queueList = row['queues'] as List?;
      final rawLike  = (likeList  != null && likeList.isNotEmpty)  ? likeList[0]['count']  : 0;
      final rawQueue = (queueList != null && queueList.isNotEmpty) ? queueList[0]['count'] : 0;

      return BarberModel(
        id:                 row['id'],
        shopId:             row['shop_id'],
        name:               row['name'],
        imageUrl:           row['image_url'],
        isClosed:           row['is_closed']           ?? false,
        isVipLocked:        row['vip_locked']          ?? false,
        isNormalLocked:     row['normal_locked']       ?? false,
        bookingCodeEnabled: row['booking_code_enabled'] ?? false,
        queueLength:   rawQueue is int ? rawQueue : int.tryParse('$rawQueue') ?? 0,
        likeCount:     rawLike  is int ? rawLike  : int.tryParse('$rawLike')  ?? 0,
        paymentNumber: row['payment_number'],
        walletNumbers: Map<String, String>.from(
          ((row['wallet_numbers'] as Map<String, dynamic>?) ?? {})
              .map((k, v) => MapEntry(k, v?.toString() ?? '')),
        ),
        location:      row['location'],
      );
    }).toList();
  }

  // ─── BOOKING CODE ──────────────────────────────────────────

  /// Fetch the booking-code settings for a barber (admin only).
  /// Returns {'enabled': bool, 'code': String?}
  Future<Map<String, dynamic>> getBarberBookingCodeSettings(String barberId) async {
    final res = await _client
        .from('barbers')
        .select('booking_code_enabled, booking_code')
        .eq('id', barberId)
        .single();
    return {
      'enabled': res['booking_code_enabled'] as bool? ?? false,
      'code':    res['booking_code']         as String?,
    };
  }

  /// Enable or disable the booking-code requirement for a barber (admin only).
  /// Pass [enabled]=true and a non-empty [code] to activate.
  /// Pass [enabled]=false to deactivate (code is cleared in DB).
  Future<void> setBarberBookingCode(
    String barberId, {
    required bool enabled,
    String? code,
  }) async {
    await _client.from('barbers').update({
      'booking_code_enabled': enabled,
      'booking_code': enabled ? (code?.trim().toUpperCase()) : null,
    }).eq('id', barberId);
  }

  // ─── ADMIN: USER MANAGEMENT ───────────────────────────────

  /// Get all users.
  Future<List<UserModel>> getAllUsers() async {
    final res = await _client
        .from('users')
        .select()
        .order('created_at', ascending: false);
    return (res as List).map((r) => UserModel.fromMap(r)).toList();
  }

  /// Create a barber user account linked to a barber (staff) record.
  Future<void> createBarberUser({
    required String name,
    required String phone,
    required String password,
    required String barberId,   // references barbers.id (individual staff)
  }) async {
    final existing = await _client
        .from('users')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();
    if (existing != null) {
      throw Exception('رقم الهاتف مسجل بالفعل');
    }

    await _client.from('users').insert({
      'name': name,
      'phone': phone,
      'password': password,
      'role': 'barber',
      'barber_id': barberId,
    });
  }

  /// Delete a user.
  Future<void> deleteUser(String userId) async {
    await _client.from('users').delete().eq('id', userId);
  }

  // ─── ADMIN USER MANAGEMENT ────────────────────────────────────

  Future<List<UserModel>> getAllCustomers() async {
    final res = await _client
        .from('users')
        .select()
        .eq('role', 'customer')
        .order('name', ascending: true);
    return (res as List).map((r) => UserModel.fromMap(r)).toList();
  }

  Future<void> blockUser(String userId) async {
    await _client.from('users').update({'is_blocked': true}).eq('id', userId);
  }

  Future<void> unblockUser(String userId) async {
    await _client.from('users').update({'is_blocked': false}).eq('id', userId);
  }

  // ─── PRODUCTS ─────────────────────────────────────────────

  Future<List<ProductModel>> getProducts(String shopId) async {
    final res = await _client
        .from('products')
        .select()
        .eq('shop_id', shopId)
        .order('created_at', ascending: false);
    return (res as List).map((r) => ProductModel.fromMap(r)).toList();
  }

  Future<void> addProduct({
    required String shopId,
    required String name,
    String? description,
    double? price,
    String? imageUrl,
  }) async {
    await _client.from('products').insert({
      'shop_id': shopId,
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
    });
  }

  Future<void> deleteProduct(String productId) async {
    await _client.from('products').delete().eq('id', productId);
  }

  // ─── PREPAYMENT ──────────────────────────────────────────

  /// Returns the customer's pending payment request for a specific barber, or null.
  Future<PaymentRequestModel?> getUserPendingPayment(
      String userId, String barberId) async {
    final res = await _client
        .from('payment_requests')
        .select('*, users(name, phone), barbers(name), shops(name)')
        .eq('user_id', userId)
        .eq('barber_id', barberId)
        .eq('status', 'pending')
        .maybeSingle();
    if (res == null) return null;
    return PaymentRequestModel.fromMap(res);
  }

  Future<void> createPaymentRequest({
    required String userId,
    required String barberId,
    required String shopId,
    required String walletType,
    required String photoUrl,
    double? amount,
    String queueType = 'normal',
    List<Map<String, dynamic>>? selectedServices,
  }) async {
    await _client.from('payment_requests').insert({
      'user_id':           userId,
      'barber_id':         barberId,
      'shop_id':           shopId,
      'wallet_type':       walletType,
      'photo_url':         photoUrl,
      'amount':            amount,
      'queue_type':        queueType,
      'status':            'pending',
      if (selectedServices != null && selectedServices.isNotEmpty)
        'selected_services': selectedServices,
    });
  }

  Future<List<PaymentRequestModel>> getPendingPayments() async {
    final res = await _client
        .from('payment_requests')
        .select('*, users(name, phone), barbers(name), shops(name)')
        .eq('status', 'pending')
        .order('created_at', ascending: true);
    return (res as List).map((r) => PaymentRequestModel.fromMap(r)).toList();
  }

  /// Approve a payment: add the customer to the barber's queue, then mark approved.
  ///
  /// FIX (Bug 1): position query is now GLOBAL — no longer filtered by queue_type.
  /// Previously `.eq('queue_type', payment.queueType)` meant a VIP approval always
  /// received position 1 (first in the VIP sub-count) even when Normal customers
  /// had already joined the queue before them.
  Future<void> approvePayment(PaymentRequestModel payment) async {
    final posRes = await _client
        .from('queues')
        .select('position')
        .eq('barber_id', payment.barberId)
        // removed: .eq('queue_type', payment.queueType)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextPos = posRes != null ? (posRes['position'] as int) + 1 : 1;

    // Calculate services total from selectedServices if not already stored
    double? svcsTotal;
    if (payment.selectedServices != null && payment.selectedServices!.isNotEmpty) {
      svcsTotal = payment.selectedServices!.fold<double>(
        0.0, (sum, s) => sum + ((s['price'] as num?)?.toDouble() ?? 0.0));
    }

    await _client.from('queues').insert({
      'barber_id':  payment.barberId,
      'user_id':    payment.userId,
      'position':   nextPos,
      'queue_type': payment.queueType,
      if (payment.selectedServices != null && payment.selectedServices!.isNotEmpty)
        'selected_services': payment.selectedServices,
      if (svcsTotal != null && svcsTotal > 0)
        'services_total': svcsTotal,
    });
    await _client
        .from('payment_requests')
        .update({'status': 'approved'})
        .eq('id', payment.id);
  }

  Future<void> rejectPayment(String paymentId) async {
    await _client
        .from('payment_requests')
        .update({'status': 'rejected'})
        .eq('id', paymentId);
  }

  Future<List<PaymentRequestModel>> getPendingPaymentsForBarber(String barberId) async {
    final res = await _client
        .from('payment_requests')
        .select('*, users(name, phone), barbers(name), shops(name)')
        .eq('barber_id', barberId)
        .eq('status', 'pending')
        .order('created_at', ascending: true);
    return (res as List).map((r) => PaymentRequestModel.fromMap(r)).toList();
  }

  Future<void> updateBarberPaymentNumber(String barberId, String number) async {
    await _client
        .from('barbers')
        .update({'payment_number': number})
        .eq('id', barberId);
  }

  Future<void> updateBarberWalletNumbers(
      String barberId, Map<String, String> numbers) async {
    await _client
        .from('barbers')
        .update({'wallet_numbers': numbers})
        .eq('id', barberId);
  }

  Future<void> updateBarberTiktokUrl(String barberId, String? url) async {
    await _client
        .from('barbers')
        .update({'tiktok_url': url?.isEmpty == true ? null : url})
        .eq('id', barberId);
  }

  RealtimeChannel subscribeToPaymentsForBarber(
      String barberId, void Function() onChanged) {
    return _client
        .channel('barber-payment-changes-$barberId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'payment_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'barber_id',
            value: barberId,
          ),
          callback: (payload) => onChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'payment_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'barber_id',
            value: barberId,
          ),
          callback: (payload) => onChanged(),
        )
        .subscribe();
  }

  RealtimeChannel subscribeToPayments(void Function() onChanged) {
    return _client
        .channel('payment-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'payment_requests',
          callback: (payload) => onChanged(),
        )
        .subscribe();
  }

  // ─── MANAGER: ALL QUEUES ─────────────────────────────────

  Future<List<QueueEntryModel>> getAllQueueEntries() async {
    final res = await _client
        .from('queues')
        .select('*, users(name, phone), barbers(name, shops(name, prepayment_enabled))')
        .order('barber_id')
        .order('queue_type')
        .order('position');
    return (res as List).map((r) => QueueEntryModel.fromMap(r)).toList();
  }

  Future<void> removeQueueEntry(String queueEntryId) async {
    await _client.from('queues').delete().eq('id', queueEntryId);
  }

  // ─── BARBER PORTFOLIO ─────────────────────────────────────────

  Future<List<String>> getBarberPortfolio(String barberId) async {
    try {
      final res = await _client
          .from('barber_portfolio')
          .select('photo_url')
          .eq('barber_id', barberId)
          .order('created_at', ascending: false);
      return (res as List).map((r) => r['photo_url'] as String).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addPortfolioPhoto(String barberId, String photoUrl) async {
    await _client.from('barber_portfolio').insert({
      'barber_id': barberId,
      'photo_url': photoUrl,
    });
  }

  Future<void> deletePortfolioPhoto(String barberId, String photoUrl) async {
    await _client
        .from('barber_portfolio')
        .delete()
        .eq('barber_id', barberId)
        .eq('photo_url', photoUrl);
  }

  // ─── ADMIN: STATISTICS ────────────────────────────────────

  /// Get total counts for the admin dashboard.
  Future<Map<String, int>> getAdminStats() async {
    final shops = await _client.from('shops').select('id');
    final users = await _client.from('users').select('id').eq('role', 'customer');
    final barbers = await _client.from('barbers').select('id');
    final queues = await _client.from('queues').select('id');

    return {
      'shops': (shops as List).length,
      'customers': (users as List).length,
      'barbers': (barbers as List).length,
      'inQueue': (queues as List).length,
    };
  }

  // ─── BARBER MENU ──────────────────────────────────────────────

  /// Fetch all menu items for a barber, ordered by sort_order then created_at.
  Future<List<BarberMenuItemModel>> getBarberMenu(String barberId) async {
    try {
      final res = await _client
          .from('barber_menu_items')
          .select()
          .eq('barber_id', barberId)
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);
      return (res as List).map((r) => BarberMenuItemModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Fetch only available menu items for a barber (shown to customers).
  Future<List<BarberMenuItemModel>> getAvailableBarberMenu(String barberId) async {
    try {
      final res = await _client
          .from('barber_menu_items')
          .select()
          .eq('barber_id', barberId)
          .eq('is_available', true)
          .order('sort_order', ascending: true)
          .order('created_at', ascending: true);
      return (res as List).map((r) => BarberMenuItemModel.fromMap(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Add a new menu item.
  Future<BarberMenuItemModel> addMenuItem({
    required String barberId,
    required String name,
    required double price,
    String queueType = 'both',
  }) async {
    final res = await _client
        .from('barber_menu_items')
        .insert({
          'barber_id':    barberId,
          'name':         name,
          'price':        price,
          'is_available': true,
          'sort_order':   0,
          'queue_type':   queueType,
        })
        .select()
        .single();
    return BarberMenuItemModel.fromMap(res);
  }

  /// Update an existing menu item (pass only fields you want to change).
  Future<void> updateMenuItem({
    required String id,
    String? name,
    double? price,
    bool? isAvailable,
    String? queueType,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (price != null) updates['price'] = price;
    if (isAvailable != null) updates['is_available'] = isAvailable;
    if (queueType != null) updates['queue_type'] = queueType;
    if (updates.isEmpty) return;
    await _client.from('barber_menu_items').update(updates).eq('id', id);
  }

  /// Delete a menu item.
  Future<void> deleteMenuItem(String id) async {
    await _client.from('barber_menu_items').delete().eq('id', id);
  }

  /// Update the queue type(s) for which the menu is shown to customers.
  /// [queueType] must be one of: 'both', 'vip', 'normal'
  Future<void> updateBarberMenuQueueType(
      String barberId, String queueType) async {
    await _client
        .from('barbers')
        .update({'menu_queue_type': queueType})
        .eq('id', barberId);
  }
}
