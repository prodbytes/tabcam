import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/main.dart';
import 'package:tabcam_app/screens/messages.dart';

const _banner = Key('top-message');

/// A page as the app's: a FAB, a bottom navigation bar, and buttons that
/// show messages.
class _Page extends StatefulWidget {
  const _Page({this.opened});

  final VoidCallback? opened;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  int _tab = 0;
  int _stars = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Riffs, $_stars stars'),
      actions: [
        IconButton(
          tooltip: 'Star',
          icon: const Icon(Icons.star),
          onPressed: () => setState(() => _stars++),
        ),
      ],
    ),
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Tab $_tab'),
          TextButton(
            onPressed: () => showMessage(
              context,
              'Saved "Riff in E" (1 page)',
              action: MessageAction(
                label: 'Open',
                onPressed: widget.opened ?? () {},
              ),
            ),
            child: const Text('save'),
          ),
          TextButton(
            onPressed: () => showMessage(context, 'Link copied'),
            child: const Text('copy'),
          ),
          TextButton(
            onPressed: () => replaceMessage(context, 'Tab copied'),
            child: const Text('replace'),
          ),
          TextButton(
            onPressed: () => showMessage(
              context,
              'Checking it is part of TabCam Premium.',
              action: MessageAction(label: 'Upgrade', onPressed: () {}),
              persist: true,
            ),
            child: const Text('offer'),
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                content: TextButton(
                  onPressed: () => showMessage(context, 'From the dialog'),
                  child: const Text('in dialog'),
                ),
              ),
            ),
            child: const Text('dialog'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Second')),
                  body: const Text('second page'),
                ),
              ),
            ),
            child: const Text('push'),
          ),
        ],
      ),
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () {},
      child: const Icon(Icons.add),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) => setState(() => _tab = i),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
        NavigationDestination(icon: Icon(Icons.add), label: 'Capture'),
        NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
      ],
    ),
  );
}

Widget _app({bool host = true, VoidCallback? opened, Brightness? brightness}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness ?? Brightness.light),
      builder: host ? (context, child) => TopMessages(child: child!) : null,
      home: _Page(opened: opened),
    );

Future<void> _show(WidgetTester tester, String button) async {
  await tester.tap(find.text(button));
  // In: its time then starts.
  await tester.pumpAndSettle();
}

