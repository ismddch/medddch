// ─── Shop Model (was BarberModel) ──────────────────────────────
// Maps to the `shops` table (previously `barbers`)
class ShopModel {
  final String id;
  final String name;
  final String code;
  final String? imageUrl;
  final String? phone;
  final String? address;
  final String? mapsUrl;
  final bool isActive;
  final bool vipEnabled;
  final bool prepaymentEnabled;

  ShopModel({
    required this.id,
    required this.name,
    required this.code,
    this.imageUrl,
    this.phone,
    this.address,
    this.mapsUrl,
    this.isActive = true,
    this.vipEnabled = false,
    this.prepaymentEnabled = false,
  });

  factory ShopModel.fromMap(Map<String, dynamic> map) {
    return ShopModel(
      id: map['id'],
      name: map['name'],
      code: map['code'],
      imageUrl: map['image_url'],
      phone: map['phone'],
      address: map['address'],
      mapsUrl: map['maps_url'],
      isActive: map['is_active'] ?? true,
      vipEnabled: map['vip_enabled'] ?? false,
      prepaymentEnabled: map['prepayment_enabled'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'image_url': imageUrl,
        'phone': phone,
        'address': address,
        'maps_url': mapsUrl,
        'is_active': isActive,
        'vip_enabled': vipEnabled,
        'prepayment_enabled': prepaymentEnabled,
      };
}

// ─── Barber Model (was ChairModel) ──────────────────────────────
// Maps to the `barbers` table (previously `chairs`) — individual staff members
class BarberModel {
  final String id;
  final String shopId;           // was barberId — references shops.id
  final String name;
  final String? imageUrl;
  final bool isClosed;
  final bool isVipLocked;
  final bool isNormalLocked;
  final bool bookingCodeEnabled; // true → customer must enter a code before joining
  final String menuQueueType;    // 'both'|'vip'|'normal' — which queue type shows the menu
  int queueLength;
  int likeCount;                 // total likes from barber_likes table
  String? shopName;              // denormalised shop name for ranking screens
  String? paymentNumber;         // account/wallet number customers send money to
  String? location;              // city/area set by admin for filtering
  String? tiktokUrl;             // TikTok profile link

  BarberModel({
    required this.id,
    required this.shopId,
    required this.name,
    this.imageUrl,
    this.isClosed = false,
    this.isVipLocked = false,
    this.isNormalLocked = false,
    this.bookingCodeEnabled = false,
    this.menuQueueType = 'both',
    this.queueLength = 0,
    this.likeCount = 0,
    this.shopName,
    this.paymentNumber,
    this.location,
    this.tiktokUrl,
  });

  factory BarberModel.fromMap(Map<String, dynamic> map) {
    // Support embedded shop join: shops(name)
    final shop = map['shops'] as Map<String, dynamic>?;
    // Support embedded count joins: barber_likes(count), queues(count)
    final likeList  = map['barber_likes'] as List?;
    final queueList = map['queues']       as List?;
    final rawLike  = (likeList  != null && likeList.isNotEmpty)  ? likeList[0]['count']  : 0;
    final rawQueue = (queueList != null && queueList.isNotEmpty) ? queueList[0]['count'] : (map['queue_length'] ?? 0);

    return BarberModel(
      id: map['id'],
      shopId: map['shop_id'],
      name: map['name'],
      imageUrl: map['image_url'],
      isClosed: map['is_closed'] ?? false,
      isVipLocked: map['vip_locked'] ?? false,
      isNormalLocked: map['normal_locked'] ?? false,
      bookingCodeEnabled: map['booking_code_enabled'] ?? false,
      menuQueueType:      map['menu_queue_type'] ?? 'both',
      queueLength:   rawQueue is int ? rawQueue : int.tryParse('$rawQueue') ?? 0,
      likeCount:     rawLike  is int ? rawLike  : int.tryParse('$rawLike')  ?? 0,
      shopName:      shop?['name'],
      paymentNumber: map['payment_number'],
      location:      map['location'],
      tiktokUrl:     map['tiktok_url'],
    );
  }
}

// ─── User Model ────────────────────────────────────────────────
// barberId for role='barber' now points to barbers.id (individual staff)
// barberId for role='customer' points to shops.id (their linked shop)
class UserModel {
  final String id;
  final String name;
  final String phone;
  final String role;
  final String? barberId;
  final String? imageUrl;
  final bool isBlocked;

  UserModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
    this.barberId,
    this.imageUrl,
    this.isBlocked = false,
  });

