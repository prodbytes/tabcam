import '../l10n/app_localizations.dart';
import 'capture_event.dart';

/// What a file is called in its capture's list: "Page 2", "Video 1", "PDF
/// 1", "Recording 1" (numbered among the files of its kind, in the capture
/// or in the contribution it's in), or a link's title (else its host).
String fileLabel(AppLocalizations l10n, CaptureEvent event, EventPage page) {
  if (page.title case final title? when title.isNotEmpty) return title;
  if (page.isLink) return page.url?.host ?? '';
  final among = event.pages.contains(page)
      ? event.pages
      : event.contributions
                .where((c) => c.pages.contains(page))
                .firstOrNull
                ?.pages ??
            event.pages;
  final number =
      among.where((p) => p.kind == page.kind).toList().indexOf(page) + 1;
  return switch (page.kind) {
    PageKind.video => l10n.eventFileVideo(number),
    PageKind.pdf => l10n.eventFilePdf(number),
    PageKind.audio => l10n.eventFileRecording(number),
    _ => l10n.eventFilePage(number),
  };
}
