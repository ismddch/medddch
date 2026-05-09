// ─── Barber Model ──────────────────────────────────────────
class BarberModel {
  final String id;
  final String name;
  final String code;
  final String? imageUrl;
  final String? phone;
  final String? address;
  final bool isActive;
  final bool vipEnabled;

  BarberModel({
    required this.id,
    required this.name,
    required this.code,
    this.imageUrl,
    this.phone,
    this.address,
    this.isActive = true,
    this.vipEnabled = false,
  });

  factory BarberModel.fromMap(Map<String, dynamic> map) {
    return BarberModel(
      id: map['id'],
      name: map['name'],
      code: map['code'],
      imageUrl: map['image_url'],
      phone: map['phone'],
      address: map['address'],
      isActive: map['is_active'] ?? true,
      vipEnabled: map['vip_enabled'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'image_url': imageUrl,
        'phone': phone,
        'address': address,
        'is_active': isActive,
        'vip_enabled': vipEnabled,
      };
}

// ─── User Model ────────────────────────────────────────────
class UserModel {
  final String id;
  final String name;
  final String phone;
  final String role;
  final String? barberId;
  final String? imageUrl;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.barberId,
    this.imageUrl,
  });

  bool get isBarber => role == 'barber';
  bool get isAdmin => role == 'admin';

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      role: map['role'] ?? 'customer',
      barberId: map['barber_id'],
      imageUrl: map['image_url'],
    );
  }

  UserModel copyWith({
    String? name,
    String? imageUrl,
    String? barberId,
    bool clearImage = false,
  }) =>
      UserModel(
        id: id,
        name: name ?? this.name,
        phone: phone,
        role: role,
        barberId: barberId ?? this.barberId,
        imageUrl: clearImage ? null : (imageUrl ?? this.imageUrl),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'role': role,
        'barber_id': barberId,
        'image_url': imageUrl,
      };
}

// ─── Product Model ─────────────────────────────────────────
class ProductModel {
  final String id;
  final String barberId;
  final String name;
  final String? description;
  final double? price;
  final String? imageUrl;
  final DateTime createdAt;

  ProductModel({
    required this.id,
    required this.barberId,
    required this.name,
    this.description,
    this.price,
    this.imageUrl,
    required this.createdAt,
  });

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'],
      barberId: map['barber_id'],
      name: map['name'],
      description: map['description'],
      price: map['price'] != null ? (map['price'] as num).toDouble() : null,
      imageUrl: map['image_url'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

// ─── Chair Model ───────────────────────────────────────────
class ChairModel {
  final String id;
  final String barberId;
  final String name;
  final String? imageUrl;
  final bool isClosed;
  final bool isVipLocked;
  final bool isNormalLocked;
  int queueLength;

  ChairModel({
    required this.id,
    required this.barberId,
    required this.name,
    this.imageUrl,
    this.isClosed = false,
    this.isVipLocked = false,
    this.isNormalLocked = false,
    this.queueLength = 0,
  });

  factory ChairModel.fromMap(Map<String, dynamic> map) {
    return ChairModel(
      id: map['id'],
      barberId: map['barber_id'],
      name: map['name'],
      imageUrl: map['image_url'],
      isClosed: map['is_closed'] ?? false,
      isVipLocked: map['vip_locked'] ?? false,
      isNormalLocked: map['normal_locked'] ?? false,
      queueLength: map['queue_length'] ?? 0,
    );
  }
}

// ─── Barber Code History Model ────────────────────────────
class BarberCodeHistoryModel {
  final String id;
  final String barberId;
  final String barberName;
  final String barberCode;
  final DateTime changedAt;

  BarberCodeHistoryModel({
    required this.id,
    required this.barberId,
    required this.barberName,
    required this.barberCode,
    required this.changedAt,
  });

  factory BarberCodeHistoryModel.fromMap(Map<String, dynamic> map) {
    return BarberCodeHistoryModel(
      id: map['id'],
      barberId: map['barber_id'],
      barberName: map['barber_name'],
      barberCode: map['barber_code'],
      changedAt: DateTime.parse(map['changed_at']),
    );
  }
}

// ─── Queue Entry Model ────────────────────────────────────
class QueueEntryModel {
  final String id;
  final String chairId;
  final String userId;
  final int position;
  final String queueType;
  final DateTime createdAt;
  String? userName;
  String? userPhone;

  QueueEntryModel({
    required this.id,
    required this.chairId,
    required this.userId,
    required this.position,
    this.queueType = 'normal',
    required this.createdAt,
    this.userName,
    this.userPhone,
  });

  factory QueueEntryModel.fromMap(Map<String, dynamic> map) {
    final user = map['users'];
    return QueueEntryModel(
      id: map['id'],
      chairId: map['chair_id'],
      userId: map['user_id'],
      position: map['position'],
      queueType: map['queue_type'] ?? 'normal',
      createdAt: DateTime.parse(map['created_at']),
      userName: user != null ? user['name'] : null,
      userPhone: user != null ? user['phone'] : null,
    );
  }
}