  bool get isBarber => role == 'barber';
  bool get isAdmin => role == 'admin';
  bool get isPaymentManager => role == 'payment';
  bool get isManager => role == 'manager';

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'],
      name: map['name'],
      phone: map['phone'],
      role: map['role'] ?? 'customer',
      barberId: map['barber_id'],
      imageUrl: map['image_url'],
      isBlocked: map['is_blocked'] ?? false,
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
        isBlocked: isBlocked,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'role': role,
        'barber_id': barberId,
        'image_url': imageUrl,
        'is_blocked': isBlocked,
      };
}

// ─── Product Model ─────────────────────────────────────────────
// Products belong to shops; shopId (was barberId)
class ProductModel {
  final String id;
  final String shopId;      // was barberId — references shops.id
  final String name;
  final String? description;
  final double? price;
  final String? imageUrl;
  final DateTime createdAt;

  ProductModel({
    required this.id,
    required this.shopId,
    required this.name,
    this.description,
    this.price,
    this.imageUrl,
    required this.createdAt,
  });

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'],
      shopId: map['shop_id'],
      name: map['name'],
      description: map['description'],
      price: map['price'] != null ? (map['price'] as num).toDouble() : null,
      imageUrl: map['image_url'],
      createdAt: DateTime.parse(map['created_at']),
    );
  }
}

// ─── Shop With Barbers (was BarberWithChairs) ──────────────────
class ShopWithBarbers {
  final ShopModel shop;
  final List<BarberModel> barbers;

  ShopWithBarbers({required this.shop, required this.barbers});
}

// ─── Shop Code History Model (was BarberCodeHistoryModel) ──────
class ShopCodeHistoryModel {
  final String id;
  final String shopId;
  final String shopName;
  final String shopCode;
  final DateTime changedAt;

  ShopCodeHistoryModel({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.shopCode,
    required this.changedAt,
  });

  factory ShopCodeHistoryModel.fromMap(Map<String, dynamic> map) {
    return ShopCodeHistoryModel(
      id: map['id'],
      shopId: map['shop_id'],
      shopName: map['shop_name'],
      shopCode: map['shop_code'],
      changedAt: DateTime.parse(map['changed_at']),
    );
  }
}

// ─── Payment Request Model ─────────────────────────────────────
// barberId = staff barber (individual barber), shopId = shop (salon)
class PaymentRequestModel {
  final String id;
  final String userId;
  final String barberId;    // references barbers.id (individual staff)
  final String shopId;      // references shops.id
  final double? amount;
  final String walletType;
  final String photoUrl;
  final String queueType;
  final String status;
  final DateTime createdAt;
  String? userName;
  String? userPhone;
  String? barberName;       // staff barber name
  String? shopName;         // shop name
  final List<Map<String, dynamic>>? selectedServices; // services chosen at booking

  PaymentRequestModel({
    required this.id,
    required this.userId,
    required this.barberId,
    required this.shopId,
    this.amount,
    required this.walletType,
    required this.photoUrl,
    this.queueType = 'normal',
    required this.status,
    required this.createdAt,
    this.userName,
    this.userPhone,
    this.barberName,
    this.shopName,
    this.selectedServices,
  });

  bool get isPending  => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';

  factory PaymentRequestModel.fromMap(Map<String, dynamic> map) {
    final user   = map['users']   as Map<String, dynamic>?;
    final barber = map['barbers'] as Map<String, dynamic>?;
    final shop   = map['shops']   as Map<String, dynamic>?;
    // Parse selected_services JSONB
    List<Map<String, dynamic>>? services;
    final rawSvc = map['selected_services'];
    if (rawSvc is List) {
      services = rawSvc.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    }
    return PaymentRequestModel(
      id:               map['id'],
      userId:           map['user_id'],
      barberId:         map['barber_id'],
      shopId:           map['shop_id'],
      amount:           map['amount'] != null ? (map['amount'] as num).toDouble() : null,
      walletType:       map['wallet_type'],
      photoUrl:         map['photo_url'],
      queueType:        map['queue_type'] ?? 'normal',
      status:           map['status'],
      createdAt:        DateTime.parse(map['created_at']),
      userName:         user?['name'],
      userPhone:        user?['phone'],
      barberName:       barber?['name'],
      shopName:         shop?['name'],
      selectedServices: services,
    );
  }
}

