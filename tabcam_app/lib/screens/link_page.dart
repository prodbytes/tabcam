import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../library/capture_event.dart';
import '../l10n/language.dart';
import 'youtube_link.dart';

/// Opens [url] outside the app: on the web in a new tab; on Android and
/// iOS in the browser, or the app the system hands it to (such as
/// YouTube). Only http and https links ([checkUrl]); false if it didn't
/// open.
Future<bool> launchLink(Uri url) async {
  try {
    checkUrl(url);
    return await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_blank',
    );
  } catch (_) {
    return false;
  }
}

/// [launchLink], saying so at the bottom of the screen if it can't.
Future<void> openLink(BuildContext context, Uri url) async {
  if (!await launchLink(url) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.textViewCouldNotOpen('$url'))),
    );
  }
}

/// A link page on the file screen: its title and address, with Open
/// ([openLink]: a new tab on the web, the browser or the app for it on
/// Android and iOS) and Copy. A YouTube video's link shows a video icon;
/// it opens the same way.
class LinkPage extends StatelessWidget {
  const LinkPage({super.key, required this.page});

  final EventPage page;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: page.url.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.textViewLinkCopied)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = page.url!;
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                youTubeVideoId(url) != null ? Icons.smart_display : Icons.link,
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
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () => openLink(context, url),
                    icon: const Icon(Icons.open_in_new),
                    label: Text(context.l10n.textViewOpen),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy),
                    label: Text(context.l10n.textViewCopy),
                  ),
                ],
              ),
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
