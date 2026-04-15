import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/auth_provider.dart';
import 'screens/login_screen.dart';
import 'utils/constants.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://xwgwzhbpbwwgbedaxqec.supabase.co',
    anonKey: 'sb_publishable_gXo6m12b4EGEGeEIS4UaMA_F4G_F9T_',
  );

  runApp(const BarbershopQueueApp());
}

class BarbershopQueueApp extends StatelessWidget {
  const BarbershopQueueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(),
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        // Force RTL for Arabic
        builder: (context, child) {
          return Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          );
        },
        home: const LoginScreen(),
      ),
    );
  }
}
