import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/auth_state.dart';
import '../../features/auth/login_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/home/splash_screen.dart';

/// Route paths.
class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const home = '/home';
}

/// Currently selected home tab. FCM taps set this to the notifications tab.
final selectedTabProvider = NotifierProvider<SelectedTabNotifier, int>(
  SelectedTabNotifier.new,
);

class SelectedTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final routerProvider = Provider<GoRouter>((ref) {
  // Bridge Riverpod auth changes into a Listenable for go_router.
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;

      final auth = ref.read(authControllerProvider);
      switch (auth.status) {
        case AuthStatus.unknown:
          return loc == Routes.splash ? null : Routes.splash;
        case AuthStatus.unauthenticated:
          return loc == Routes.login ? null : Routes.login;
        case AuthStatus.authenticated:
          return (loc == Routes.login || loc == Routes.splash)
              ? Routes.home
              : null;
      }
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.home, builder: (_, _) => const HomeShell()),
    ],
  );
});
