import 'package:flutter/foundation.dart';

/// A file format Download makes of a video's edit.
enum EditFormat {
  /// H.264 (and AAC) in MP4: what the phones make, and the browsers that
  /// record MP4.
  mp4('MP4', 'mp4', 'video/mp4'),

  /// WebM (VP9 or VP8, Opus): the browsers that can't record MP4
  /// (Firefox).
  webm('WebM', 'webm', 'video/webm'),

  /// AAC in an MP4 file: the sound alone, on the phones and in the
  /// browsers that encode AAC.
  m4a('M4A', 'm4a', 'audio/mp4'),

  /// 16-bit PCM: the sound alone where AAC can't be made (Firefox).
  wav('WAV', 'wav', 'audio/wav');

  const EditFormat(this.label, this.extension, this.mimeType);

  /// Its name, as the Download menu says it.
  final String label;

  /// Its file's extension, without the dot.
  final String extension;

  /// Its file's MIME type.
  final String mimeType;

  /// The format of a file the browser recorded as [mimeType] (with or
  /// without its codecs): MP4, or WebM for anything else.
  static EditFormat recorded(String mimeType) =>
      mimeType.trim().toLowerCase().startsWith('video/mp4') ? mp4 : webm;
}

/// What Download makes here: the video's format and its sound's alone.
@immutable
class EditFormats {
  const EditFormats({this.video = EditFormat.mp4, this.sound = EditFormat.m4a});

  /// What the phones make, and the browsers that record MP4 and encode
  /// AAC: MP4 and M4A.
  static const standard = EditFormats();

  final EditFormat video;
  final EditFormat sound;

  @override
  bool operator ==(Object other) =>
      other is EditFormats && other.video == video && other.sound == sound;

  @override
  int get hashCode => Object.hash(video, sound);

  @override
  String toString() => 'EditFormats(${video.label}, ${sound.label})';

  /// Whether a video file with [extension], unchanged, downloads as it
  /// is rather than made again: when it's already MPEG-4 (`mp4`, or
  /// `m4v`, the same file named for iTunes), or already in the [video]
  /// format made here (a WebM where the browser records WebM).
  bool keepsAsIs(String? extension) {
    final e = extension?.toLowerCase();
    return e == 'mp4' || e == 'm4v' || e == video.extension;
  }
}

/// The MediaRecorder types the browser's editor records a video as, best
/// first: H.264 and AAC in MP4 (the level is the browser's to raise for a
/// larger frame), MP4 with the codecs the browser picks, then WebM where
/// MP4 can't be recorded (Firefox).
const List<String> videoRecorderTypes = [
  'video/mp4;codecs=avc1.42E01E,mp4a.40.2',
  'video/mp4;codecs=avc1,mp4a.40.2',
  'video/mp4',
  'video/webm;codecs=vp9,opus',
  'video/webm;codecs=vp8,opus',
  'video/webm',
];

/// The first of [videoRecorderTypes] that [supported] (the browser's
/// `MediaRecorder.isTypeSupported`) says it records; null when none, and
/// the recorder picks.
String? videoRecorderType(bool Function(String type) supported) {
  for (final type in videoRecorderTypes) {
    if (supported(type)) return type;
  }
  return null;
}

/// The MediaRecorder type the sound alone is recorded as, in real time,
/// where AAC can't be encoded faster (an older Safari): AAC in MP4 only,
/// as a plain `audio/mp4` may be Opus.
const soundRecorderType = 'audio/mp4;codecs=mp4a.40.2';

/// How the browser's editor makes the sound alone, best first.
enum WebSoundWay {
  /// WebCodecs' AudioEncoder, AAC, fed the offline mix (faster than it
  /// plays), written to an M4A here (`m4aBytes`).
  encoder,

  /// The offline mix played into a MediaRecorder as AAC in MP4, as long
  /// as it is.
  recorder,

  /// The offline mix as a WAV (`wavBytes`): where AAC can't be made.
  wav;

  /// The best way where the AudioEncoder can encode AAC ([encoder]) and
  /// MediaRecorder record it ([recorder]).
  static WebSoundWay best({required bool encoder, required bool recorder}) =>
      encoder
      ? WebSoundWay.encoder
      : recorder
      ? WebSoundWay.recorder
      : WebSoundWay.wav;

  /// The format it makes.
  EditFormat get format => this == wav ? EditFormat.wav : EditFormat.m4a;
}
