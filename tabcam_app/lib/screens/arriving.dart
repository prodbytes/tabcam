import 'package:flutter/material.dart';

import '../library/capture_event.dart';
import '../library/library.dart';

/// [page]'s preview, or, while its file is still on its way (cloud sync
/// brings it after its event: [Library.isArriving]), [placeholder] with a
/// spinner over it.
class Arriving extends StatelessWidget {
  const Arriving({
    super.key,
    required this.library,
    required this.event,
    required this.page,
    required this.placeholder,
    required this.child,
  });

  final Library library;
  final CaptureEvent event;
  final EventPage? page;
  final Widget placeholder;

  /// Built once the file is here.
  final WidgetBuilder child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) {
      final page = this.page;
      if (page == null || !library.isArriving(event.id, page)) {
        return child(context);
      }
      return Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          placeholder,
          const Center(
            child: SizedBox.square(
              key: Key('arriving'),
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ],
      );
    },
  );
}
