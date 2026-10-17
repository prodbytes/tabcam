import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'link_frame.dart';

/// Android's and iOS's link frame: a web view. A YouTube video's is its
/// embedded player in a page of its own (from the site's address, which
/// YouTube wants to see), told to play, pause and stop with messages;
/// another page's first video or sound is played, paused and stopped
/// itself.
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
    c.addListener(_changed);
    final id = c.youTubeId;
    if (id != null) {
      final src = youTubeEmbed(id, _site, autoplay: c.autoplay);
      _web.loadHtmlString(
        '<!doctype html><html><head>'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<style>html,body{margin:0;height:100%;background:#000}'
        'iframe{border:0;width:100%;height:100%}</style></head><body>'
        '<iframe id="player" src="$src" allow="autoplay; encrypted-media; '
        'picture-in-picture" allowfullscreen></iframe>'
        // The video's time, for « and »: it says it once asked to.
        '<script>var t=0,r=${c.repeat},p=document.getElementById("player");'
        "p.onload=function(){p.contentWindow.postMessage('$youTubeListening','*')};"
        'addEventListener("message",function(e){if(e.source!==p.contentWindow)return;'
        'try{var d=JSON.parse(e.data);if(d.info&&typeof d.info.currentTime=="number")'
        't=d.info.currentTime;'
        // Repeat: at its end, it starts over.
        'if(r&&((d.event=="onStateChange"&&d.info===0)||(d.info&&d.info.playerState===0)))'
        "{${youTubeRestart.map((m) => "p.contentWindow.postMessage('$m','*');").join()}}"
        '}catch(_){}});</script></body></html>',
        baseUrl: '$_site/',
      );
      c.command = (command) async {
        if (command == LinkCommand.back || command == LinkCommand.forward) {
          // The time is the page's (t), so the seek is worked out there.
          final by = (command == LinkCommand.back ? -1 : 1) * skipBy.inSeconds;
          await _web.runJavaScript(
            "p.contentWindow.postMessage(JSON.stringify({event:'command',"
            "func:'seekTo',args:[Math.max(0,t+($by)),true]}),'*')",
          );
          return;
        }
        for (final message in youTubeCommands(command)) {
          await _web.runJavaScript(
            "document.getElementById('player').contentWindow"
            ".postMessage('$message', '*')",
          );
        }
      };
    } else {
      Future<void> run(LinkCommand command) => _web.runJavaScript(
        "(function(){var m=document.querySelector('video,audio');"
        "if(m){${switch (command) {
          LinkCommand.play => 'm.play()',
          LinkCommand.pause => 'm.pause()',
          LinkCommand.stop => 'm.pause();m.currentTime=0',
          LinkCommand.back => 'm.currentTime=Math.max(0,m.currentTime-${skipBy.inSeconds})',
          LinkCommand.forward => 'm.currentTime+=${skipBy.inSeconds}',
        }}}})()",
      );
      // Opened paused: a page that plays by itself is paused once loaded.
      _web.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!c.playing) run(LinkCommand.pause);
            _loop();
          },
        ),
      );
      _web.loadRequest(c.url);
      c.command = run;
    }
  }

  /// Repeat as last told to the page.
  late bool _repeat = widget.controller.repeat;

  /// Tells the page about Repeat: a YouTube video's frame starts it over
  /// at its end (r); a page's first video or sound loops.
  void _loop() {
    final on = widget.controller.repeat;
    _repeat = on;
    unawaited(
      _web.runJavaScript(
        widget.controller.youTubeId != null
            ? 'r=$on'
            : "(function(){var m=document.querySelector('video,audio');"
                  'if(m)m.loop=$on})()',
      ),
    );
  }

  void _changed() {
    if (widget.controller.repeat != _repeat) _loop();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.controller.command = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}
