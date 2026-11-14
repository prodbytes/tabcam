import 'package:camera/camera.dart';

import 'take_priority.dart';
import 'web_take_recorder_stub.dart'
    if (dart.library.js_interop) 'web_take_recorder.dart';

/// Records a take where the camera plugin's own recording isn't what Cam
/// wants (the web: the camera opens without sound, and the take is
/// recorded with the microphone Cam opens itself, see [TakePriority]).
/// The take is the camera and its sound as they are: the tab isn't in its
/// picture, it's kept with the take (`TakeLog`) and drawn by the editor.
abstract class TakeRecorder {
  /// Gets ready for takes when Cam opens (the web: opens the microphone,
  /// as [TakePriority.webMicConstraints], and keeps it open), so a take
  /// starts without waiting for it.
  Future<void> prepare();

  /// Whether a take would have sound: the microphone open (opened now if
  /// it isn't, which may ask the user), or the camera's own. Cam records
  /// no take without it: the take's sound matters most.
  Future<bool> hasSound();

  /// Should [start] fail, gives the camera's own recording the
  /// microphone's sound: the web's camera is opened without sound, so its
  /// stream gets the microphone's track. Whether the camera's stream has
  /// sound now.
  Future<bool> lendSoundToCamera();

  /// Starts recording the camera with the microphone's sound; returns
  /// once the recording has started (or, should it not say, soon after).
  Future<void> start();

  /// How long ago the recording started, in ms, as of now (the web: the
  /// MediaRecorder's `start` event, on the page's clock); null when it
  /// isn't known. Cam reads it as the take's clock starts: the take's lag
  /// (`TakeLog.lagMs`).
  double? msSinceStart();

  /// The microphones a take can record from (the browser's audio inputs,
  /// their names as it gives them), the system's default not among them.
  Future<List<TakeMic>> microphones();

  /// Takes record from microphone [id] from now on (null: the system's
  /// default); the microphone, if open, is opened again from it (else it
  /// is when it opens). Whether it opened from [id] (false: it couldn't,
  /// and the default is open instead). Not while recording.
  Future<bool> useMicrophone(String? id);

  /// The browser's; null elsewhere.
  static TakeRecorder? forPlatform() => webTakeRecorder();

  /// Stops, and gives the take.
  Future<XFile> stop();

  void dispose();
}

/// A microphone Cam can record takes from ([TakeRecorder.microphones],
/// `TakeSound.inputs`, `TakeAudio.inputs`): its [id], kept in Cam's
/// settings, and its [name] as the system gives it (empty when it gives
/// none: Cam names it then). [builtIn]: the phone's own (Android, whose
/// [name] is then where on the phone, such as "bottom", or empty).
class TakeMic {
  const TakeMic(this.id, this.name, {this.builtIn = false});

  final String id;
  final String name;
  final bool builtIn;

  /// From a channel's reply: a list of `{id, name, builtIn}` maps.
  static List<TakeMic> fromChannel(Object? reply) => [
    if (reply is List)
      for (final m in reply)
        if (m is Map && m['id'] is String && (m['id'] as String).isNotEmpty)
          TakeMic(
            m['id'] as String,
            m['name'] is String ? m['name'] as String : '',
            builtIn: m['builtIn'] == true,
          ),
  ];

  @override
  bool operator ==(Object other) =>
      other is TakeMic &&
      other.id == id &&
      other.name == name &&
      other.builtIn == builtIn;

  @override
  int get hashCode => Object.hash(id, name, builtIn);

  @override
  String toString() => 'TakeMic($id, $name${builtIn ? ', built in' : ''})';
}
