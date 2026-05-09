import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'services/auth_provider.dart';
import 'services/fcm_service.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/barber_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase must be initialized before Supabase so the FCM background handler
  // can also call Firebase.initializeApp without a second Supabase init.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await Supabase.initialize(
    url: 'https://xwgwzhbpbwwgbedaxqec.supabase.co',
    anonKey: 'sb_publishable_gXo6m12b4EGEGeEIS4UaMA_F4G_F9T_',
  );

  await NotificationService.initialize();
  await FcmService.initialize();

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
