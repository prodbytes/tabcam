import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../cloud/profile_service.dart';
import '../cloud/share_api.dart';
import '../l10n/language.dart';
import 'mono_font.dart';

/// Profile → **Linked accounts**: the sign-ins that reach the profile's
/// captures (the owner can't be unlinked), a code to link another one, and
/// a field to enter the code another account made.
Future<void> showLinkedAccounts(
  BuildContext context,
  ProfileService profiles,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => LinkedAccountsSheet(profiles: profiles),
);

class LinkedAccountsSheet extends StatefulWidget {
  const LinkedAccountsSheet({super.key, required this.profiles});

  final ProfileService profiles;

  @override
  State<LinkedAccountsSheet> createState() => _LinkedAccountsSheetState();
}

class _LinkedAccountsSheetState extends State<LinkedAccountsSheet> {
  final _code = TextEditingController();
  LinkCode? _made;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _why(Object e) {
    final l10n = context.l10n;
    if (e is ShareApiException) {
      if (e.notShared) return l10n.profileCodeWrong;
      if (e.conflict) return l10n.profileCantLink;
      if (e.throttled) return l10n.profileTooManyTries;
    }
    return l10n.profileLinkFailed('$e');
  }

  Future<void> _makeCode() async {
    setState(() => _error = null);
    try {
      final code = await widget.profiles.makeCode();
      if (mounted) setState(() => _made = code);
    } on Object catch (e) {
      if (mounted) setState(() => _error = _why(e));
    }
  }

  Future<void> _link() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    setState(() => _error = null);
    try {
      await widget.profiles.link(code);
      _code.clear();
      final id = widget.profiles.profile?.id ?? '';
      messenger?.showSnackBar(SnackBar(content: Text(l10n.profileLinked(id))));
    } on Object catch (e) {
      if (mounted) setState(() => _error = _why(e));
    }
  }

  Future<void> _unlink(ProfileAccount account) async {
    setState(() => _error = null);
    try {
      await widget.profiles.unlink(account.id);
      if (account.you && mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) setState(() => _error = _why(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.profiles,
      builder: (context, _) {
        final profile = widget.profiles.profile;
        final busy = widget.profiles.loading;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              0,
              24,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.profileLinkedAccounts,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.profileLinkedIntro),
                  const SizedBox(height: 8),
                  if (profile == null)
                    const LinearProgressIndicator()
                  else
                    for (final a in profile.accounts)
                      ListTile(
                        key: Key('account-${a.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          a.provider == 'apple'
                              ? Icons.apple
                              : Icons.account_circle_outlined,
                        ),
                        title: Text(a.email, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          [
                            a.provider == 'apple' ? 'Apple' : 'Google',
                            if (a.owner) l10n.profileOwner,
                            if (a.you) l10n.profileThisAccount,
                          ].join(' · '),
                        ),
                        trailing: a.owner
                            ? const Icon(Icons.star_outline)
                            : TextButton(
                                onPressed: busy ? null : () => _unlink(a),
                                child: Text(l10n.profileUnlink),
                              ),
                      ),
                  const Divider(height: 32),
                  Text(
                    l10n.profileLinkAnother,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (_made case final made?) ...[
                    SelectableText(
                      made.code,
                      key: const Key('link-code'),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontFamily: monoFont,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(l10n.profileCodeHow),
                    TextButton.icon(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: made.code)),
                      icon: const Icon(Icons.copy),
                      label: Text(l10n.profileCopyCode),
                    ),
                  ] else
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : _makeCode,
                      icon: const Icon(Icons.link),
                      label: Text(l10n.profileGetCode),
                    ),
                  const Divider(height: 32),
                  Text(l10n.profileHaveCode),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('enter-code'),
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: l10n.profileCodeLabel,
                      hintText: 'ABCD-EFGH',
                    ),
                    onSubmitted: (_) => _link(),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: busy ? null : _link,
                    child: Text(l10n.profileLinkThis),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.profileLinkThisNote,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (_error case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
