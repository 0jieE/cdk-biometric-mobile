import '../../models/employee.dart';

enum AuthStatus {
  /// Startup — we don't yet know if a session exists.
  unknown,

  /// A valid/refreshable session exists; [employee] may still be loading.
  authenticated,

  /// No session — show login.
  unauthenticated,
}

class AuthState {
  final AuthStatus status;
  final Employee? employee;

  /// True while a login request or bootstrap check is in flight.
  final bool busy;

  /// Last login error message to surface on the login screen.
  final String? error;

  const AuthState({
    required this.status,
    this.employee,
    this.busy = false,
    this.error,
  });

  const AuthState.unknown() : this(status: AuthStatus.unknown);

  bool get isAuthenticated => status == AuthStatus.authenticated;

  AuthState copyWith({
    AuthStatus? status,
    Employee? employee,
    bool? busy,
    String? error,
    bool clearError = false,
    bool clearEmployee = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      employee: clearEmployee ? null : (employee ?? this.employee),
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
