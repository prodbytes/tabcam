import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../l10n/language.dart';
import 'auth_service.dart';
import 'email_config.dart';
import 'email_store.dart';
import 'jwt.dart';
import 'saved_session.dart';

/// An error from the user pool: its type (`CodeMismatchException`, …).
class EmailIdpException implements Exception {
  const EmailIdpException(this.type, this.message);

  final String type;
  final String message;

  @override
  String toString() => '$type: $message';
}

/// The user pool's public calls (no AWS credentials: only the app client
/// ID): [HttpEmailIdp], or a fake in tests.
abstract interface class EmailIdp {
  /// Calls [operation] (`SignUp`, `InitiateAuth`, …) with [body]; its
  /// answer, or [EmailIdpException].
  Future<Map<String, Object?>> call(
    String operation,
    Map<String, Object?> body,
  );
}

/// [EmailIdp] over HTTPS: Cognito's JSON API.
class HttpEmailIdp implements EmailIdp {
  HttpEmailIdp({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<Map<String, Object?>> call(
    String operation,
    Map<String, Object?> body,
  ) async {
    final response = await _client.post(
      Uri.https('cognito-idp.${EmailConfig.region}.amazonaws.com', '/'),
      headers: {
        'content-type': 'application/x-amz-json-1.1',
        'x-amz-target': 'AWSCognitoIdentityProviderService.$operation',
      },
      body: jsonEncode(body),
    );
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    final Map<String, Object?> json = decoded is Map
        ? decoded.cast<String, Object?>()
        : const {};
    if (response.statusCode != 200) {
      final type = '${json['__type'] ?? 'Error ${response.statusCode}'}';
      throw EmailIdpException(
        type.split('#').last,
        '${json['message'] ?? json['Message'] ?? ''}',
      );
    }
    return json;
  }
}

/// Where a sign-in with email stands.
enum EmailStep {
  /// Asking for the address.
  address,

  /// A code was sent: asking for it.
  code,
}

/// Sign in with email: the address, then a one-time code emailed to it
/// (the tabcam-email user pool's EMAIL_OTP). A new address signs up (no
/// password) and confirms with its code; a known one asks for a code. The
/// email also has a link (`…/app/?signin-code=<code>`) that fills the code
/// in ([completeWithLink]).
///
/// Signed in, the session (the user, the ID token and the refresh token) is
/// kept ([EmailStore]) and the ID token renewed five minutes before it
/// expires (they last an hour; the refresh token 30 days). A sign-in
/// waiting for its code is kept too, for the 15 minutes the pool gives it,
/// so the link works even if the app was closed meanwhile.
class EmailAuthService extends AuthService {
  EmailAuthService({
    EmailIdp? idp,
    this._store = const EmailStore(),
    DateTime Function()? now,
    this.site,
  }) : _idp = idp ?? HttpEmailIdp(),
       _now = now ?? DateTime.now;

  final EmailIdp _idp;
  final EmailStore _store;
  final DateTime Function() _now;

  /// The site the email's link goes to (the web app's own origin); null:
  /// tabcam.nu01.com.
  final String? site;

  AuthUser? _user;
  String? _idToken;
  String? _refreshToken;
  bool _checking = true;
  String? _error;
  bool _busy = false;
  Timer? _refresh;

  /// The sign-in waiting for its code: the address, the pool's session,
  /// and whether it's a new address confirming (sign-up) or a known one
  /// signing in.
  ({String email, String session, bool signUp, DateTime at})? _pending;

  /// How long the pool keeps a sign-in waiting for its code.
  static const _waits = Duration(minutes: 15);

  @override
  AuthUser? get user => _user;

  @override
  String? get idToken => _idToken;

  @override
  List<AuthProvider> get providers => const [AuthProvider.email];

  @override
  bool get checking => _checking;

  @override
  bool get available => EmailConfig.enabled;

  @override
  String? get unavailableReason =>
      available ? null : appL10n.emailSignInUnavailable;

  @override
  String? get error => _error;

  /// A call to the pool is under way.
  bool get busy => _busy;

  /// Where the sign-in stands: the address, or the code once one is sent.
  EmailStep get step => _pending == null ? EmailStep.address : EmailStep.code;

  /// The address the code went to.
  String? get pendingEmail => _pending?.email;

  @override
  Future<void> init() async {
    final data = _decode(await _store.load());
    final pending = data['pending'];
    if (pending is Map) {
      final at = DateTime.tryParse('${pending['at']}');
      final email = pending['email'], session = pending['session'];
      if (at != null &&
          email is String &&
          session is String &&
          _now().difference(at) < _waits) {
        _pending = (
          email: email,
          session: session,
          signUp: pending['signUp'] == true,
          at: at,
        );
      }
    }
    final saved = data['session'];
    final refresh = data['refresh'];
    if (saved is String && refresh is String) {
      _refreshToken = refresh;
      final restored = SavedSession.decode(saved, now: _now());
      if (restored != null) {
        _user = restored.user;
        _idToken = restored.idToken;
        _scheduleRefresh(restored.idToken);
      } else {
        // The ID token has expired: a new one from the refresh token.
        await _renew(quiet: true);
      }
    }
    _checking = false;
    notifyListeners();
  }

  /// Email sign-in has no single call: [EmailSignInDialog] asks for the
  /// address ([sendCode]) and the code ([verify]).
  @override
  Future<void> signIn([AuthProvider provider = AuthProvider.email]) async {}

  static final _address = RegExp(r'^[^@\s]{1,64}@[^@\s]{1,189}\.[^@\s]{2,}$');

  /// Emails a code to [email]: signs a new address up, or starts a known
  /// one's sign-in. True once sent.
  Future<bool> sendCode(String email) async {
    email = email.trim().toLowerCase();
    if (!_address.hasMatch(email)) {
      _fail(appL10n.emailSignInBadAddress);
      return false;
    }
    return _run(() async {
      final meta = _metadata();
      try {
        final up = await _idp.call('SignUp', {
          'ClientId': EmailConfig.clientId,
          'Username': email,
          'UserAttributes': [
            {'Name': 'email', 'Value': email},
          ],
          'ClientMetadata': meta,
        });
        _wait(email, '${up['Session'] ?? ''}', signUp: true);
      } on EmailIdpException catch (e) {
        if (e.type != 'UsernameExistsException') rethrow;
        await _startSignIn(email, meta);
      }
    });
  }

  /// A known address: a code to sign in with, or, if it never confirmed,
  /// its confirmation code again.
  Future<void> _startSignIn(String email, Map<String, String> meta) async {
    try {
      final r = await _idp.call('InitiateAuth', {
        'ClientId': EmailConfig.clientId,
        'AuthFlow': 'USER_AUTH',
        'AuthParameters': {
          'USERNAME': email,
          'PREFERRED_CHALLENGE': 'EMAIL_OTP',
        },
        'ClientMetadata': meta,
      });
      if (r['ChallengeName'] != 'EMAIL_OTP') {
        throw EmailIdpException('UnexpectedChallenge', '${r['ChallengeName']}');
      }
      _wait(email, '${r['Session']}', signUp: false);
    } on EmailIdpException catch (e) {
      if (e.type != 'UserNotConfirmedException') rethrow;
      await _idp.call('ResendConfirmationCode', {
        'ClientId': EmailConfig.clientId,
        'Username': email,
        'ClientMetadata': meta,
      });
      _wait(email, '', signUp: true);
    }
  }

  /// Sends a new code to the same address.
  Future<bool> resend() async {
    final pending = _pending;
    if (pending == null) return false;
    return sendCode(pending.email);
  }

  /// Back to asking for the address.
  Future<void> otherAddress() async {
    _pending = null;
    _error = null;
    await _save();
    notifyListeners();
  }

  /// Signs in with [code], the one emailed. True once signed in.
  Future<bool> verify(String code) async {
    final pending = _pending;
    code = code.replaceAll(RegExp(r'\s'), '');
    if (pending == null) return false;
    if (!RegExp(r'^\d{6,8}$').hasMatch(code)) {
      _fail(appL10n.emailSignInBadCode);
      return false;
    }
    return _run(() async {
      final Map<String, Object?> result;
      if (pending.signUp) {
        final confirmed = await _idp.call('ConfirmSignUp', {
          'ClientId': EmailConfig.clientId,
          'Username': pending.email,
          'ConfirmationCode': code,
          if (pending.session.isNotEmpty) 'Session': pending.session,
          'ClientMetadata': _metadata(),
        });
        final session = confirmed['Session'];
        if (session is String && session.isNotEmpty) {
          // Confirmed: signed in at once, without another code.
          result = await _idp.call('InitiateAuth', {
            'ClientId': EmailConfig.clientId,
            'AuthFlow': 'USER_AUTH',
            'AuthParameters': {'USERNAME': pending.email},
            'Session': session,
          });
        } else {
          // Confirmed, but no session to go on with: a sign-in code next.
          await _startSignIn(pending.email, _metadata());
          return;
        }
      } else {
        result = await _idp.call('RespondToAuthChallenge', {
          'ClientId': EmailConfig.clientId,
          'ChallengeName': 'EMAIL_OTP',
          'Session': pending.session,
          'ChallengeResponses': {
            'USERNAME': pending.email,
            'EMAIL_OTP_CODE': code,
          },
        });
      }
      await _signedIn(result);
    });
  }

  /// The email's link: its code, for the sign-in waiting here. False when
  /// none is waiting (another device's, or an old link).
  Future<bool> completeWithLink(String code) async {
    if (_pending == null || _user != null) return false;
    return verify(code);
  }

  Future<void> _signedIn(Map<String, Object?> result) async {
    final auth = result['AuthenticationResult'];
    if (auth is! Map) {
      throw const EmailIdpException('NoTokens', 'no tokens in the answer');
    }
    final idToken = auth['IdToken'];
    final refresh = auth['RefreshToken'];
    if (idToken is! String) {
      throw const EmailIdpException('NoTokens', 'no ID token in the answer');
    }
    final claims = jwtClaims(idToken) ?? const {};
    final email = '${claims['email'] ?? _pending?.email ?? ''}'.toLowerCase();
    _user = AuthUser(
      id: '${claims['sub'] ?? email}',
      email: email,
      provider: AuthProvider.email,
    );
    _idToken = idToken;
    if (refresh is String) _refreshToken = refresh;
    _pending = null;
    _scheduleRefresh(idToken);
    await _save();
  }

  /// A new ID token from the refresh token; signed out when it's refused.
  Future<void> _renew({bool quiet = false}) async {
    final refresh = _refreshToken;
    if (refresh == null) return;
    try {
      final r = await _idp.call('InitiateAuth', {
        'ClientId': EmailConfig.clientId,
        'AuthFlow': 'REFRESH_TOKEN_AUTH',
        'AuthParameters': {'REFRESH_TOKEN': refresh},
      });
      await _signedIn(r);
    } on EmailIdpException catch (e) {
      debugPrint('TabCam: the email session ended: $e');
      await _forget();
      if (!quiet) _error = appL10n.emailSignInExpired;
    } catch (e) {
      // Offline: try again in a minute; the token may still be good.
      debugPrint('TabCam: renewing the email session failed: $e');
      _refresh?.cancel();
      _refresh = Timer(const Duration(minutes: 1), _renew);
    }
    notifyListeners();
  }

  void _scheduleRefresh(String token) {
    _refresh?.cancel();
    final wait = SavedSession.refreshIn(token, now: _now());
    if (wait == null) return;
    _refresh = Timer(wait, _renew);
  }

  @override
  Future<void> signOut() async {
    final refresh = _refreshToken;
    await _forget();
    notifyListeners();
    if (refresh != null) {
      // The refresh token is revoked too, so it can't sign in again.
      unawaited(
        _idp
            .call('RevokeToken', {
              'ClientId': EmailConfig.clientId,
              'Token': refresh,
            })
            .then(
              (_) {},
              onError: (Object e) {
                debugPrint('TabCam: revoking the email session failed: $e');
              },
            ),
      );
    }
  }

  Future<void> _forget() async {
    _refresh?.cancel();
    _user = null;
    _idToken = null;
    _refreshToken = null;
    await _save();
  }

  void _wait(String email, String session, {required bool signUp}) {
    _pending = (email: email, session: session, signUp: signUp, at: _now());
  }

  Map<String, String> _metadata() => {
    'lang': appL10n.localeName.split('_').first,
    'site': ?site,
  };

  /// Runs a call to the pool, [busy] meanwhile; its error, said in words.
  Future<bool> _run(Future<void> Function() call) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await call();
      await _save();
      return true;
    } on EmailIdpException catch (e) {
      debugPrint('TabCam: sign in with email: $e');
      _error = switch (e.type) {
        'CodeMismatchException' ||
        'ExpiredCodeException' => appL10n.emailSignInBadCode,
        'NotAuthorizedException' => appL10n.emailSignInBadCode,
        'LimitExceededException' ||
        'TooManyRequestsException' ||
        'TooManyFailedAttemptsException' ||
        'CodeDeliveryFailureException' => appL10n.emailSignInTooMany,
        'InvalidParameterException' => appL10n.emailSignInBadAddress,
        _ => appL10n.emailSignInFailed(e.message.isEmpty ? e.type : e.message),
      };
      return false;
    } catch (e) {
      debugPrint('TabCam: sign in with email: $e');
      _error = appL10n.emailSignInFailed('$e');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _fail(String message) {
    _error = message;
    notifyListeners();
  }

  Future<void> _save() {
    final (user, token, refresh, pending) = (
      _user,
      _idToken,
      _refreshToken,
      _pending,
    );
    if (user == null && pending == null) return _store.save(null);
    return _store.save(
      jsonEncode({
        if (user != null && token != null && refresh != null) ...{
          'session': SavedSession(user: user, idToken: token).encode(),
          'refresh': refresh,
        },
        if (pending != null)
          'pending': {
            'email': pending.email,
            'session': pending.session,
            'signUp': pending.signUp,
            'at': pending.at.toIso8601String(),
          },
      }),
    );
  }

  static Map<String, Object?> _decode(String? data) {
    if (data == null) return const {};
    try {
      final m = jsonDecode(data);
      return m is Map ? m.cast<String, Object?>() : const {};
    } catch (_) {
      return const {};
    }
  }

  /// "Sign in with email": opens [EmailSignInDialog].
  @override
  Widget? buildSignInButton([AuthProvider provider = AuthProvider.email]) =>
      _EmailButton(service: this);

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }
}

class _EmailButton extends StatelessWidget {
  const _EmailButton({required this.service});

