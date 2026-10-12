// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get languageTitle => 'Idioma';

  @override
  String get languageSystem => 'Idioma del dispositivo';

  @override
  String get accountSignIn => 'Iniciar sesión';

  @override
  String get accountSignInIntro =>
      'Inicia sesión para leer tablaturas, compartir y tener tus eventos respaldados en cada dispositivo donde inicies sesión. Sin sesión, puedes seguir capturando; todo queda en este dispositivo.';

  @override
  String get accountSignInPremium =>
      'Con sesión iniciada, TabScan Premium transcribe tus escaneos en la nube mientras se sincronizan.';

  @override
  String get accountSignInWithGoogle => 'Iniciar sesión con Google';

  @override
  String accountRole(String role) {
    return 'Rol: $role';
  }

  @override
  String get accountSyncNow => 'Sincronizar ahora';

  @override
  String get accountSignOut => 'Cerrar sesión';

  @override
  String get accountSignOutNote =>
      'Al cerrar sesión, tus eventos se quedan en este dispositivo.';

  @override
  String get accountChecking => 'Verificando…';

  @override
  String get accountRolePremium => 'Premium';

  @override
  String get accountRoleFree => 'Gratis';

  @override
  String get accountRoleFreeUnchecked => 'Gratis (no se pudo verificar)';

  @override
  String get accountSyncOff => 'Sin sincronizar';

  @override
  String get accountSyncing => 'Sincronizando…';

  @override
  String get accountSyncFailed => 'Falló la sincronización';

  @override
  String accountSyncedAt(String time) {
    return 'Sincronizado a las $time';
  }

  @override
  String get accountSynced => 'Sincronizado';

  @override
  String accountSyncUploaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subidos',
      one: '1 subido',
    );
    return '$_temp0';
  }

  @override
  String accountSyncDownloaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count descargados',
      one: '1 descargado',
    );
    return '$_temp0';
  }

  @override
  String accountSyncFailedHttp(String status) {
    return 'Falló la sincronización (HTTP $status)';
  }

  @override
  String accountSyncFailedBecause(String reason) {
    return 'Falló la sincronización: $reason';
  }

  @override
  String get accountSignInAgainToSync =>
      'Inicia sesión de nuevo para sincronizar';

  @override
  String accountSyncClockOff(int minutes) {
    return 'El reloj de este dispositivo tiene $minutes min de diferencia: ajústalo a la hora correcta para sincronizar';
  }

  @override
  String get accountSignInAgain => 'Inicia sesión de nuevo';

  @override
  String get accountPremiumCheckFailed => 'No se pudo verificar Premium';

  @override
  String get accountPremiumCheckFailedNow =>
      'No se pudo verificar Premium en este momento';

  @override
  String get accountPremiumTitle => 'TabScan Premium';

  @override
  String get accountPremiumActive =>
      'Tus escaneos se transcriben en la nube mientras se sincronizan: la tablatura en texto aparece sola en el evento.';

  @override
  String accountPremiumUntil(String date) {
    return 'Premium hasta el $date.';
  }

  @override
  String accountPremiumInactive(String email) {
    return 'TabScan Premium no está activo para $email.';
  }

  @override
  String accountPremiumOffer(String email) {
    return 'Transcribe cada escaneo automáticamente en la nube, con más precisión que en el teléfono, y lee tablaturas también en la web. Suscríbete con $email.';
  }

  @override
  String get accountPremiumUpgrade => 'Mejorar';

  @override
  String get accountPremiumVoucher => 'Canjear un cupón';

  @override
  String get accountPremiumCheckAgain => 'Verificar de nuevo';

  @override
  String accountPremiumCouldntOpen(String url) {
    return 'No se pudo abrir $url';
  }

  @override
  String get accountPeopleTitle => 'Compartir con personas';

  @override
  String get accountPeopleIntro =>
      'Las personas que agregues encontrarán esta captura al iniciar sesión en TabScan con ese correo. No se envía ningún correo.';

  @override
  String get accountPeopleEmail => 'Correo';

  @override
  String get accountPeopleAdd => 'Agregar';

  @override
  String get accountPeopleEnterEmail => 'Ingresa un correo electrónico';

  @override
  String get accountPeopleNone => 'Aún no se ha compartido.';

  @override
  String accountPeopleRemove(String email) {
    return 'Quitar a $email';
  }

  @override
  String get accountPeopleRoleTooltip => 'Qué pueden hacer';

  @override
  String get accountPeopleCanEdit => 'Puede editar';

  @override
  String get accountPeopleReadOnly => 'Solo lectura';

  @override
  String get accountSignInToShare => 'Inicia sesión para compartir';

  @override
  String get accountSignInAgainToShare =>
      'Inicia sesión de nuevo para compartir';

  @override
  String accountShareFailedHttp(String status) {
    return 'Falló al compartir (HTTP $status)';
  }

  @override
  String get accountShareLink => 'Enlace';

  @override
  String get accountShareLinkNeedsSync =>
      'Requiere iniciar sesión y sincronizar con la nube';

  @override
  String get accountShareLinkDetail =>
      'Abre esta captura en TabScan, para ti y las personas con quienes se comparte';

  @override
  String get accountSharePdf => 'PDF';

  @override
  String get accountSharePdfHidden =>
      'La tablatura en texto y los enlaces (las fotos y escaneos están ocultos)';

  @override
  String get accountSharePdfDetail =>
      'Todas las fotos y escaneos en un PDF, más la tablatura en texto y los enlaces';

  @override
  String get accountShareText => 'Texto';

  @override
  String get accountShareTextDetail =>
      'La tablatura en texto y los enlaces, como texto simple';

  @override
  String get accountShareTextNone =>
      'Aún no hay tablatura en texto: se lee después de cada captura';

  @override
  String get accountShareFiles => 'Archivos';

  @override
  String get accountShareFilesHidden =>
      'Un zip con los videos, grabaciones, PDF, la tablatura en texto y los enlaces (las fotos y escaneos están ocultos)';

  @override
  String get accountShareFilesDetail =>
      'Un zip con todo: fotos, escaneos, videos, grabaciones, PDF, la tablatura en texto y los enlaces';

  @override
  String accountShareFailed(String error) {
    return 'No se pudo compartir: $error';
  }

  @override
  String get accountExportLinks => 'Enlaces';

  @override
  String get accountSignInNotSetUp =>
      'El inicio de sesión no está configurado en esta versión.';

  @override
  String accountGoogleUnavailable(String reason) {
    return 'El inicio de sesión con Google no está disponible: $reason';
  }

  @override
  String get eventCouldntAdd => 'No se pudo agregar';

  @override
  String eventSkippedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos no son fotos ni videos, así que no se agregaron.',
      one: '1 archivo no es una foto ni un video, así que no se agregó.',
    );
    return '$_temp0';
  }

  @override
  String get eventAddedHidden =>
      'Agregado. Las imágenes están ocultas en esta captura.';

  @override
  String get eventPremiumHint =>
      'TabScan Premium transcribe tus escaneos automáticamente.';

  @override
  String get eventUpgrade => 'Mejorar';

  @override
  String get eventNotNow => 'Ahora no';

  @override
  String get eventNothingToRead =>
      'Nada que leer: agrega un escaneo, una foto o un PDF.';

  @override
  String get eventReadingTab => 'Leyendo la tablatura…';

  @override
  String get eventInCloud =>
      'Transcribiendo en la nube. El texto aparecerá aquí cuando termine.';

  @override
  String get eventNoTab =>
      'No se encontró tablatura en las páginas. Escanea más cerca y con la hoja más plana.';

  @override
  String get eventReadAgain => 'Leer de nuevo';

  @override
  String get eventReadFailed => 'No se pudo leer la tablatura.';

  @override
  String get eventReadUnsupported =>
      'Para leer tablaturas necesitas la app de Android o iOS, o TabScan Premium.';

  @override
  String get eventReadNeedsSignIn =>
      'Para leer tablaturas tienes que iniciar sesión.';

  @override
  String get eventSignIn => 'Iniciar sesión';

  @override
  String get eventNoTextYet => 'Todavía no hay texto.';

  @override
  String get eventNotReadYet => 'Todavía no se leyó.';

  @override
  String get eventRead => 'Leer';

  @override
  String get eventKeepOnePage =>
      'Una captura conserva al menos una página; elimina la captura en su lugar.';

  @override
  String get eventRename => 'Cambiar nombre';

  @override
  String get eventShareWithPeople => 'Compartir con personas';

  @override
  String get eventClone => 'Clonar';

  @override
  String get eventShare => 'Compartir';

  @override
  String get eventPages => 'Páginas';

  @override
  String get eventText => 'Texto';

  @override
  String get eventAdd => 'Agregar';

  @override
  String get eventRotate => 'Rotar';

  @override
  String get eventCouldntRotate => 'No se pudo rotar';

  @override
  String get eventDelete => 'Eliminar';

  @override
  String get eventViewOriginal => 'Original';

  @override
  String get eventViewScan => 'Escaneo';

  @override
  String get eventFilterTab => 'Tab';

  @override
  String get eventAddScan => 'Escanear páginas';

  @override
  String get eventAddScanDetail => 'Más páginas de tablatura, con la cámara';

  @override
  String get eventAddLibrary => 'Fotos y videos';

  @override
  String get eventAddLibraryDetail => 'De tu galería de fotos';

  @override
  String get eventAddFiles => 'Archivos';

  @override
  String get eventAddFilesDetail => 'Archivos de imagen, video, audio y PDF';

  @override
  String get eventAddLink => 'Enlace';

  @override
  String get eventAddLinkDetail =>
      'Una clase, una grabación, la canción en línea';

  @override
  String eventSharedBy(String owner, String access) {
    return 'Compartido por $owner · $access';
  }

  @override
  String get eventReadOnly => 'Solo lectura';

  @override
  String get eventCanEdit => 'Puede editar';

  @override
  String eventClonedAs(String title) {
    return 'Clonado como \"$title\"';
  }

  @override
  String eventCouldntClone(String error) {
    return 'No se pudo clonar: $error';
  }

  @override
  String get eventSong => 'Canción';

  @override
  String get eventArtist => 'Artista';

  @override
  String get eventCancel => 'Cancelar';

  @override
  String get eventSave => 'Guardar';

  @override
  String get eventGateReadTabTitle => 'Inicia sesión para leer tablaturas';

  @override
  String get eventGateReadTabDetail =>
      'Para convertir una tablatura en texto tienes que iniciar sesión.';

  @override
  String get eventGateShareTitle => 'Inicia sesión para compartir';

  @override
  String get eventGateShareDetail =>
      'Para compartir tienes que iniciar sesión.';

  @override
  String eventGateBody(String detail) {
    return '$detail Sin iniciar sesión, puedes seguir escaneando y agregando a tus capturas; se quedan en este dispositivo.';
  }

  @override
  String get eventSignInGoogle => 'Iniciar sesión con Google';

  @override
  String get eventNoCamera => 'No se encontró ninguna cámara.';

  @override
  String get eventCameraNotAllowed =>
      'La cámara no está permitida: deja que TabScan la use en la configuración del sitio del navegador.';

  @override
  String eventCameraFailed(String error) {
    return 'Falló la cámara: $error';
  }

  @override
  String eventCouldntTakePicture(String error) {
    return 'No se pudo tomar la foto: $error';
  }

  @override
  String eventDiscardPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return '¿Descartar $_temp0?';
  }

  @override
  String get eventKeepScanning => 'Seguir escaneando';

  @override
  String get eventDiscard => 'Descartar';

  @override
  String get eventScanTitle => 'Escanear';

  @override
  String eventPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return '$_temp0';
  }

  @override
  String get eventFlipCamera => 'Cambiar cámara';

  @override
  String get eventDone => 'Listo';

  @override
  String get eventTakePicture => 'Tomar una foto';

  @override
  String get eventChoosePhotos => 'Elegir fotos';

  @override
  String get homeTabHome => 'Inicio';

  @override
  String get homeTabCapture => 'Capturar';

  @override
  String get homeTabProfile => 'Perfil';

  @override
  String homeSignedInAs(String identity) {
    return 'Sesión iniciada como $identity';
  }

  @override
  String get homeLinkNotHere => 'Esa captura no está en este dispositivo.';

  @override
  String get homeLinkSignIn =>
      'Inicia sesión (Perfil) para abrir la captura de este enlace.';

  @override
  String get homeLinkNotShared =>
      'Esa captura no está compartida contigo. Pídele a su dueño que la comparta con tu correo electrónico.';

  @override
  String homeSaved(String title, String contents) {
    return 'Se guardó \"$title\" ($contents)';
  }

  @override
  String get homeOpen => 'Abrir';

  @override
  String homeScanFailed(String error) {
    return 'No se pudo escanear: $error';
  }

  @override
  String homeAddFailed(String error) {
    return 'No se pudo agregar: $error';
  }

  @override
  String homeSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos no son fotos ni videos, así que no se agregaron.',
      one: '1 archivo no es una foto ni un video, así que no se agregó.',
    );
    return '$_temp0';
  }

  @override
  String homePages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return '$_temp0';
  }

  @override
  String homeVideos(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count videos',
      one: '1 video',
    );
    return '$_temp0';
  }

  @override
  String homeAudio(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grabaciones',
      one: '1 grabación',
    );
    return '$_temp0';
  }

  @override
  String homePdfs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDF',
      one: '1 PDF',
    );
    return '$_temp0';
  }

  @override
  String homeLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count enlaces',
      one: '1 enlace',
    );
    return '$_temp0';
  }

  @override
  String get homeScan => 'Escanear';

  @override
  String get homeScanDetail =>
      'Con la cámara: se detecta la página, se endereza y se limpia, y puedes tomar varias seguidas.';

  @override
  String get homeAdd => 'Agregar';

  @override
  String get homeAddPhotos => 'Fotos y videos';

  @override
  String get homeAddPhotosDetail => 'De tu galería';

  @override
  String get homeAddFiles => 'Archivos';

  @override
  String get homeAddFilesDetail => 'Archivos de imagen y video';

  @override
  String get homeAddLink => 'Enlace';

  @override
  String get homeAddLinkDetail =>
      'Una lección, una grabación, la canción en línea';

  @override
  String get homeNoSignIn =>
      'El inicio de sesión no está configurado en esta versión: tus eventos se quedan en este dispositivo.';

  @override
  String get homeAbout => 'Acerca de';

  @override
  String get homeDevelopmentBuild => '(versión de desarrollo)';

  @override
  String get homeAboutDetail =>
      'Escanea tablaturas de guitarra, léelas como texto y compártelas.';

  @override
  String get homeLicenses => 'Licencias';

  @override
  String get homeLibraryMine => 'Mis capturas';

  @override
  String get homeLibraryMineEmpty =>
      'Todavía no tienes nada propio: ve a Capturar para agregar algo.';

  @override
  String get homeLibraryShared => 'Compartido conmigo';

  @override
  String get homeLibraryEmpty => 'Aún no hay tablaturas';

  @override
  String get homeLibraryEmptyDetail =>
      'Ve a Capturar para escanear una tablatura con la cámara (se detecta la página, se endereza y se limpia por ti), o para agregar fotos, videos, archivos y enlaces.';

  @override
  String homeLibraryRemoveTitle(String title) {
    return '¿Quitar \"$title\"?';
  }

  @override
  String homeLibraryRemoveBody(String owner) {
    return 'Sale de tu biblioteca. $owner lo conserva y puede volver a compartirlo contigo.';
  }

  @override
  String get homeLibraryCancel => 'Cancelar';

  @override
  String get homeLibraryRemove => 'Quitar';

  @override
  String homeLibraryRemoveFailed(String error) {
    return 'No se pudo quitar: $error';
  }

  @override
  String homeLibraryDeleteTitle(String title) {
    return '¿Eliminar \"$title\"?';
  }

  @override
  String get homeLibraryDeleteBody =>
      'Sus páginas y su tablatura en texto también se eliminan.';

  @override
  String get homeLibraryDelete => 'Eliminar';

  @override
  String get homeLibraryImagesHidden => 'imágenes ocultas';

  @override
  String get homeLibraryText => 'texto';

  @override
  String homeLibrarySharedBy(String owner) {
    return 'compartido por $owner';
  }

  @override
  String get homeLibraryMore => 'Más';

  @override
  String get homeLibraryRename => 'Renombrar';

  @override
  String get homeLibraryShare => 'Compartir';

  @override
  String get homeLibraryClone => 'Clonar';

  @override
  String get homeMaintenanceDefault =>
      'Lo sentimos, TabScan está en mantenimiento. Vuelve a intentarlo más tarde.';

  @override
  String get textViewTabCopied => 'Tablatura copiada';

  @override
  String get textViewPutCursorOnFret =>
      'Pon el cursor sobre un número de traste';

  @override
  String get textViewFixPremium => 'Arreglar es parte de TabScan Premium';

  @override
  String get textViewUpgrade => 'Mejorar';

  @override
  String get textViewFixSignIn => 'Vuelve a iniciar sesión para usar Arreglar';

  @override
  String get textViewFixUnavailable => 'Arreglar aún no está disponible';

  @override
  String get textViewCheckFailed =>
      'No se pudo verificar en línea ahora. Inténtalo más tarde.';

  @override
  String get textViewTextChanged =>
      'El texto cambió mientras tanto: toca Arreglar de nuevo';

  @override
  String get textViewTabMatches =>
      'La tablatura coincide con la encontrada en línea';

  @override
  String get textViewTabNotFound =>
      'No se encontró la tablatura de esta canción en línea';

  @override
  String textViewApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correcciones aplicadas',
      one: '1 corrección aplicada',
    );
    return '$_temp0';
  }

  @override
  String get textViewCopy => 'Copiar';

  @override
  String get textViewFix => 'Arreglar';

  @override
  String get textViewLookingOnline =>
      'Buscando la tablatura de la canción en línea…';

  @override
  String get textViewCorrect => 'Correcto';

  @override
  String get textViewMarkedCorrect =>
      'Marcado como correcto: el evento abre en su texto';

  @override
  String get textViewMarkCorrect => 'Marcar la lectura como correcta';

  @override
  String get textViewFretDown => 'Bajar traste (el número bajo el cursor)';

  @override
  String get textViewFretUp => 'Subir traste (el número bajo el cursor)';

  @override
  String get textViewOvertypeOn =>
      'Sobrescribir: lo que escribes reemplaza caracteres, las columnas no se mueven';

  @override
  String get textViewOvertypeOff =>
      'Insertar: lo que escribes empuja la línea a la derecha';

  @override
  String get textViewOvertype => 'Sobrescribir';

  @override
  String get textViewSongDialogTitle =>
      'Arreglar con la tablatura de la canción';

  @override
  String get textViewSongLabel => 'Canción y artista';

  @override
  String get textViewSongHelper =>
      'Se busca en sitios de tablaturas para corregir la lectura';

  @override
  String get textViewCancel => 'Cancelar';

  @override
  String get textViewCheck => 'Verificar';

  @override
  String get textViewRemoved => 'eliminado';

  @override
  String get textViewPrevious => 'Anterior';

  @override
  String get textViewNext => 'Siguiente';

  @override
  String textViewPosition(int index, int total) {
    return '$index de $total';
  }

  @override
  String textViewLineColumn(int line, int column) {
    return 'Línea $line, columna $column';
  }

  @override
  String textViewLineStringColumn(int line, String string, int column) {
    return 'Línea $line ($string), columna $column';
  }

  @override
  String get textViewReject => 'Rechazar';

  @override
  String get textViewRejected => 'Rechazada';

  @override
  String get textViewAccept => 'Aceptar';

  @override
  String get textViewAccepted => 'Aceptada';

  @override
  String get textViewAll => 'Todas';

  @override
  String get textViewAcceptAll => 'Aceptar todas';

  @override
  String get textViewRejectAll => 'Rechazar todas';

  @override
  String get textViewAllMenu => 'Todas…';

  @override
  String textViewDoneCount(int decided, int total) {
    return 'Listo ($decided/$total)';
  }

  @override
  String get textViewDone => 'Listo';

  @override
  String get textViewNoTextTab => 'Aún no hay tablatura en texto';

  @override
  String get textViewHiddenNotRead =>
      'Las imágenes están ocultas y la tablatura no se ha leído.';

  @override
  String get textViewHiddenStillRead =>
      'Las imágenes están ocultas. Igual se leen: el texto aparece aquí.';

  @override
  String get textViewTextTab => 'Tablatura en texto';

  @override
  String get textViewOpen => 'Abrir';

  @override
  String textViewCouldNotOpen(String url) {
    return 'No se pudo abrir $url';
  }

  @override
  String get textViewLinkCopied => 'Enlace copiado';

  @override
  String get textViewAddLink => 'Agregar un enlace';

  @override
  String get textViewLink => 'Enlace';

  @override
  String get textViewEnterAddress => 'Ingresa una dirección web (https://…)';

  @override
  String get textViewTitleOptional => 'Título (opcional)';

  @override
  String get textViewTitleHint => 'Clase, grabación…';

  @override
  String get textViewAdd => 'Agregar';

  @override
  String get textViewCantPlay => 'Este video no se puede reproducir aquí';

  @override
  String get textViewVideo => 'Video';

  @override
  String get textViewAudio => 'Grabación';

  @override
  String get textViewCantPlayAudio =>
      'Esta grabación no se puede reproducir aquí';

  @override
  String get textViewPlay => 'Reproducir';

  @override
  String get textViewPause => 'Pausar';

  @override
  String get textViewCantShowPdf => 'Este PDF no se puede mostrar aquí';

  @override
  String get homePrivacyPolicy => 'Política de privacidad';

  @override
  String get deleteAccountDone => 'Se eliminó tu cuenta de TabScan.';

  @override
  String get deleteAccountTitle => '¿Eliminar tu cuenta?';

  @override
  String get deleteAccountThisDeletes => 'Esto elimina:';

  @override
  String get deleteAccountEvents =>
      'Todos tus eventos, en la nube y en este dispositivo.';

  @override
  String get deleteAccountShares =>
      'Lo que compartiste: las personas con quienes compartiste capturas las pierden.';

  @override
  String get deleteAccountSharedWithYou =>
      'Las capturas compartidas contigo: dejan de aparecer aquí.';

  @override
  String get deleteAccountCantUndo => 'No se puede deshacer.';

  @override
  String get deleteAccountGoogleKept => 'Tu cuenta de Google no se elimina.';

  @override
  String get deleteAccountPremiumWeb =>
      'Una suscripción a TabScan Premium no se cancela: cancélala en Substack, donde te suscribiste.';

  @override
  String get deleteAccountPremiumStore =>
      'Una suscripción a TabScan Premium no se cancela: se gestiona donde la compraste.';

  @override
  String get deleteAccountOtherDevices =>
      'Si TabScan tiene la sesión iniciada en tus otros dispositivos, cierra sesión allí primero para que no vuelvan a subir sus eventos.';

  @override
  String get deleteAccountCancel => 'Cancelar';

  @override
  String get deleteAccountButton => 'Eliminar cuenta';

  @override
  String deleteAccountCouldnt(String error) {
    return 'No se pudo eliminar tu cuenta: $error';
  }

  @override
  String get deleteAccountDeleting => 'Eliminando tu cuenta';

  @override
  String get deleteAccountDeleted => 'Cuenta eliminada';

  @override
  String get deleteAccountNotDeleted => 'La cuenta no se eliminó';

  @override
  String get deleteAccountClose => 'Cerrar';

  @override
  String get deleteAccountTryAgain => 'Reintentar';

  @override
  String get deleteAccountStepCloud => 'Eliminando tus archivos en la nube…';

  @override
  String deleteAccountStepCloudCount(int done, int total) {
    return 'Eliminando tus archivos en la nube ($done de $total)…';
  }

  @override
  String get deleteAccountStepShares => 'Eliminando lo que compartiste…';

  @override
  String get deleteAccountStepDevice =>
      'Eliminando tus eventos en este dispositivo…';

  @override
  String deleteAccountStepDeviceCount(int done, int total) {
    return 'Eliminando tus eventos en este dispositivo ($done de $total)…';
  }

  @override
  String get deleteAccountStepSignOut => 'Cerrando sesión…';

  @override
  String get deleteAccountSignInAgain =>
      'Inicia sesión de nuevo para eliminar tu cuenta.';

  @override
  String get deleteAccountSignedOutMeanwhile =>
      'Cerraste sesión antes de que se eliminara tu cuenta. Tus archivos en la nube se eliminaron; inicia sesión y elimínala de nuevo para terminar.';

  @override
  String deleteAccountSharesFailed(String reason) {
    return 'Tus archivos en la nube se eliminaron, pero no lo que compartiste: $reason. Elimina tu cuenta de nuevo para terminar.';
  }

  @override
  String get deleteAccountSignInAgainShort => 'inicia sesión de nuevo';

  @override
  String deleteAccountSharesFailedBecause(String error) {
    return 'Tus archivos en la nube se eliminaron, pero no lo que compartiste ($error). Elimina tu cuenta de nuevo para terminar.';
  }

  @override
  String deleteAccountLeftHere(String error) {
    return 'Tu cuenta se eliminó y se cerró tu sesión, pero algunos eventos de este dispositivo no se pudieron eliminar ($error): elimínalos desde Inicio.';
  }

  @override
  String deleteAccountSomeFiles(int failed, int total) {
    return 'No se pudieron eliminar $failed de $total archivos en la nube. No se eliminó nada más y tu sesión sigue iniciada: inténtalo de nuevo.';
  }

  @override
  String get deleteAccountKeptAppearing =>
      'Siguieron apareciendo archivos en tu carpeta de la nube mientras se vaciaba. No se eliminó nada más: inténtalo de nuevo.';

  @override
  String deleteAccountFilesHttp(int status) {
    return 'No se pudieron eliminar tus archivos en la nube (HTTP $status). No se eliminó nada más: inténtalo de nuevo.';
  }

  @override
  String deleteAccountFilesCognito(String type) {
    return 'No se pudieron eliminar tus archivos en la nube ($type). No se eliminó nada: inténtalo de nuevo.';
  }

  @override
  String deleteAccountFilesError(String error) {
    return 'No se pudieron eliminar tus archivos en la nube ($error). No se eliminó nada más: inténtalo de nuevo.';
  }

  @override
  String get accountPremiumNeedsGoogle =>
      'Premium requiere iniciar sesión con Google';

  @override
  String get accountSignInWithApple => 'Iniciar sesión con Apple';

  @override
  String get accountAppleSignInFailed => 'No se pudo iniciar sesión con Apple';

  @override
  String get accountAppleSignInExpired =>
      'Tu sesión de Apple expiró: inicia sesión de nuevo.';

  @override
  String get accountAppleUnavailable =>
      'Iniciar sesión con Apple no está disponible en este dispositivo.';

  @override
  String accountPrivateEmail(String provider) {
    return 'ID de $provider (correo privado)';
  }
}
