import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tabcam_app/screens/home_screen.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Records the URLs the app opens instead of opening them.
class _FakeLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final opened = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    opened.add(url);
    return true;
  }
}

void main() {
  Widget profile({required bool store}) => MaterialApp(
    home: Scaffold(body: ProfileView(store: store)),
  );

  testWidgets('Android opens its steps, then the latest release', (
    tester,
  ) async {
    final launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    await tester.pumpWidget(profile(store: false));
    expect(find.text('Get the phone app'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Android'), 200);
    await tester.tap(find.text('Android'));
    await tester.pumpAndSettle();
    expect(find.text('Install on Android'), findsOneWidget);
    expect(find.textContaining('-android.apk'), findsOneWidget);
    await tester.tap(find.text('Open the release on GitHub'));
    await tester.pumpAndSettle();
    expect(launcher.opened, [
      'https://github.com/prodbytes/tabcam/releases/latest',
    ]);
  });

  testWidgets('iPhone opens its steps, then the build guide', (tester) async {
    final launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    await tester.pumpWidget(profile(store: false));
    await tester.scrollUntilVisible(find.text('iPhone'), 200);
    await tester.tap(find.text('iPhone'));
    await tester.pumpAndSettle();
    expect(find.text('Install on iPhone'), findsOneWidget);
    await tester.tap(find.text('Open the guide on GitHub'));
    await tester.pumpAndSettle();
    expect(launcher.opened, [
      'https://github.com/prodbytes/tabcam/blob/main/README.md#ios',
    ]);
  });

  testWidgets('a store app leaves the install links out', (tester) async {
    await tester.pumpWidget(profile(store: true));
    expect(find.text('Get the phone app'), findsNothing);
    expect(find.text('Android'), findsNothing);
  });
}