  final EmailAuthService service;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const Key('sign-in-email'),
    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
    onPressed: service.checking
        ? null
        : () => showDialog<void>(
            context: context,
            builder: (_) => EmailSignInDialog(service: service),
          ),
    icon: const Icon(Icons.mail_outline),
    label: Text(context.l10n.emailSignInButton),
  );
}

/// Sign in with email's dialog: the address and Send code, then the code
/// and Sign in (or Send a new code, or Use another address). It closes
/// once signed in.
class EmailSignInDialog extends StatefulWidget {
  const EmailSignInDialog({super.key, required this.service});

  final EmailAuthService service;

  @override
  State<EmailSignInDialog> createState() => _EmailSignInDialogState();
}

class _EmailSignInDialogState extends State<EmailSignInDialog> {
  final _address = TextEditingController();
  final _code = TextEditingController();

  EmailAuthService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _address.text = _service.pendingEmail ?? '';
    _service.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    if (_service.user != null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (await _service.sendCode(_address.text)) _code.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = _service.busy;
    final code = _service.step == EmailStep.code;
    final error = _service.error;
    return AlertDialog(
      title: Text(l10n.emailSignInTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!code) ...[
              Text(l10n.emailSignInIntro),
              const SizedBox(height: 12),
              TextField(
                key: const Key('email-sign-in-address'),
                controller: _address,
                autofocus: true,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.emailSignInAddress,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _send(),
              ),
            ] else ...[
              Text(l10n.emailSignInSent(_service.pendingEmail ?? '')),
              const SizedBox(height: 12),
              TextField(
                key: const Key('email-sign-in-code'),
                controller: _code,
                autofocus: true,
                enabled: !busy,
                keyboardType: TextInputType.number,
                autofillHints: const [AutofillHints.oneTimeCode],
                maxLength: 8,
                style: const TextStyle(fontSize: 24, letterSpacing: 6),
                decoration: InputDecoration(
                  labelText: l10n.emailSignInCode,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
                onSubmitted: (value) => _service.verify(value),
              ),
              Wrap(
                children: [
                  TextButton(
                    key: const Key('email-sign-in-resend'),
                    onPressed: busy ? null : _service.resend,
                    child: Text(l10n.emailSignInResend),
                  ),
                  TextButton(
                    key: const Key('email-sign-in-other'),
                    onPressed: busy ? null : _service.otherAddress,
                    child: Text(l10n.emailSignInOther),
                  ),
                ],
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                key: const Key('email-sign-in-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          key: const Key('email-sign-in-go'),
          onPressed: busy
              ? null
              : code
              ? () => _service.verify(_code.text)
              : _send,
          child: Text(code ? l10n.emailSignInVerify : l10n.emailSignInSend),
        ),
      ],
    );
  }
}
