import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;

    // ── Notifications locales ──────────────────────────────────────────────
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

    // ── FCM : demande permission + écoute messages foreground ─────────────
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Quand l'app est ouverte, afficher la notification locale manuellement
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        final n = msg.notification;
        if (n != null) {
          _show(
            id: msg.hashCode,
            title: n.title ?? '',
            body: n.body ?? '',
            channelId: _channelId(msg.data['type']),
            channelName: _channelName(msg.data['type']),
          );
        }
      });

      // ── Sauvegarder le token FCM dans Supabase ───────────────────────────
      await _saveToken();
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => _saveToken());
    } catch (_) {
      // FCM non disponible — les notifications locales fonctionnent toujours
    }

    _initialized = true;
  }

  // ── Sauvegarde token ────────────────────────────────────────────────────

  /// Appeler après chaque connexion réussie pour s'assurer que le token
  /// est enregistré même si l'utilisateur vient de créer son compte.
  static Future<void> saveTokenForUser(String userId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': token})
          .eq('id', userId);
    } catch (_) {}
  }

  static Future<void> _saveToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('saved_user_id');
      if (userId == null) return;
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': token})
          .eq('id', userId);
    } catch (_) {
      // Non bloquant — les notifications locales fonctionnent sans FCM
    }
  }

  // ── Helpers canaux ──────────────────────────────────────────────────────

  static String _channelId(String? type) =>
      (type == 'new_customer' || type == 'paid_booking')
          ? 'new_customer'
          : 'queue_position';

  static String _channelName(String? type) {
    if (type == 'new_customer') return 'عملاء جدد';
    if (type == 'paid_booking') return 'الحجوزات المدفوعة';
    return 'موقعك في الطابور';
  }

  // ── Affichage notification locale ───────────────────────────────────────

  static Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    Importance importance = Importance.max,
  }) async {
    if (!_initialized) return;
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          importance: importance,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ── Méthodes publiques (déclenchées par Realtime quand app ouverte) ─────

  static Future<void> notifyCustomerPosition(int position) async {
    final bool isFirst = position == 1;
    await _show(
      id: position,
      title: isFirst ? 'حان دورك! 🎉' : 'استعد، أنت التالي!',
      body: isFirst
          ? 'أنت الآن الأول في الطابور — توجه للكرسي الآن.'
          : 'أنت في المرتبة الثانية، لم يتبقَّ سوى شخص واحد!',
      channelId: 'queue_position',
      channelName: 'موقعك في الطابور',
    );
  }

  static Future<void> notifyCustomerPositionThree() async {
    await _show(
      id: 3,
      title: 'اقترب دورك',
      body: 'أنت في المرتبة الثالثة — استعد قريباً!',
      channelId: 'queue_position',
      channelName: 'موقعك في الطابور',
      importance: Importance.high,
    );
  }

  static Future<void> notifyBarberNewCustomer(String barberName) async {
    await _show(
      id: 100,
      title: 'عميل جديد في الطابور',
      body: barberName.isNotEmpty
          ? 'انضم عميل جديد إلى طابور $barberName'
          : 'انضم عميل جديد إلى الطابور',
      channelId: 'new_customer',
      channelName: 'عملاء جدد',
    );
  }

  static Future<void> notifyBarberNewPayment(String customerName) async {
    await _show(
      id: 200,
      title: 'طلب حجز مدفوع جديد 💰',
      body: customerName.isNotEmpty
          ? 'أرسل $customerName طلب حجز — راجع الإيصال وأكّد الدفع'
          : 'وصل طلب حجز مدفوع جديد — راجع الإيصال وأكّد الدفع',
      channelId: 'new_customer',
      channelName: 'الحجوزات المدفوعة',
    );
  }
}
