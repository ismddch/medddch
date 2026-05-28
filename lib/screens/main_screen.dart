import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/supabase_service.dart';
import '../utils/theme.dart';
import 'shops_list_screen.dart';
import 'all_barbers_screen.dart';
import 'my_barber_screen.dart';
import 'my_booking_screen.dart';
import 'products_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final SupabaseService _service = SupabaseService();

  // Start on home; will switch to favorites tab (index 1) if user has saved barbers.
  int _currentIndex = 0;

  final _screens = const [
    AllBarbersScreen(),
    MyBarberScreen(),
    MyBookingScreen(),
    ShopsListScreen(),
    ProductsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkFavorites();
  }

  Future<void> _checkFavorites() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null) return;
    try {
      final ids = await _service.getFavoriteBarberIds(userId);
      if (ids.isNotEmpty && mounted) {
        setState(() => _currentIndex = 1);
      }
    } catch (_) {
      // Non-fatal — stay on default home tab
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        backgroundColor: AppTheme.card,
        indicatorColor: AppTheme.accent.withValues(alpha: 0.15),
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded, color: AppTheme.accent),
            label: 'الرئيسية',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline_rounded),
            selectedIcon: Icon(Icons.bookmark_rounded, color: AppTheme.accent),
            label: 'حلاقي',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon:
                Icon(Icons.calendar_month_rounded, color: AppTheme.accent),
            label: 'حجزي',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront, color: AppTheme.accent),
            label: 'الصالونات',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag, color: AppTheme.accent),
            label: 'المنتجات',
          ),
        ],
      ),
    );
  }
}
