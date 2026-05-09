import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../firebase_options.dart';
import 'notification_service.dart';

/// Top-level handler required by Firebase for messages received while the app
/// is terminated or in the background. Must be a top-level (non-class) function.
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // System tray notification is shown automatically by FCM when the payload
  // contains a `notification` object — no extra work needed here.
}

class FcmService {
  static final _fcm = FirebaseMessaging.instance;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Call once at app startup (after Firebase.initializeApp).
  static Future<void> initialize() async {
    // Request permission (iOS prompt + Android 13+ runtime permission).
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Register the background/terminated handler.
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);

    // Show a local banner when an FCM message arrives in the foreground.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Persist the token whenever Firebase rotates it.
    _fcm.onTokenRefresh.listen(_saveTokenForCurrentUser);

    // Save the current token (covers the already-logged-in session-restore path).
    await _trySaveToken();
  }

  /// Call right after a successful login or registration.
  static Future<void> onUserLoggedIn(String userId) async {
    try {
      final token = await _fcm.getToken();
      if (token != null) await _saveToken(userId, token);
    } catch (e) {
      debugPrint('[FCM] onUserLoggedIn error: $e');
    }
  }

  /// Call on logout so the server stops sending notifications to this device.
  static Future<void> onUserLoggedOut(String userId) async {
    try {
      await Supabase.instance.client
          .from('users')
          .update({'fcm_token': null}).eq('id', userId);
      await _fcm.deleteToken();
    } catch (e) {
      debugPrint('[FCM] onUserLoggedOut error: $e');
    }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Show a local notification banner when the app is in the foreground.
  static void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    final type = message.data['type'] as String?;
    final position = int.tryParse(message.data['position'] ?? '');

    if (type == 'position' && position != null) {
      if (position == 3) {
        NotificationService.notifyCustomerPositionThree();
      } else {
        NotificationService.notifyCustomerPosition(position);
      }
    } else {
      // Generic fallback — show title/body as a barber-style notification.
      NotificationService.notifyBarberNewCustomer(
        notification.title ?? message.data['chair_name'] ?? '',
      );
    }
  }

  /// Save the token for the user whose ID is persisted in SharedPreferences.
  static Future<void> _saveTokenForCurrentUser(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('saved_user_id');
      if (userId == null) return;
      await _saveToken(userId, token);
    } catch (e) {
      debugPrint('[FCM] token refresh save error: $e');
    }
  }

  /// Used at startup to update the token if the user was already signed in.
  static Future<void> _trySaveToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('saved_user_id');
      if (userId == null) return;
      final token = await _fcm.getToken();
      if (token != null) await _saveToken(userId, token);
    } catch (e) {
      debugPrint('[FCM] startup token save error: $e');
    }
  }

  static Future<void> _saveToken(String userId, String token) async {
    await Supabase.instance.client
        .from('users')
        .update({'fcm_token': token}).eq('id', userId);
    debugPrint('[FCM] token saved for $userId');
  }
}
