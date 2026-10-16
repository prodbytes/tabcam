import 'package:flutter/widgets.dart';

import 'auth_service.dart';

/// Several sign-in providers as one [AuthService] (Google and Apple on
/// iOS): the user signs in with any of them, one at a time. Signing in with
/// one signs the other out, so the session (user, ID token, provider) is
/// always one provider's.
class MultiAuthService extends AuthService {
  /// [services] each sign in with their own provider(s), their buttons in
  /// this order.
  MultiAuthService(List<AuthService> services)
    : _services = List.unmodifiable(services) {
    for (final s in _services) {
      s.addListener(_changed);
    }
  }

  final List<AuthService> _services;

  /// The service whose session this is.
  AuthService? _active;

  @override
  AuthUser? get user => _active?.user;

  @override
  String? get idToken => _active?.idToken;

  @override
  List<AuthProvider> get providers => [
    for (final s in _services)
      if (s.available) ...s.providers,
  ];

  @override
  bool get checking => _services.any((s) => s.checking);

  @override
  bool get available => _services.any((s) => s.available);

  @override
  String? get unavailableReason => available
      ? null
      : _services.map((s) => s.unavailableReason).nonNulls.firstOrNull;

  @override
  String? get error => _services
      .where((s) => s.available)
      .map((s) => s.error)
      .nonNulls
      .firstOrNull;

  AuthService _for(AuthProvider provider) => _services.firstWhere(
    (s) => s.providers.contains(provider),
    orElse: () => throw ArgumentError('No sign-in with ${provider.label}'),
  );

  void _changed() {
    final active = _active;
    if (active != null && active.user != null) {
      // Someone signed in with another provider too: theirs is the session
      // now, and the old one signs out.
      for (final s in _services) {
        if (s != active && s.user != null) {
          _active = s;
          active.signOut().ignore();
          break;
        }
      }
    } else {
      _active = _services.where((s) => s.user != null).firstOrNull;
    }
    notifyListeners();
  }

  @override
  Future<void> init() async {
    await Future.wait([for (final s in _services) s.init()]);
  }

  @override
  Future<void> signIn([AuthProvider provider = AuthProvider.google]) =>
      _for(provider).signIn(provider);

  @override
  Future<void> signOut() async {
    final services = [for (final s in _services) s.signOut()];
    await Future.wait(services);
  }

  @override
  Future<String?> deletionAuthorization() async =>
      _active?.deletionAuthorization();

  @override
  Widget? buildSignInButton([AuthProvider provider = AuthProvider.google]) =>
      _for(provider).buildSignInButton(provider);

  @override
  void dispose() {
    for (final s in _services) {
      s.removeListener(_changed);
      s.dispose();
    }
    super.dispose();
  }
}
