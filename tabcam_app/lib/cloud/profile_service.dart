import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cloud_sync.dart';
import 'share_api.dart';

/// The signed-in user's profile ([Profile]), as the share API has it:
/// asked for at each sign-in and when the Profile tab opens. Linking
/// another sign-in, or unlinking one, changes whose folder this sign-in
/// reaches, so sync starts over with new credentials, and [onChanged] runs
/// (the Premium check: the profile's roles are every address's).
class ProfileService extends ChangeNotifier {
  ProfileService({required this.sync, this.onChanged});

  final CloudSync sync;
  final VoidCallback? onChanged;

  ShareApi get _api => sync.shares!;

  Profile? _profile;

  /// Null signed out, or until the API has answered.
  Profile? get profile => _profile;

  bool _loading = false;
  bool get loading => _loading;

  /// Why the last request failed, if it did.
  String? get error => _error;
  String? _error;

  String? _userId;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    sync.auth.addListener(_onAuth);
    _onAuth();
  }

  @override
  void dispose() {
    if (_started) sync.auth.removeListener(_onAuth);
    super.dispose();
  }

  void _onAuth() {
    final user = sync.auth.user?.id;
    if (user == _userId) return;
    _userId = user;
    _profile = null;
    _error = null;
    notifyListeners();
    if (user != null) unawaited(refresh());
  }

  Future<T?> _run<T>(Future<T> Function(String token) call) async {
    final token = sync.auth.idToken;
    if (token == null) return null;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      return await call(token);
    } on ShareApiException catch (e) {
      _error = e.message;
      debugPrint('TabCam: profile: ${e.statusCode} $e');
      rethrow;
    } on Object catch (e) {
      _error = '$e';
      debugPrint('TabCam: profile failed: $e');
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Asks for the profile again.
  Future<void> refresh() async {
    try {
      final p = await _run(_api.profile);
      if (p != null) _profile = p;
    } on Object {
      // Kept in [error].
    } finally {
      notifyListeners();
    }
  }

  /// A code for another sign-in to join this profile.
  Future<LinkCode?> makeCode() => _run(_api.linkCode);

  /// Joins the profile [code] is for. Throws [ShareApiException] (404: a
  /// wrong, used or expired code; 409: this sign-in can't move).
  Future<void> link(String code) async {
    final p = await _run((t) => _api.link(t, code));
    if (p != null) _profile = p;
    _moved();
  }

  /// Unlinks the account [id] (this sign-in, or another).
  Future<void> unlink(String id) async {
    final p = await _run((t) => _api.unlink(t, id));
    _profile = p;
    if (p == null) {
      // This sign-in left: it gets a profile of its own.
      _moved();
      await refresh();
    } else {
      notifyListeners();
    }
  }

  /// This sign-in's folder changed: new credentials, sync again.
  void _moved() {
    sync.credentials.clear();
    unawaited(sync.syncNow());
    onChanged?.call();
    notifyListeners();
  }
}
