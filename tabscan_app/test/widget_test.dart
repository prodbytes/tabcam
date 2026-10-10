import 'package:flutter_test/flutter_test.dart';
import 'package:tabscan_app/library/library.dart';
import 'package:tabscan_app/library/event_store_memory.dart';
import 'package:tabscan_app/main.dart';

void main() {
  testWidgets('an empty library offers to event', (tester) async {
    final library = Library(PlatformEventStore());
    await library.load();
    await tester.pumpWidget(TabScanApp(library: library));
    expect(find.text('No tabs yet'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });
}
