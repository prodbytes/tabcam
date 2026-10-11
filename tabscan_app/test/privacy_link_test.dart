import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:tabscan_app/screens/home_screen.dart';
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
  test('the privacy policy is on the production site', () {
    expect(privacyPolicyUrl.toString(), 'https://tabscan.nu01.com/privacy');
  });

  testWidgets('About opens the privacy policy', (tester) async {
    final launcher = _FakeLauncher();
    UrlLauncherPlatform.instance = launcher;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ProfileView())),
    );
    expect(find.text('Licenses'), findsOneWidget);
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(launcher.opened, ['https://tabscan.nu01.com/privacy']);
  });
}
