import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../library/capture_event.dart';

/// A link page on the event screen: its title and address, with Open (in
/// the browser, or the app that handles it, such as YouTube) and Copy.
class LinkPage extends StatelessWidget {
  const LinkPage({super.key, required this.page});

  final EventPage page;

  Future<void> _open(BuildContext context) async {
    final ok = await launchUrl(
      page.url!,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Couldn\'t open ${page.url}')));
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: page.url.toString()));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Link copied')));
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
              Icon(Icons.link, size: 56, color: theme.colorScheme.primary),
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
                    onPressed: () => _open(context),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(context),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
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
    title: const Text('Add a link'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _url,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Link',
            hintText: 'https://…',
            errorText: _tried && parseLink(_url.text) == null
                ? 'Enter a web address (https://…)'
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
          decoration: const InputDecoration(
            labelText: 'Title (optional)',
            hintText: 'Lesson, recording…',
          ),
          onSubmitted: (_) => _add(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _add, child: const Text('Add')),
    ],
  );
}