// ─── Barber Menu Item Model ────────────────────────────────────
class BarberMenuItemModel {
  final String id;
  final String barberId;
  final String name;
  final double price;
  final bool isAvailable;
  final int sortOrder;
  /// 'vip' | 'normal' | 'both'  — which queue type this item applies to
  final String queueType;
  final DateTime createdAt;

  BarberMenuItemModel({
    required this.id,
    required this.barberId,
    required this.name,
    required this.price,
    this.isAvailable = true,
    this.sortOrder = 0,
    this.queueType = 'both',
    required this.createdAt,
  });

  factory BarberMenuItemModel.fromMap(Map<String, dynamic> map) {
    return BarberMenuItemModel(
      id:          map['id'],
      barberId:    map['barber_id'],
      name:        map['name'],
      price:       (map['price'] as num).toDouble(),
      isAvailable: map['is_available'] ?? true,
      sortOrder:   map['sort_order'] ?? 0,
      queueType:   map['queue_type'] as String? ?? 'both',
      createdAt:   DateTime.parse(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id':           id,
        'barber_id':    barberId,
        'name':         name,
        'price':        price,
        'is_available': isAvailable,
        'sort_order':   sortOrder,
        'queue_type':   queueType,
        'created_at':   createdAt.toIso8601String(),
      };

  // For selected services JSONB storage
  Map<String, dynamic> toSelectedJson() => {
        'id':    id,
        'name':  name,
        'price': price,
      };
}

// ─── Queue Entry Model ─────────────────────────────────────────
// barberId (was chairId); joins: barbers → shops
class QueueEntryModel {
  final String id;
  final String barberId;    // was chairId — references barbers.id (individual staff)
  final String userId;
  final int position;
  final String queueType;
  final DateTime createdAt;
  String? userName;
  String? userPhone;
  String? barberName;       // the staff barber's name
  String? shopName;         // the shop name (from barbers→shops join)
  bool shopPrepaymentEnabled;
  final List<Map<String, dynamic>>? selectedServices; // services chosen at booking
  final double? servicesTotal;                        // total price of services

  QueueEntryModel({
    required this.id,
    required this.barberId,
    required this.userId,
    required this.position,
    this.queueType = 'normal',
    required this.createdAt,
    this.userName,
    this.userPhone,
    this.barberName,
    this.shopName,
    this.shopPrepaymentEnabled = false,
    this.selectedServices,
    this.servicesTotal,
  });

  factory QueueEntryModel.fromMap(Map<String, dynamic> map) {
    final user   = map['users']   as Map<String, dynamic>?;
    final barber = map['barbers'] as Map<String, dynamic>?;
    final shop   = barber?['shops'] as Map<String, dynamic>?;
    // Parse selected_services JSONB (can be List or null)
    List<Map<String, dynamic>>? services;
    final rawServices = map['selected_services'];
    if (rawServices is List) {
      services = rawServices.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    }
    return QueueEntryModel(
      id:                      map['id'],
      barberId:                map['barber_id'],
      userId:                  map['user_id'],
      position:                map['position'],
      queueType:               map['queue_type'] ?? 'normal',
      createdAt:               DateTime.parse(map['created_at']),
      userName:                user?['name'],
      userPhone:               user?['phone'],
      barberName:              barber?['name'],
      shopName:                shop?['name'],
      shopPrepaymentEnabled:   shop?['prepayment_enabled'] as bool? ?? false,
      selectedServices:        services,
      servicesTotal:           map['services_total'] != null
                                   ? (map['services_total'] as num).toDouble()
                                   : null,
    );
  }
}
