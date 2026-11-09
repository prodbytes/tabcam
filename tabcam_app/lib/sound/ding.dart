/// A short, soft ding for when something the user waited on is done
/// (Rescan's read): [playDing] plays it, and [primeDing], called from the
/// tap that starts the wait, lets the browser play it when the wait ends.
/// On Android a notification sound, on iOS a system sound (both quiet with
/// the phone on silent), on the web Web Audio. The sound is made in
/// [ding_sound.dart](ding_sound.dart).
library;

export 'ding_io.dart' if (dart.library.js_interop) 'ding_web.dart';
