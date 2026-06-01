import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // ── Notification channel IDs ──────────────────────────────────────────────
  static const _chQueue   = 'queue_position';
  static const _chPayment = 'new_customer';

  // ── Initialize ────────────────────────────────────────────────────────────

  static Future<void> initialize() async {
    if (_initialized) return;

    // ── Local notifications (flutter_local_notifications) ──────────────────
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosSettings     = DarwinInitializationSettings(
      requestAlertPermission: false, // we request below via FCM permission
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Android 13+ runtime permission
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // ── Firebase Messaging ─────────────────────────────────────────────────
    try {
      final messaging = FirebaseMessaging.instance;

      // 1. Request permission (shows the iOS system alert exactly once)
      final settings = await messaging.requestPermission(
        alert:         true,
        badge:         true,
        sound:         true,
        provisional:   false,
        announcement:  false,
        carPlay:       false,
        criticalAlert: false,
      );
      final granted = settings.authorizationStatus == AuthorizationStatus.authorized
          || settings.authorizationStatus == AuthorizationStatus.provisional;

      if (granted) {
        // 2. iOS: show FCM notifications while app is in foreground
        //    (without this, iOS silently drops them)
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // 3. Show a local notification when FCM arrives in foreground on Android
        //    (iOS uses setForegroundNotificationPresentationOptions above)
        FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
          if (Platform.isAndroid) {
            final n = msg.notification;
            if (n != null) {
              _show(
                id:          msg.hashCode,
                title:       n.title ?? '',
                body:        n.body  ?? '',
                channelId:   _chIdFromData(msg.data['type']),
                channelName: _chNameFromData(msg.data['type']),
              );
            }
          }
        });

        // 4. Save FCM token to Supabase
        await _persistToken();
        messaging.onTokenRefresh.listen((_) => _persistToken());
      }
    } catch (e) {
      // Firebase unavailable on this platform/build — local notifications still work
    }

    _initialized = true;
  }

  // ── Token persistence ─────────────────────────────────────────────────────

  /// Call this immediately after a successful login / register so the token
  /// is linked to the right user even on first launch.
  static Future<void> saveTokenForUser(String userId) async {
    try {
      final token = await _getFcmToken();
      if (token == null) return;
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': token})
          .eq('id', userId);
    } catch (_) {}
  }

  /// Read token from SharedPreferences (saved after login) and persist to DB.
  static Future<void> _persistToken() async {
    try {
      final token = await _getFcmToken();
      if (token == null) return;
      final prefs  = await SharedPreferences.getInstance();
      final userId = prefs.getString('saved_user_id');
      if (userId == null) return;
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': token})
          .eq('id', userId);
    } catch (_) {}
  }

  /// Gets FCM token, waiting for APNs token on iOS first.
  static Future<String?> _getFcmToken() async {
    try {
      if (Platform.isIOS) {
        // On iOS, FCM token requires APNs token. Wait up to 5 s.
        for (var i = 0; i < 10; i++) {
          final apns = await FirebaseMessaging.instance.getAPNSToken();
          if (apns != null) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }

  // ── Channel helpers ───────────────────────────────────────────────────────

  static String _chIdFromData(String? type) =>
      (type == 'new_customer' || type == 'paid_booking') ? _chPayment : _chQueue;

  static String _chNameFromData(String? type) {
    if (type == 'new_customer') return 'عملاء جدد';
    if (type == 'paid_booking') return 'الحجوزات المدفوعة';
    return 'موقعك في الطابور';
  }

  // ── Show local notification ───────────────────────────────────────────────

  static Future<void> _show({
    required int    id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    Importance      importance = Importance.max,
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
          priority:   Priority.high,
          playSound:  true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  // ── Public helpers (triggered by Supabase Realtime while app is open) ─────

  static Future<void> notifyCustomerPosition(int position) async {
    final isFirst = position == 1;
    await _show(
      id:          position,
      title:       isFirst ? 'حان دورك! 🎉' : 'استعد، أنت التالي!',
      body:        isFirst
          ? 'أنت الآن الأول في الطابور — توجه للكرسي الآن.'
          : 'أنت في المرتبة الثانية، لم يتبقَّ سوى شخص واحد!',
      channelId:   _chQueue,
      channelName: 'موقعك في الطابور',
    );
  }

  static Future<void> notifyCustomerPositionThree() async {
    await _show(
      id:          3,
      title:       'اقترب دورك',
      body:        'أنت في المرتبة الثالثة — استعد قريباً!',
      channelId:   _chQueue,
      channelName: 'موقعك في الطابور',
      importance:  Importance.high,
    );
  }

  static Future<void> notifyBarberNewCustomer(String barberName) async {
    await _show(
      id:          100,
      title:       'عميل جديد في الطابور',
      body:        barberName.isNotEmpty
          ? 'انضم عميل جديد إلى طابور $barberName'
          : 'انضم عميل جديد إلى الطابور',
      channelId:   _chPayment,
      channelName: 'عملاء جدد',
    );
  }

  static Future<void> notifyBarberNewPayment(String customerName) async {
    await _show(
      id:          200,
      title:       'طلب حجز مدفوع جديد 💰',
      body:        customerName.isNotEmpty
          ? 'أرسل $customerName طلب حجز — راجع الإيصال وأكّد الدفع'
          : 'وصل طلب حجز مدفوع جديد — راجع الإيصال وأكّد الدفع',
      channelId:   _chPayment,
      channelName: 'الحجوزات المدفوعة',
    );
  }
}
