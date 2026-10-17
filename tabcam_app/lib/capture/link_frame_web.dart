import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'link_frame.dart';

/// The web's link frame: an iframe. A YouTube video's is its embedded
/// player, told to play, pause and stop with messages; another site's page
/// can't be told anything.
Widget buildLinkFrame(LinkFrameController controller) =>
    _IframeFrame(controller: controller);

var _views = 0;

class _IframeFrame extends StatefulWidget {
  const _IframeFrame({required this.controller});

  final LinkFrameController controller;

  @override
  State<_IframeFrame> createState() => _IframeFrameState();
}

class _IframeFrameState extends State<_IframeFrame> {
  late final String _view = 'tabcam-link-frame-${_views++}';

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    final id = c.youTubeId;
    final iframe = web.HTMLIFrameElement()
      ..src = id != null
          ? youTubeEmbed(
              id,
              web.window.location.origin,
              autoplay: c.autoplay,
            ).toString()
          : c.url.toString()
      ..allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen'
      ..referrerPolicy = 'strict-origin-when-cross-origin';
    iframe.style
      ..border = 'none'
      ..width = '100%'
      ..height = '100%';
    ui_web.platformViewRegistry.registerViewFactory(_view, (_) => iframe);
    if (id != null) {
      // The video's time, for « and »: it says it once asked to.
      iframe.onLoad.listen(
        (_) =>
            iframe.contentWindow?.postMessage(youTubeListening.toJS, '*'.toJS),
      );
      _onMessage = (web.MessageEvent event) {
        if (event.source != iframe.contentWindow) return;
        final data = event.data;
        if (youTubeTime(data.isA<JSString>() ? (data as JSString).toDart : null)
            case final time?) {
          _time = time;
        }
      }.toJS;
      web.window.addEventListener('message', _onMessage);
      c.command = (command) async {
        for (final message in youTubeCommands(command, at: _time)) {
          iframe.contentWindow?.postMessage(message.toJS, '*'.toJS);
        }
      };
    }
  }

  /// The YouTube video's time, in seconds, as it last said.
  double _time = 0;
  JSFunction? _onMessage;

  @override
  void dispose() {
    if (_onMessage case final listener?) {
      web.window.removeEventListener('message', listener);
    }
    widget.controller.command = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _view);
}
