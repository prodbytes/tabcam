import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/auth/auth_service.dart';
import 'package:tabcam_app/auth/multi_auth_service.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/screens/quick_sign_in.dart';

import 'fakes.dart';

/// A provider whose sign-out takes until [release], noting when the
/// one-click sign-in was offered.
class _SlowSignOut extends FakeAuth {
  _SlowSignOut(this.log);

  final List<String> log;
  final Completer<void> release = Completer<void>();

  @override
  Future<void> signOut() async {
    await release.future;
    log.add('signed out');
    await super.signOut();
  }

  @override
  Future<void> offerQuickSignIn() async {
    log.add('offered');
    await super.offerQuickSignIn();
  }
}

void main() {
  Future<Library> library() async {
    final library = Library(PlatformEventStore());
    await library.load();
    return library;
  }

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  test('signs in with Apple on iOS, Google elsewhere, and not with email '
      'alone', () {
    const all = [AuthProvider.apple, AuthProvider.google, AuthProvider.email];
    expect(
      QuickSignIn.quickProvider(all, TargetPlatform.iOS),
      AuthProvider.apple,
    );
    expect(
      QuickSignIn.quickProvider(all, TargetPlatform.android),
      AuthProvider.google,
    );
    expect(
      QuickSignIn.quickProvider(const [
        AuthProvider.google,
        AuthProvider.email,
      ], TargetPlatform.iOS),
      AuthProvider.google,
    );
    expect(
      QuickSignIn.quickProvider(const [
        AuthProvider.apple,
      ], TargetPlatform.android),
      AuthProvider.apple,
    );
    expect(
      QuickSignIn.quickProvider(const [
        AuthProvider.email,
      ], TargetPlatform.android),
      isNull,
    );
  });

  testWidgets('the welcome has the one-click sign-in at the top right, and '
      'one tap signs in', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(TabCamApp(library: await library(), auth: auth));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('welcome')), findsOneWidget);
    final quick = find.byKey(const Key('quick-sign-in-google'));
    expect(quick, findsOneWidget);
    // Top right, above the welcome's own buttons.
    final screen = tester.getSize(find.byKey(const Key('welcome')));
    final box = tester.getRect(quick);
    expect(box.right, greaterThan(screen.width - 40));
    expect(box.top, lessThan(kToolbarHeight));
    expect(
      box.top,
      lessThan(tester.getTopLeft(find.byKey(const Key('sign-in-google'))).dy),
    );
    expect(find.text('Sign in with Google'), findsNWidgets(2));

    await tester.tap(quick);
    expect(auth.signIns, [AuthProvider.google]);

    // Signed in: gone, with the welcome.
    auth.signInAs('ana');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('quick-sign-in')), findsNothing);
  });

  testWidgets('on a phone it is an icon alone', (tester) async {
    phone(tester);
    final auth = FakeAuth();
    await tester.pumpWidget(TabCamApp(library: await library(), auth: auth));
    await tester.pumpAndSettle();
    final quick = find.byKey(const Key('quick-sign-in-google'));
    expect(quick, findsOneWidget);
    expect(tester.getSize(quick).width, lessThan(60));
    expect(find.byTooltip('Sign in with Google'), findsOneWidget);
    await tester.tap(quick);
    expect(auth.signIns, [AuthProvider.google]);
  });

  testWidgets('on iOS it is Sign in with Apple', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final auth = FakeAuth(
        offered: const [AuthProvider.apple, AuthProvider.google],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(actions: [QuickSignIn(auth: auth)]),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('quick-sign-in-apple')));
      expect(auth.signIns, [AuthProvider.apple]);
      expect(find.byKey(const Key('quick-sign-in-google')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('nothing with email alone, nor without sign-in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              QuickSignIn(auth: FakeAuth(offered: const [AuthProvider.email])),
              const QuickSignIn(),
            ],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('quick-sign-in')), findsNothing);
  });

  testWidgets('signing out offers the one-click sign-in again; launching '
      'signed out leaves it to the sign-in', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(TabCamApp(library: await library(), auth: auth));
    await tester.pumpAndSettle();
    // At launch the sign-in's init offers it.
    expect(auth.offers, 0);

    auth.signInAs('ana');
    await tester.pumpAndSettle();
    expect(auth.offers, 0);

    await auth.signOut();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('welcome')), findsOneWidget);
    expect(auth.offers, 1);
  });

  test(
    'several providers offer it only once every one has signed out',
    () async {
      final log = <String>[];
      final slow = _SlowSignOut(log);
      final other = FakeAuth();
      final auth = MultiAuthService([slow, other]);
      other.signInAs('ana');
      expect(auth.user, isNotNull);

      final signingOut = auth.signOut();
      // The other provider is out already; the slow one isn't.
      final offered = auth.offerQuickSignIn();
      await Future<void>.delayed(Duration.zero);
      expect(log, isEmpty);
      slow.release.complete();
      await signingOut;
      await offered;
      expect(log, ['signed out', 'offered']);
      expect(other.offers, 1);
    },
  );

  test('signed in, nothing is offered', () async {
    final google = FakeAuth();
    final auth = MultiAuthService([google, FakeAuth()]);
    google.signInAs('ana');
    await auth.offerQuickSignIn();
    expect(google.offers, 0);
  });
}
