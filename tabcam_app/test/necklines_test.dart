import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/recognition/necklines.dart';

void main() {
  test('each staff is a neckline, with the chords and label above it', () {
    const tab = '''
[Intro]
Am      C
e|--0-----0--|
B|--1-----1--|
G|--2-----0--|

e|--3--2--0--|
B|--3--3--1--|
la la la

[Outro]
e|--5--------|
B|--5--------|
''';
    expect(necklines(tab), [
      '[Intro]\nAm      C\ne|--0-----0--|\nB|--1-----1--|\nG|--2-----0--|',
      'e|--3--2--0--|\nB|--3--3--1--|',
      '[Outro]\ne|--5--------|\nB|--5--------|',
    ]);
  });

  test('text right under a staff heads the next one', () {
    expect(necklines('e|--1--1--|\nB|--2--2--|\nG chord\ne|--3--3--|'), [
      'e|--1--1--|\nB|--2--2--|',
      'G chord\ne|--3--3--|',
    ]);
  });

  test('without string lines, the blocks between blank lines', () {
    expect(necklines('Am  C  G\n\n\nF  G  Am\n'), ['Am  C  G', 'F  G  Am']);
  });

  test('no text, no necklines', () {
    expect(necklines(''), isEmpty);
    expect(necklines('\n  \n'), isEmpty);
  });
}
