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

    await _client.storage.from(bucket).uploadBinary(
      fileName,
      bytes,
      fileOptions: const FileOptions(upsert: true, contentType: 'image/*'),
    );

    final publicUrl = _client.storage.from(bucket).getPublicUrl(fileName);
    return publicUrl;
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

  /// Register a new customer account.
  Future<UserModel> register({
    required String name,
    required String phone,
    required String password,
    required String barberCode,
  }) async {
    // Look up barber by code
    final barberRes = await _client
        .from('barbers')
        .select()
        .eq('code', barberCode)
        .maybeSingle();

    if (barberRes == null) {
      throw Exception('رمز الحلاق غير صحيح');
    }

    final barber = BarberModel.fromMap(barberRes);

    // Check if phone already exists
    final existing = await _client
        .from('users')
        .select('id')
        .eq('phone', phone)
        .maybeSingle();

    if (existing != null) {
      throw Exception('رقم الهاتف مسجل بالفعل');
    }

    // Insert user
    final res = await _client
        .from('users')
        .insert({
          'name': name,
          'phone': phone,
          'password': password,
          'role': 'customer',
          'barber_id': barber.id,
        })
        .select()
        .single();

    return UserModel.fromMap(res);
  }

  // ─── CHAIRS ───────────────────────────────────────────────

  /// Get all chairs for a barber, with current queue length.
  Future<List<ChairModel>> getChairs(String barberId) async {
    final res = await _client
        .from('chairs')
        .select('*, queues(count)')
        .eq('barber_id', barberId)
        .order('name');

    return (res as List).map((row) {
      final count =
          row['queues'] != null && (row['queues'] as List).isNotEmpty
              ? row['queues'][0]['count'] ?? 0
              : 0;
      return ChairModel(
        id: row['id'],
        barberId: row['barber_id'],
        name: row['name'],
        imageUrl: row['image_url'],
        isClosed: row['is_closed'] ?? false,
        queueLength: count is int ? count : int.tryParse('$count') ?? 0,
      );
    }).toList();
  }

  // ─── QUEUE ────────────────────────────────────────────────

  /// Get queue entries for a specific chair, ordered by position.
  Future<List<QueueEntryModel>> getQueueForChair(String chairId) async {
    final res = await _client
        .from('queues')
        .select('*, users(name, phone)')
        .eq('chair_id', chairId)
        .order('position', ascending: true);

    return (res as List).map((r) => QueueEntryModel.fromMap(r)).toList();
  }

  /// Get all queue entries across all chairs for a barber.
  Future<List<QueueEntryModel>> getBarberQueue(String barberId) async {
    final chairsRes = await _client
        .from('chairs')
        .select('id')
        .eq('barber_id', barberId);

    final chairIds = (chairsRes as List).map((c) => c['id'] as String).toList();
    if (chairIds.isEmpty) return [];

    final res = await _client
        .from('queues')
        .select('*, users(name, phone)')
        .inFilter('chair_id', chairIds)
        .order('position', ascending: true);

    return (res as List).map((r) => QueueEntryModel.fromMap(r)).toList();
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

  /// Get user's current position in a chair's queue (null if not in queue).
  Future<int?> getUserPositionInChair(
      String userId, String chairId) async {
    final res = await _client
        .from('queues')
        .select('position')
        .eq('user_id', userId)
        .eq('chair_id', chairId)
        .maybeSingle();

    return res?['position'] as int?;
  }

  /// Join a queue.
  Future<void> joinQueue(String chairId, String userId) async {
    // Check if already in any queue
    final inQueue = await isUserInQueue(userId);
    if (inQueue) {
      throw Exception('أنت بالفعل في طابور');
    }

    // Get next position
    final posRes = await _client
        .from('queues')
        .select('position')
        .eq('chair_id', chairId)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();

    final nextPosition =
        posRes != null ? (posRes['position'] as int) + 1 : 1;

    await _client.from('queues').insert({
      'chair_id': chairId,
      'user_id': userId,
      'position': nextPosition,
    });
  }

  /// Remove the first person in queue (for barber "Next" action).
  Future<void> removeFirstInQueue(String chairId) async {
    final first = await _client
        .from('queues')
        .select('id, chair_id, user_id, position')
        .eq('chair_id', chairId)
        .order('position', ascending: true)
        .limit(1)
        .maybeSingle();

    if (first != null) {
      // Save to undo history
      await _saveDeletedEntry(first);
      await _client.from('queues').delete().eq('id', first['id']);
      await _reorderQueue(chairId);
    }
  }

  /// Remove a specific user from queue (barber action, saves for undo).
  Future<void> removeFromQueue(String queueId, String chairId) async {
    // Fetch entry before deleting for undo
    final entry = await _client
        .from('queues')
        .select('id, chair_id, user_id, position')
        .eq('id', queueId)
        .maybeSingle();

    if (entry != null) {
      await _saveDeletedEntry(entry);
    }
    await _client.from('queues').delete().eq('id', queueId);
    await _reorderQueue(chairId);
  }

  /// Customer leaves the queue voluntarily.
  Future<void> leaveQueue(String userId) async {
    final entry = await _client
        .from('queues')
        .select('id, chair_id')
        .eq('user_id', userId)
        .maybeSingle();

    if (entry == null) return;

    await _client.from('queues').delete().eq('id', entry['id']);
    await _reorderQueue(entry['chair_id']);
  }

  /// Save a deleted entry for undo.
  Future<void> _saveDeletedEntry(Map<String, dynamic> entry) async {
    await _client.from('deleted_queue_entries').insert({
      'original_id': entry['id'],
      'chair_id': entry['chair_id'],
      'user_id': entry['user_id'],
      'position': entry['position'],
    });
  }

  /// Undo the last deleted queue entry.
  Future<bool> undoLastDelete(String barberId) async {
    // Get chair IDs for this barber
    final chairsRes = await _client
        .from('chairs')
        .select('id')
        .eq('barber_id', barberId);
    final chairIds = (chairsRes as List).map((c) => c['id'] as String).toList();
    if (chairIds.isEmpty) return false;

    // Get the most recent deleted entry for any of this barber's chairs
    final lastDeleted = await _client
        .from('deleted_queue_entries')
        .select('*')
        .inFilter('chair_id', chairIds)
        .order('deleted_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (lastDeleted == null) return false;

    // Check if user is already in a queue
    final alreadyIn = await isUserInQueue(lastDeleted['user_id']);
    if (alreadyIn) return false;

    // Get next position for the chair
    final posRes = await _client
        .from('queues')
        .select('position')
        .eq('chair_id', lastDeleted['chair_id'])
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextPos = posRes != null ? (posRes['position'] as int) + 1 : 1;

    // Re-insert the entry
    await _client.from('queues').insert({
      'chair_id': lastDeleted['chair_id'],
      'user_id': lastDeleted['user_id'],
      'position': nextPos,
    });

    // Remove from undo history
    await _client.from('deleted_queue_entries').delete().eq('id', lastDeleted['id']);
    return true;
  }

  /// Clear entire queue for a chair.
  Future<void> clearQueue(String chairId) async {
    await _client.from('queues').delete().eq('chair_id', chairId);
  }

  /// Clear all queues for a barber.
  Future<void> clearBarberQueues(String barberId) async {
    final chairsRes = await _client
        .from('chairs')
        .select('id')
        .eq('barber_id', barberId);

    final chairIds = (chairsRes as List).map((c) => c['id'] as String).toList();
    if (chairIds.isEmpty) return;

    for (final cid in chairIds) {
      await _client.from('queues').delete().eq('chair_id', cid);
    }
  }

  /// Reorder queue positions after a removal.
  Future<void> _reorderQueue(String chairId) async {
    final entries = await _client
        .from('queues')
        .select('id')
        .eq('chair_id', chairId)
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

  // ─── BARBER: CHAIR & SHOP CONTROLS ────────────────────────

  /// Toggle a single chair open/closed.
  Future<void> toggleChairClosed(String chairId, bool isClosed) async {
    await _client
        .from('chairs')
        .update({'is_closed': isClosed})
        .eq('id', chairId);
  }

  /// Close or open the entire shop (all chairs).
  Future<void> toggleShopClosed(String barberId, bool close) async {
    final chairsRes = await _client
        .from('chairs')
        .select('id')
        .eq('barber_id', barberId);
    final chairIds = (chairsRes as List).map((c) => c['id'] as String).toList();
    for (final cid in chairIds) {
      await _client.from('chairs').update({'is_closed': close}).eq('id', cid);
    }
  }

  /// Check if the entire shop is closed (all chairs closed).
  Future<bool> isShopClosed(String barberId) async {
    final res = await _client
        .from('chairs')
        .select('is_closed')
        .eq('barber_id', barberId);
    if ((res as List).isEmpty) return false;
    return res.every((c) => c['is_closed'] == true);
  }

  /// Add a customer to the queue by phone number (existing account).
  Future<void> addCustomerToQueue(String chairId, String phone) async {
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
        .eq('chair_id', chairId)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextPos = posRes != null ? (posRes['position'] as int) + 1 : 1;

    await _client.from('queues').insert({
      'chair_id': chairId,
      'user_id': userId,
      'position': nextPos,
    });
  }

  /// Add a guest (no account) to the queue by name + phone.
  /// Creates a temporary customer account then joins the queue.
  Future<void> addGuestToQueue({
    required String chairId,
    required String name,
    required String phone,
    required String barberId,
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
      // Create a guest account (no password needed for guest)
      final res = await _client
          .from('users')
          .insert({
            'name': name,
            'phone': phone,
            'password': 'guest_${DateTime.now().millisecondsSinceEpoch}',
            'role': 'customer',
            'barber_id': barberId,
          })
          .select()
          .single();
      userId = res['id'] as String;
    }

    // Get next position
    final posRes = await _client
        .from('queues')
        .select('position')
        .eq('chair_id', chairId)
        .order('position', ascending: false)
        .limit(1)
        .maybeSingle();
    final nextPos = posRes != null ? (posRes['position'] as int) + 1 : 1;

    await _client.from('queues').insert({
      'chair_id': chairId,
      'user_id': userId,
      'position': nextPos,
    });
  }

  /// Auto-remove the first person in queue for a chair (for timer feature).
  /// Returns true if someone was removed.
  Future<bool> autoRemoveFirst(String chairId) async {
    final first = await _client
        .from('queues')
        .select('id, chair_id, user_id, position')
        .eq('chair_id', chairId)
        .order('position', ascending: true)
        .limit(1)
        .maybeSingle();

    if (first == null) return false;

    await _saveDeletedEntry(first);
    await _client.from('queues').delete().eq('id', first['id']);
    await _reorderQueue(chairId);
    return true;
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

  // ─── ADMIN: BARBER MANAGEMENT ─────────────────────────────

  /// Get all barbers (for admin panel).
  Future<List<BarberModel>> getAllBarbers() async {
    final res = await _client
        .from('barbers')
        .select()
        .order('created_at', ascending: false);
    return (res as List).map((r) => BarberModel.fromMap(r)).toList();
  }

  /// Get a single barber by ID.
  Future<BarberModel?> getBarberById(String barberId) async {
    final res = await _client
        .from('barbers')
        .select()
        .eq('id', barberId)
        .maybeSingle();
    if (res == null) return null;
    return BarberModel.fromMap(res);
  }

  /// Create a new barber / salon.
  Future<BarberModel> createBarber({
    required String name,
    required String code,
    String? imageUrl,
    String? phone,
    String? address,
  }) async {
    // Ensure code uniqueness
    final existing = await _client
        .from('barbers')
        .select('id')
        .eq('code', code.toUpperCase())
        .maybeSingle();
    if (existing != null) {
      throw Exception('رمز الحلاق مستخدم بالفعل');
    }

    final res = await _client
        .from('barbers')
        .insert({
          'name': name,
          'code': code.toUpperCase(),
          'image_url': imageUrl,
          'phone': phone,
          'address': address,
          'is_active': true,
        })
        .select()
        .single();
    return BarberModel.fromMap(res);
  }

  /// Update barber details.
  Future<void> updateBarber({
    required String barberId,
    required String name,
    String? imageUrl,
    String? phone,
    String? address,
    bool? isActive,
  }) async {
    final updates = <String, dynamic>{'name': name};
    if (imageUrl != null) updates['image_url'] = imageUrl;
    if (phone != null) updates['phone'] = phone;
    if (address != null) updates['address'] = address;
    if (isActive != null) updates['is_active'] = isActive;

    await _client.from('barbers').update(updates).eq('id', barberId);
  }

  /// Delete a barber and all related data.
  Future<void> deleteBarber(String barberId) async {
    await _client.from('barbers').delete().eq('id', barberId);
  }

  /// Toggle barber active state.
  Future<void> toggleBarberActive(String barberId, bool isActive) async {
    await _client
        .from('barbers')
        .update({'is_active': isActive})
        .eq('id', barberId);
  }

  // ─── ADMIN: CHAIR MANAGEMENT ──────────────────────────────

  /// Add a chair to a barber.
  Future<void> addChair(String barberId, String name, {String? imageUrl}) async {
    await _client.from('chairs').insert({
      'barber_id': barberId,
      'name': name,
      'image_url': imageUrl,
    });
  }

  /// Update a chair's name and image.
  Future<void> updateChair(String chairId, {required String name, String? imageUrl}) async {
    await _client.from('chairs').update({
      'name': name,
      'image_url': imageUrl,
    }).eq('id', chairId);
  }

  /// Delete a chair.
  Future<void> deleteChair(String chairId) async {
    await _client.from('chairs').delete().eq('id', chairId);
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

  /// Create a barber user account linked to a barber.
  Future<void> createBarberUser({
    required String name,
    required String phone,
    required String password,
    required String barberId,
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

  // ─── PRODUCTS ─────────────────────────────────────────────

  Future<List<ProductModel>> getProducts(String barberId) async {
    final res = await _client
        .from('products')
        .select()
        .eq('barber_id', barberId)
        .order('created_at', ascending: false);
    return (res as List).map((r) => ProductModel.fromMap(r)).toList();
  }

  Future<void> addProduct({
    required String barberId,
    required String name,
    String? description,
    double? price,
    String? imageUrl,
  }) async {
    await _client.from('products').insert({
      'barber_id': barberId,
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
    });
  }

  Future<void> deleteProduct(String productId) async {
    await _client.from('products').delete().eq('id', productId);
  }

  // ─── ADMIN: STATISTICS ────────────────────────────────────

  /// Get total counts for the admin dashboard.
  Future<Map<String, int>> getAdminStats() async {
    final barbers = await _client.from('barbers').select('id');
    final users = await _client.from('users').select('id').eq('role', 'customer');
    final chairs = await _client.from('chairs').select('id');
    final queues = await _client.from('queues').select('id');

    return {
      'barbers': (barbers as List).length,
      'customers': (users as List).length,
      'chairs': (chairs as List).length,
      'inQueue': (queues as List).length,
    };
  }
}
