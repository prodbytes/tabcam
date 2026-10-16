import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'link_frame.dart';

/// The web's link frame: an iframe. A YouTube video's is its embedded
/// player, told to play and pause with messages; another site's page
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
          ? youTubeEmbed(id, web.window.location.origin).toString()
          : c.url.toString()
      ..allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen'
      ..referrerPolicy = 'strict-origin-when-cross-origin';
    iframe.style
      ..border = 'none'
      ..width = '100%'
      ..height = '100%';
    ui_web.platformViewRegistry.registerViewFactory(_view, (_) => iframe);
    if (id != null) {
      c.command = (play) async => iframe.contentWindow?.postMessage(
        youTubeCommand(play).toJS,
        '*'.toJS,
      );
    }
  }

  @override
  void dispose() {
    widget.controller.command = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _view);
}
