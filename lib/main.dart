import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_provider.dart';
import 'services/notification_service.dart';
import 'services/supabase_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/barber_screen.dart';
import 'screens/queue_details_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/payment_manager_screen.dart';
import 'screens/manager_screen.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';

/// Global navigator key — used by the deep-link handler to push routes
/// from outside the widget tree.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Runs in a separate Dart isolate when the app is in background or killed.
/// FCM messages that include a `notification` field are shown automatically
/// by the OS. This handler covers data-only messages and ensures Firebase is
/// ready for any processing needed.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // For Android data-only messages: show a local notification manually.
  // (iOS handles all background display via APNs automatically.)
  await NotificationService.showFromFcmData(message.data);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase — non-fatal if unavailable on the current platform
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  } catch (_) {}

  // 2. Supabase
  await Supabase.initialize(
    url: 'https://xwgwzhbpbwwgbedaxqec.supabase.co',
    anonKey: 'sb_publishable_gXo6m12b4EGEGeEIS4UaMA_F4G_F9T_',
  );

  // 3. Local notifications + FCM token
  try {
    await NotificationService.initialize();
  } catch (_) {}

  // 4. Session
  final authProvider = AuthProvider();
  await authProvider.loadSession();

  runApp(BarbershopQueueApp(authProvider: authProvider));
}

class BarbershopQueueApp extends StatefulWidget {
  final AuthProvider authProvider;
  const BarbershopQueueApp({super.key, required this.authProvider});

  @override
  State<BarbershopQueueApp> createState() => _BarbershopQueueAppState();
}

class _BarbershopQueueAppState extends State<BarbershopQueueApp> {
  final _appLinks   = AppLinks();
  final _service    = SupabaseService();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    // Handle hallaqak:// deep link when app is already running
    _linkSub = _appLinks.uriLinkStream.listen(_handleLink);
    // Handle hallaqak:// deep link that cold-started the app
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) _handleLink(uri);
    } catch (_) {}

    // Handle FCM notification tap when app was terminated (cold start)
    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleFcmMessage(initial);
    } catch (_) {}

    // Handle FCM notification tap when app was in background (resumed)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleFcmMessage);
  }

  void _handleFcmMessage(RemoteMessage msg) {
    final type = msg.data['type'] as String?;
    // Payment notification → barber's screen doesn't need extra navigation
    // (barber is already on BarberScreen which auto-refreshes via Realtime)
    // Queue position notification → customer may not have the screen open;
    // no navigation needed — the user is already waiting in the queue.
    // Both cases: the notification itself conveys the information.
    // If you later want to open a specific screen, add navigation here.
    debugPrint('[FCM tap] type=$type');
  }

  Future<void> _handleLink(Uri uri) async {
    if (uri.scheme != 'hallaqak' || uri.host != 'barber') return;
    final barberId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (barberId == null || barberId.isEmpty) return;

    // Wait briefly so the app UI is fully mounted before navigating
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final barber = await _service.getBarberById(barberId);
      if (barber == null) return;
      // Only navigate if the customer role is active (not barber/admin)
      final auth = widget.authProvider;
      if (!auth.isLoggedIn || auth.isBarber || auth.isAdmin) return;
      if (navigatorKey.currentContext == null) return;
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => QueueDetailsScreen(barber: barber)),
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Widget _home() {
    if (!widget.authProvider.isLoggedIn) return const LoginScreen();
    if (widget.authProvider.isAdmin) return const AdminDashboardScreen();
    if (widget.authProvider.isBarber) return const BarberScreen();
    if (widget.authProvider.isPaymentManager) return const PaymentManagerScreen();
    if (widget.authProvider.isManager) return const ManagerScreen();
    return const MainScreen();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.authProvider,
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          );
        },
        home: _home(),
      ),
    );
  }
}
