import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/link_frame.dart';

void main() {
  test('YouTube embed autoplays unless opened paused', () {
    expect(youTubeEmbed('abc', 'https://x').queryParameters['autoplay'], '1');
    expect(
      youTubeEmbed(
        'abc',
        'https://x',
        autoplay: false,
      ).queryParameters['autoplay'],
      '0',
    );
  });

  test('YouTube stop pauses, then seeks to the start', () {
    expect(youTubeCommands(LinkCommand.stop), [
      '{"event":"command","func":"pauseVideo","args":""}',
      '{"event":"command","func":"seekTo","args":[0,true]}',
    ]);
  });

  test('a link opened paused is not playing; stop pauses it', () async {
    final c = LinkFrameController(Uri.parse('https://x'), autoplay: false);
    expect(c.playing, isFalse);
    final sent = <LinkCommand>[];
    c.command = (command) async => sent.add(command);
    await c.toggle();
    expect(c.playing, isTrue);
    await c.stop();
    expect(c.playing, isFalse);
    expect(sent, [LinkCommand.play, LinkCommand.stop]);
    c.dispose();
  });

  test('YouTube « and » seek 10 seconds from its time, not before 0', () {
    expect(youTubeCommands(LinkCommand.forward, at: 42.5), [
      '{"event":"command","func":"seekTo","args":[52.5,true]}',
    ]);
    expect(youTubeCommands(LinkCommand.back, at: 42.5), [
      '{"event":"command","func":"seekTo","args":[32.5,true]}',
    ]);
    expect(youTubeCommands(LinkCommand.back, at: 4), [
      '{"event":"command","func":"seekTo","args":[0,true]}',
    ]);
  });

  test("a YouTube embed's time comes from its infoDelivery messages", () {
    expect(
      youTubeTime('{"event":"infoDelivery","info":{"currentTime":12.3}}'),
      12.3,
    );
    expect(youTubeTime('{"event":"onReady"}'), isNull);
    expect(youTubeTime('not json currentTime'), isNull);
    expect(youTubeTime(null), isNull);
  });

  test('a link\'s « and » are told to its frame', () async {
    final c = LinkFrameController(Uri.parse('https://x'));
    final sent = <LinkCommand>[];
    c.command = (command) async => sent.add(command);
    await c.skip(skipBy);
    await c.skip(-skipBy);
    expect(sent, [LinkCommand.forward, LinkCommand.back]);
    c.dispose();
  });
}
