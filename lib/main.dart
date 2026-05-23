import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'services/auth_provider.dart';
import 'services/fcm_service.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/barber_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/payment_manager_screen.dart';
import 'screens/manager_screen.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Firebase must be initialized first so the FCM background handler
  //    (@pragma vm:entry-point) can call Firebase.initializeApp safely.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 2. Supabase
  await Supabase.initialize(
    url: 'https://xwgwzhbpbwwgbedaxqec.supabase.co',
    anonKey: 'sb_publishable_gXo6m12b4EGEGeEIS4UaMA_F4G_F9T_',
  );

  // 3. Restore session before FCM so _trySaveToken finds the saved user ID.
  final authProvider = AuthProvider();
  await authProvider.loadSession();

  // 4. FCM — registers background handler + saves token for the logged-in user.
  await FcmService.initialize();

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
