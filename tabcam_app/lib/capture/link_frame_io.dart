import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'link_frame.dart';

/// Android's and iOS's link frame: a web view. A YouTube video's is its
/// embedded player in a page of its own (from the site's address, which
/// YouTube wants to see), told to play and pause with messages; another
/// page's first video or sound is played and paused itself.
Widget buildLinkFrame(LinkFrameController controller) =>
    WebViewPlatform.instance == null
    ? const SizedBox.shrink()
    : _WebViewFrame(controller: controller);

/// The site the app is: YouTube's player is embedded from there.
const _site = 'https://tabcam.nu01.com';

class _WebViewFrame extends StatefulWidget {
  const _WebViewFrame({required this.controller});

  final LinkFrameController controller;

  @override
  State<_WebViewFrame> createState() => _WebViewFrameState();
}

class _WebViewFrameState extends State<_WebViewFrame> {
  late final WebViewController _web;

  @override
  void initState() {
    super.initState();
    final c = widget.controller;
    // Media plays at once, inline, with no tap on it first.
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(
            allowsInlineMediaPlayback: true,
            mediaTypesRequiringUserAction: const {},
          )
        : const PlatformWebViewControllerCreationParams();
    _web = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black);
    if (_web.platform case final AndroidWebViewController android) {
      android.setMediaPlaybackRequiresUserGesture(false);
    }
    final id = c.youTubeId;
    if (id != null) {
      final src = youTubeEmbed(id, _site);
      _web.loadHtmlString(
        '<!doctype html><html><head>'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>html,body{margin:0;height:100%;background:#000}'
        'iframe{border:0;width:100%;height:100%}</style></head><body>'
        '<iframe id="player" src="$src" allow="autoplay; encrypted-media; '
        'picture-in-picture" allowfullscreen></iframe></body></html>',
        baseUrl: '$_site/',
      );
      c.command = (play) => _web.runJavaScript(
        "document.getElementById('player').contentWindow"
        ".postMessage('${youTubeCommand(play)}', '*')",
      );
    } else {
      _web.loadRequest(c.url);
      c.command = (play) => _web.runJavaScript(
        "(function(){var m=document.querySelector('video,audio');"
        "if(m){${play ? 'm.play()' : 'm.pause()'}}})()",
      );
    }
  }

  @override
  void dispose() {
    widget.controller.command = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}
