import 'package:flutter/material.dart';

import '../cloud/cloud_sync.dart';
import '../cloud/share_api.dart';
import '../l10n/language.dart';
import '../library/capture_event.dart';

/// Shows who [event] (the user's own) is shared with, to add people by
/// email (to edit, by default, or read only), change what they may do, or
/// remove them. No email is sent: they find it when they sign in to
/// TabCam with that address.
Future<void> showPeopleSheet(
  BuildContext context,
  CloudSync sync,
  CaptureEvent event,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => PeopleSheet(sync: sync, event: event),
);

class PeopleSheet extends StatefulWidget {
  const PeopleSheet({super.key, required this.sync, required this.event});

  final CloudSync sync;
  final CaptureEvent event;

  @override
  State<PeopleSheet> createState() => _PeopleSheetState();
}

final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[A-Za-z]{2,}$');

class _PeopleSheetState extends State<PeopleSheet> {
  final _address = TextEditingController();
  ShareRole _role = ShareRole.edit;
  List<Grant>? _grants;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run(() => widget.sync.grants(widget.event));
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _run(Future<List<Grant>> Function() task) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final grants = await task();
      if (mounted) setState(() => _grants = grants);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final email = _address.text.trim().toLowerCase();
    if (!_email.hasMatch(email)) {
      setState(() => _error = context.l10n.accountPeopleEnterEmail);
      return;
    }
    await _run(() => widget.sync.grant(widget.event, email, _role));
    if (_error == null) _address.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final grants = _grants;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.accountPeopleTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(l10n.accountPeopleIntro),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _address,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.accountPeopleEmail,
                  ),
                  onSubmitted: (_) => _add(),
                ),
              ),
              const SizedBox(width: 8),
              _RoleMenu(
                role: _role,
                onChanged: (r) => setState(() => _role = r),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: Text(l10n.accountPeopleAdd),
            ),
          ),
          if (_error case final error?) ...[
            const SizedBox(height: 8),
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 8),
          if (_busy && grants == null)
            const Center(child: CircularProgressIndicator())
          else if (grants != null && grants.isEmpty)
            Text(l10n.accountPeopleNone, style: theme.textTheme.bodyMedium)
          else if (grants != null)
            for (final g in grants)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(g.email, overflow: TextOverflow.ellipsis),
                subtitle: g.viaLink ? Text(l10n.accountPeopleViaLink) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _RoleMenu(
                      role: g.role,
                      onChanged: _busy
                          ? null
                          : (r) => _run(
                              () => widget.sync.grant(widget.event, g.email, r),
                            ),
                    ),
                    IconButton(
                      tooltip: l10n.accountPeopleRemove(g.email),
                      icon: const Icon(Icons.close),
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => widget.sync.revoke(widget.event, g.email),
                            ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _RoleMenu extends StatelessWidget {
  const _RoleMenu({required this.role, required this.onChanged});

  final ShareRole role;
  final ValueChanged<ShareRole>? onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<ShareRole>(
    tooltip: context.l10n.accountPeopleRoleTooltip,
    enabled: onChanged != null,
    initialValue: role,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final r in ShareRole.values)
        PopupMenuItem(value: r, child: Text(_label(context, r))),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_label(context, role)),
          const Icon(Icons.arrow_drop_down),
        ],
      ),
    ),
  );

  static String _label(BuildContext context, ShareRole role) =>
      role == ShareRole.edit
      ? context.l10n.accountPeopleCanEdit
      : context.l10n.accountPeopleReadOnly;
}
