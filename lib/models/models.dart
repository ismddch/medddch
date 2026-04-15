// ─── Barber Model ──────────────────────────────────────────
class BarberModel {
  final String id;
  final String name;
  final String code;
  final String? imageUrl;
  final String? phone;
  final String? address;
  final bool isActive;

  BarberModel({
    required this.id,
    required this.name,
    required this.code,
    this.imageUrl,
    this.phone,
    this.address,
    this.isActive = true,
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
      };
}

// ─── User Model ────────────────────────────────────────────
class UserModel {
  final String id;
  final String name;
  final String phone;
  final String role;
  final String? barberId;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.barberId,
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
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'role': role,
        'barber_id': barberId,
      };
}

// ─── Chair Model ───────────────────────────────────────────
class ChairModel {
  final String id;
  final String barberId;
  final String name;
  final String? imageUrl;
  final bool isClosed;
  int queueLength;

  ChairModel({
    required this.id,
    required this.barberId,
    required this.name,
    this.imageUrl,
    this.isClosed = false,
    this.queueLength = 0,
  });

  factory ChairModel.fromMap(Map<String, dynamic> map) {
    return ChairModel(
      id: map['id'],
      barberId: map['barber_id'],
      name: map['name'],
      imageUrl: map['image_url'],
      isClosed: map['is_closed'] ?? false,
      queueLength: map['queue_length'] ?? 0,
    );
  }
}

// ─── Queue Entry Model ────────────────────────────────────
class QueueEntryModel {
  final String id;
  final String chairId;
  final String userId;
  final int position;
  final DateTime createdAt;
  String? userName;
  String? userPhone;

  QueueEntryModel({
    required this.id,
    required this.chairId,
    required this.userId,
    required this.position,
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
      createdAt: DateTime.parse(map['created_at']),
      userName: user != null ? user['name'] : null,
      userPhone: user != null ? user['phone'] : null,
    );
  }
}
