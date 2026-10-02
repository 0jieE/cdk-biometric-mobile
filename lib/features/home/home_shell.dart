import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../attendance/attendance_screen.dart';
import '../notifications/fcm_service.dart';
import '../notifications/notifications_controller.dart';
import '../profile/profile_screen.dart';
import '../notifications/notifications_screen.dart';

/// Authenticated shell with bottom navigation:
/// Attendance · Notifications · Profile.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _tabs = [
    AttendanceScreen(),
    NotificationsScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Landing here means we are authenticated (fresh login or restored
    // session): register this device's FCM token. No-op if Firebase is off.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(fcmServiceProvider).syncTokenAfterLogin();
    });
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(selectedTabProvider);
    final unread = ref.watch(
      notificationsControllerProvider.select((s) => s.unreadCount),
    );

    return Scaffold(
      body: IndexedStack(index: index, children: _tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(selectedTabProvider.notifier).set(i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Attendance',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.notifications),
            ),
            label: 'Notifications',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