void main() {
  for (final host in [true, false]) {
    final how = host ? 'over the app' : 'on the root overlay';

    testWidgets('a message shows at the top, $how, moving nothing', (
      tester,
    ) async {
      await tester.pumpWidget(_app(host: host));
      final fab = tester.getRect(find.byType(FloatingActionButton));
      final bar = tester.getRect(find.byType(NavigationBar));
      final appBar = tester.getRect(find.byType(AppBar));
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

      await _show(tester, 'save');
      expect(find.textContaining('Riff in E'), findsOneWidget);
      final banner = tester.getRect(find.byKey(_banner));
      expect(banner.top, lessThan(screen.height / 4));
      // Under the app bar, 8 px below it, not over its buttons.
      expect(banner.top, appBar.bottom + messageGap);
      expect(banner.bottom, lessThan(bar.top));
      // Nothing moved for it, the FAB and the navigation bars least of all.
      expect(tester.getRect(find.byType(FloatingActionButton)), fab);
      expect(tester.getRect(find.byType(NavigationBar)), bar);
      expect(tester.getRect(find.byType(AppBar)), appBar);

      // The bottom navigation takes taps while it shows.
      await tester.tap(find.text('Profile'));
      await tester.pump();
      expect(find.text('Tab 2'), findsOneWidget);
      expect(find.textContaining('Riff in E'), findsOneWidget);

      // So does the app bar's action, at once.
      await tester.tap(find.byTooltip('Star'));
      await tester.pump();
      expect(find.text('Riffs, 1 stars'), findsOneWidget);
      expect(find.textContaining('Riff in E'), findsOneWidget);

      // Gone by itself after 4 s.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.textContaining('Riff in E'), findsNothing);
      expect(find.byKey(_banner), findsNothing);
    });

    testWidgets('one message at a time, $how', (tester) async {
      await tester.pumpWidget(_app(host: host));
      await _show(tester, 'copy');
      await tester.tap(find.text('save'));
      await tester.pump();
      // The second waits for the first.
      expect(find.text('Link copied'), findsOneWidget);
      expect(find.textContaining('Riff in E'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(find.text('Link copied'), findsNothing);
      expect(find.textContaining('Riff in E'), findsOneWidget);
      // Replacing: the one showing goes, and the new one shows.
      await tester.tap(find.text('replace'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Riff in E'), findsNothing);
      expect(find.text('Tab copied'), findsOneWidget);
      expect(find.byKey(_banner), findsOneWidget);
    });
  }

  testWidgets('its background is 42% transparent, its text opaque', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(_app(brightness: brightness));
      await _show(tester, 'save');
      final material = tester.widget<Material>(find.byKey(_banner));
      expect(material.color!.a, closeTo(0.58, 0.01));
      final scheme = Theme.of(tester.element(find.text('save'))).colorScheme;
      expect(
        material.color!.withValues(alpha: 1),
        isSameColorAs(scheme.inverseSurface),
      );
      final text = tester.widget<Text>(find.textContaining('Riff in E'));
      expect(text.style!.color!.a, 1);
      expect(text.style!.color, isSameColorAs(scheme.onInverseSurface));
      final open = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Open'),
      );
      expect(open.style!.foregroundColor!.resolve({})!.a, 1);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('its action runs and hides it; a tap or a swipe up hides it', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(_app(opened: () => opened++));
    await _show(tester, 'save');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.byKey(_banner), findsNothing);

    await _show(tester, 'copy');
    await tester.tap(find.text('Link copied'));
    await tester.pumpAndSettle();
    expect(find.byKey(_banner), findsNothing);

    await _show(tester, 'copy');
    await tester.fling(find.byKey(_banner), const Offset(0, -200), 1000);
    await tester.pumpAndSettle();
    expect(find.byKey(_banner), findsNothing);
  });

  testWidgets('wide screens get a compact message, centred', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await _show(tester, 'save');
    final banner = tester.getRect(find.byKey(_banner));
    expect(banner.width, lessThanOrEqualTo(560));
    expect(banner.center.dx, closeTo(800, 1));
  });

  testWidgets('it stays under the status bar and the app bar', (tester) async {
    // A 24 px status bar and 30 px cut-outs on the sides.
    tester.view.padding = const FakeViewPadding(top: 72, left: 90, right: 90);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    await _show(tester, 'offer');
    final banner = tester.getRect(find.byKey(_banner));
    expect(tester.getRect(find.byType(AppBar)).bottom, 24 + kToolbarHeight);
    expect(banner.top, 24 + kToolbarHeight + 8);
    expect(banner.left, greaterThanOrEqualTo(30 + 12));
    expect(banner.right, lessThanOrEqualTo(screen.width - 30 - 12));
  });

  testWidgets('with an offer to keep, it stays until dismissed', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _show(tester, 'offer');
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade'), findsOneWidget);
    // The others wait for it, as they did for a SnackBar's.
    await tester.tap(find.text('copy'));
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Link copied'), findsNothing);
    await tester.tap(find.textContaining('TabCam Premium'));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade'), findsNothing);
    expect(find.text('Link copied'), findsOneWidget);
    // Replaced, it goes at once.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await _show(tester, 'offer');
    await _show(tester, 'replace');
    expect(find.text('Upgrade'), findsNothing);
    expect(find.text('Tab copied'), findsOneWidget);
  });

  testWidgets('shown from a dialog, it shows over it; it outlives a page', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.text('dialog'));
    await tester.pumpAndSettle();
    await _show(tester, 'in dialog');
    expect(find.text('From the dialog'), findsOneWidget);
    // Over the dialog's barrier: a tap on it reaches it.
    await tester.tap(find.text('From the dialog'));
    await tester.pumpAndSettle();
    expect(find.byKey(_banner), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    Navigator.of(tester.element(find.text('in dialog'))).pop();
    await tester.pumpAndSettle();

    // Shown, then a page opens over it: it shows on that page, then goes.
    await _show(tester, 'copy');
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(find.text('second page'), findsOneWidget);
    expect(find.text('Link copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byKey(_banner), findsNothing);

    // A long message, shown on that page, leaves its back button free.
    showMessage(
      tester.element(find.text('second page')),
      'Saved "A riff with a rather long name to fill the line" (2 pages, '
      '1 video, 1 link)',
      action: MessageAction(label: 'Open', onPressed: () {}),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_banner), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('second page'), findsNothing);
    expect(find.byKey(_banner), findsOneWidget);
  });

  testWidgets('nothing is left when the app goes while one shows', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _show(tester, 'save');
    await tester.tap(find.text('copy'));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(find.byKey(_banner), findsNothing);
  });

  testWidgets('in the app: "Saved" shows at the top, the navigation free', (
    tester,
  ) async {
    final library = Library(PlatformEventStore());
    await library.load();
    await tester.pumpWidget(TabCamApp(library: library));
    final bar = find.byType(NavigationBar);
    await tester.tap(find.descendant(of: bar, matching: find.text('Capture')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Link'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'example.com/riff');
    await tester.enterText(find.byType(TextField).last, 'Riff one');
    final barAt = tester.getRect(bar);
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    const saved = 'Saved "Riff one" (1 link)';
    expect(find.text(saved), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final banner = tester.getRect(find.byKey(_banner));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(banner.top, lessThan(screen.height / 4));
    expect(banner.top, greaterThan(tester.getRect(find.byType(AppBar)).bottom));
    expect(tester.getRect(bar), barAt);
    // Profile, from the navigation bar, while it shows.
    await tester.tap(find.descendant(of: bar, matching: find.text('Profile')));
    await tester.pumpAndSettle();
    expect(find.text('About'), findsOneWidget);
    expect(find.text(saved), findsOneWidget);
    // Gone after its 6 s, with the new card's outline.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text(saved), findsNothing);
  });
}
