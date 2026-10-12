import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../library/capture_event.dart';
import '../l10n/language.dart';
import 'youtube_player_view.dart';

/// A link page on the event screen: its title and address, with Open (in
/// a browser inside the app on Android and iOS, in a new tab on the web)
/// and Copy. A YouTube video's link also has Play, which plays it here in
/// YouTube's player; if it can't play here, for any reason, the page goes
/// back to the link, saying so.
class LinkPage extends StatefulWidget {
  const LinkPage({super.key, required this.page});

  final EventPage page;

  @override
  State<LinkPage> createState() => _LinkPageState();
}

class _LinkPageState extends State<LinkPage> {
  YouTubeVideo? get _video =>
      canEmbedYouTube ? youTubeVideo(widget.page.url!) : null;
  bool _playing = false;
  bool _cantPlay = false;

  @override
  void didUpdateWidget(LinkPage old) {
    super.didUpdateWidget(old);
    if (old.page.url != widget.page.url) {
      _playing = false;
      _cantPlay = false;
    }
  }

  EventPage get page => widget.page;

  Future<void> _open(BuildContext context) async {
    final url = page.url!;
    Future<bool> launch(LaunchMode mode) => launchUrl(
      url,
      mode: mode,
      webOnlyWindowName: '_blank',
    ).catchError((_) => false);
    // Where there's no browser inside the app, the browser (or the app
    // that handles it, such as YouTube) opens it.
    final ok = kIsWeb
        ? await launch(LaunchMode.platformDefault)
        : await launch(LaunchMode.inAppBrowserView) ||
              await launch(LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.textViewCouldNotOpen('${page.url}')),
        ),
      );
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: page.url.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.textViewLinkCopied)));
    }
  }

  Widget _buttons(BuildContext context, {required bool play}) => Wrap(
    spacing: 12,
    runSpacing: 8,
    alignment: WrapAlignment.center,
    children: [
      if (play)
        FilledButton.icon(
          onPressed: () => setState(() => _playing = true),
          icon: const Icon(Icons.play_arrow),
          label: Text(context.l10n.textViewPlay),
        ),
      if (play)
        OutlinedButton.icon(
          onPressed: () => _open(context),
          icon: const Icon(Icons.open_in_new),
          label: Text(context.l10n.textViewOpen),
        )
      else
        FilledButton.icon(
          onPressed: () => _open(context),
          icon: const Icon(Icons.open_in_new),
          label: Text(context.l10n.textViewOpen),
        ),
      OutlinedButton.icon(
        onPressed: () => _copy(context),
        icon: const Icon(Icons.copy),
        label: Text(context.l10n.textViewCopy),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = page.url!;
    final video = _cantPlay ? null : _video;
    if (video != null && _playing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: YouTubePlayerView(
                video: video,
                onFailed: () => setState(() => _cantPlay = true),
              ),
            ),
            const SizedBox(height: 12),
            _buttons(context, play: false),
          ],
        ),
      );
    }
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                video != null ? Icons.smart_display : Icons.link,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                page.title ?? url.host,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              SelectableText(
                url.toString(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              if (_cantPlay) ...[
                const SizedBox(height: 8),
                Text(
                  context.l10n.textViewCantPlay,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _buttons(context, play: video != null),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks for a link's address and an optional title; null if cancelled.
Future<(Uri, String?)?> askForLink(BuildContext context) =>
    showDialog<(Uri, String?)>(
      context: context,
      builder: (_) => const _LinkDialog(),
    );

class _LinkDialog extends StatefulWidget {
  const _LinkDialog();

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  bool _tried = false;

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  void _add() {
    final url = parseLink(_url.text);
    if (url == null) {
      setState(() => _tried = true);
      return;
    }
    Navigator.pop(context, (url, _title.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.textViewAddLink),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _url,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: context.l10n.textViewLink,
            hintText: 'https://…',
            errorText: _tried && parseLink(_url.text) == null
                ? context.l10n.textViewEnterAddress
                : null,
          ),
          onChanged: (_) {
            if (_tried) setState(() {});
          },
          onSubmitted: (_) => _add(),
        ),
        TextField(
          controller: _title,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: context.l10n.textViewTitleOptional,
            hintText: context.l10n.textViewTitleHint,
          ),
          onSubmitted: (_) => _add(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.textViewCancel),
      ),
      FilledButton(onPressed: _add, child: Text(context.l10n.textViewAdd)),
    ],
  );
}
