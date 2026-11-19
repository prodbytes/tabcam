import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/out_delays.dart';
import 'package:tabcam_app/library/capture_event.dart';
import 'package:tabcam_app/library/event_store_memory.dart';
import 'package:tabcam_app/library/library.dart';
import 'package:tabcam_app/library/meta_names.dart';

void main() {
  test('the meta\'s name is a device setting the apps\' store takes', () {
    expect(OutDelays.metaName, 'outdelays');
    expect(checkId(OutDelays.metaName), OutDelays.metaName);
    expect(MetaNames.deviceSettings, contains(OutDelays.metaName));
  });

  test('none kept: none read', () async {
    final library = Library(PlatformEventStore());
    expect(await OutDelays.read(library), isEmpty);
  });

  test('kept per output, read back by another library on the same '
      'store; zeros left out, each within its range', () async {
    final store = PlatformEventStore();
    await OutDelays.write(Library(store), {
      'bluetooth|3f9a1c07': 170,
      'wired|': 0,
      'usb|ab12cd34': 9000,
      'bluetooth|0000beef': -900,
    });
    expect(jsonDecode((await Library(store).readMeta('outdelays'))!), {
      'v': 1,
      'ms': {
        'bluetooth|3f9a1c07': 170,
        'usb|ab12cd34': OutDelays.most,
        'bluetooth|0000beef': OutDelays.least,
      },
    });
    expect(await OutDelays.read(Library(store)), {
      'bluetooth|3f9a1c07': 170,
      'usb|ab12cd34': 2500,
      'bluetooth|0000beef': -500,
    });
  });

  test('read leniently: what isn\'t a number of ms is left out', () async {
    final library = Library(PlatformEventStore());
    await library.writeMeta(
      'outdelays',
      jsonEncode({
        'v': 2,
        'ms': {'bluetooth|a': 120.6, 'wired|': 'x', 'usb|': 0, 'x|': 4000},
        'newer': true,
      }),
    );
    expect(await OutDelays.read(library), {'bluetooth|a': 121, 'x|': 2500});
    await library.writeMeta('outdelays', '[1, 2]');
    expect(await OutDelays.read(library), isEmpty);
    await library.writeMeta('outdelays', '{not json');
    expect(await OutDelays.read(library), isEmpty);
  });
}
