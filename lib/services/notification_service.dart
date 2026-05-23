import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  // Sent to the customer when their position drops to 2 or 1.
  static Future<void> notifyCustomerPosition(int position) async {
    if (!_initialized) return;

    final bool isFirst = position == 1;
    final title = isFirst ? 'حان دورك! 🎉' : 'استعد، أنت التالي!';
    final body = isFirst
        ? 'أنت الآن الأول في الطابور — توجه للكرسي الآن.'
        : 'أنت في المرتبة الثانية، لم يتبقَّ سوى شخص واحد!';

    await _plugin.show(
      position,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'queue_position',
          'موقعك في الطابور',
          channelDescription: 'إشعارات تغيير موقعك في طابور الانتظار',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  // Sent to the barber when a new customer joins their queue.
  static Future<void> notifyBarberNewCustomer(String barberName) async {
    if (!_initialized) return;

    await _plugin.show(
      100,
      'عميل جديد في الطابور',
      barberName.isNotEmpty
          ? 'انضم عميل جديد إلى طابور $barberName'
          : 'انضم عميل جديد إلى الطابور',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'new_customer',
          'عملاء جدد',
          channelDescription: 'إشعارات انضمام عملاء جدد للطابور',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  // Sent to the barber when a new paid booking request arrives.
  static Future<void> notifyBarberNewPayment(String customerName) async {
    if (!_initialized) return;
    await _plugin.show(
      200,
      'طلب حجز مدفوع جديد 💰',
      customerName.isNotEmpty
          ? 'أرسل $customerName طلب حجز — راجع الإيصال وأكّد الدفع'
          : 'وصل طلب حجز مدفوع جديد — راجع الإيصال وأكّد الدفع',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'paid_booking',
          'الحجوزات المدفوعة',
          channelDescription: 'إشعارات طلبات الحجز المدفوعة الواردة',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // Position 3 notification (new — FCM triggers this for position 3 as well).
  static Future<void> notifyCustomerPositionThree() async {
    if (!_initialized) return;
    await _plugin.show(
      3,
      'اقترب دورك',
      'أنت في المرتبة الثالثة — استعد قريباً!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'queue_position',
          'موقعك في الطابور',
          channelDescription: 'إشعارات تغيير موقعك في طابور الانتظار',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
