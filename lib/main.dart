import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_provider.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/barber_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/payment_manager_screen.dart';
import 'screens/manager_screen.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';

/// Appelé par Android/iOS quand une notification FCM arrive et que l'app
/// est fermée ou en arrière-plan. Doit être une fonction top-level.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Le payload FCM contient déjà un bloc notification → Android/iOS affiche
  // la notification système automatiquement, rien d'autre à faire ici.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase (avant Supabase) — non-fatal si indisponible sur la plateforme
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  } catch (_) {
    // Firebase non supporté sur ce build (web sans config, etc.) — on continue
  }

  // 2. Supabase
  await Supabase.initialize(
    url: 'https://xwgwzhbpbwwgbedaxqec.supabase.co',
    anonKey: 'sb_publishable_gXo6m12b4EGEGeEIS4UaMA_F4G_F9T_',
  );

  // 3. Notifications locales + enregistrement token FCM
  try {
    await NotificationService.initialize();
  } catch (_) {}

  // 4. Session
  final authProvider = AuthProvider();
  await authProvider.loadSession();

  runApp(BarbershopQueueApp(authProvider: authProvider));
}

class BarbershopQueueApp extends StatelessWidget {
  final AuthProvider authProvider;
  const BarbershopQueueApp({super.key, required this.authProvider});

  Widget _home() {
    if (!authProvider.isLoggedIn) return const LoginScreen();
    if (authProvider.isAdmin) return const AdminDashboardScreen();
    if (authProvider.isBarber) return const BarberScreen();
    if (authProvider.isPaymentManager) return const PaymentManagerScreen();
    if (authProvider.isManager) return const ManagerScreen();
    return const MainScreen();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: authProvider,
      child: MaterialApp(
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
