// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get languageTitle => 'Idioma';

  @override
  String get languageSystem => 'Idioma do dispositivo';

  @override
  String get accountSignIn => 'Entrar';

  @override
  String get accountSignInIntro =>
      'Entre para ler tablaturas, compartilhar e ter seus eventos com backup em todos os dispositivos em que você entrar.';

  @override
  String get accountSignInPremium =>
      'Com a sessão iniciada, o TabCam Premium transcreve suas digitalizações na nuvem enquanto sincronizam.';

  @override
  String get accountSignInWithGoogle => 'Entrar com o Google';

  @override
  String accountRole(String role) {
    return 'Função: $role';
  }

  @override
  String get accountSyncNow => 'Sincronizar agora';

  @override
  String get accountSignOut => 'Sair';

  @override
  String get accountSignOutNote =>
      'Ao sair, seus eventos continuam neste dispositivo.';

  @override
  String get accountChecking => 'Verificando…';

  @override
  String get accountRolePremium => 'Premium';

  @override
  String get accountRoleFree => 'Grátis';

  @override
  String get accountRoleFreeUnchecked => 'Grátis (não foi possível verificar)';

  @override
  String get accountSyncOff => 'Sem sincronização';

  @override
  String get accountSyncing => 'Sincronizando…';

  @override
  String get accountSyncFailed => 'Falha na sincronização';

  @override
  String accountSyncedAt(String time) {
    return 'Sincronizado às $time';
  }

  @override
  String get accountSynced => 'Sincronizado';

  @override
  String accountSyncUploaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count enviados',
      one: '1 enviado',
    );
    return '$_temp0';
  }

  @override
  String accountSyncDownloaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count baixados',
      one: '1 baixado',
    );
    return '$_temp0';
  }

  @override
  String accountSyncFailedHttp(String status) {
    return 'Falha na sincronização (HTTP $status)';
  }

  @override
  String accountSyncFailedBecause(String reason) {
    return 'Falha na sincronização: $reason';
  }

  @override
  String get accountSignInAgainToSync => 'Entre novamente para sincronizar';

  @override
  String accountSyncClockOff(int minutes) {
    return 'O relógio deste dispositivo está errado em $minutes min: ajuste a hora certa para sincronizar';
  }

  @override
  String get accountSignInAgain => 'Entre novamente';

  @override
  String get accountPremiumCheckFailed =>
      'Não foi possível verificar o Premium';

  @override
  String get accountPremiumCheckFailedNow =>
      'Não foi possível verificar o Premium agora';

  @override
  String get accountPremiumTitle => 'TabCam Premium';

  @override
  String get accountPremiumActive =>
      'Suas digitalizações são transcritos na nuvem enquanto sincronizam: a tablatura em texto aparece sozinha no evento.';

  @override
  String accountPremiumUntil(String date) {
    return 'Premium até $date.';
  }

  @override
  String accountPremiumInactive(String email) {
    return 'O TabCam Premium não está ativo para $email.';
  }

  @override
  String accountPremiumOffer(String email) {
    return 'Tenha cada digitalização transcrita automaticamente na nuvem, com mais precisão do que no celular, e leia tablaturas na web também. US\$ 10 por mês ou US\$ 100 por ano: assine com $email.';
  }

  @override
  String get accountPremiumUpgrade => 'Fazer upgrade';

  @override
  String get accountPremiumVoucher => 'Resgatar um cupom';

  @override
  String get accountPremiumCheckAgain => 'Verificar novamente';

  @override
  String accountPremiumCouldntOpen(String url) {
    return 'Não foi possível abrir $url';
  }

  @override
  String get accountPeopleCanEdit => 'Pode editar';

  @override
  String get accountPeopleReadOnly => 'Pode ver e adicionar';

  @override
  String get accountSignInToShare => 'Entre para compartilhar';

  @override
  String get accountSignInAgainToShare => 'Entre novamente para compartilhar';

  @override
  String accountShareFailedHttp(String status) {
    return 'Falha ao compartilhar (HTTP $status)';
  }

  @override
  String get accountShareLink => 'Link';

  @override
  String get accountShareLinkNeedsSync =>
      'Requer entrar e sincronizar com a nuvem';

  @override
  String get accountShareLinkDetail =>
      'Abre esta captura no TabCam, para você e as pessoas com quem ela é compartilhada';

  @override
  String get accountSharePdf => 'PDF';

  @override
  String get accountSharePdfHidden =>
      'A tablatura em texto e os links (as fotos e digitalizações estão ocultas)';

  @override
  String get accountSharePdfDetail =>
      'Todas as fotos e digitalizações em um PDF, mais a tablatura em texto e os links';

  @override
  String get accountShareText => 'Texto';

  @override
  String get accountShareTextDetail =>
      'A tablatura em texto e os links, como texto simples';

  @override
  String get accountShareTextNone =>
      'Ainda não há tablatura em texto: ela é lida após cada captura';

  @override
  String get accountShareFiles => 'Arquivos';

  @override
  String get accountShareFilesHidden =>
      'Um zip com os vídeos, gravações, PDFs, a tablatura em texto e os links (as fotos e digitalizações estão ocultas)';

  @override
  String get accountShareFilesDetail =>
      'Um zip com tudo: fotos, digitalizações, vídeos, gravações, PDFs, a tablatura em texto e os links';

  @override
  String accountShareFailed(String error) {
    return 'Não foi possível compartilhar: $error';
  }

  @override
  String get accountExportLinks => 'Links';

  @override
  String get accountSignInNotSetUp =>
      'O login não está configurado nesta versão.';

  @override
  String accountGoogleUnavailable(String reason) {
    return 'O login com o Google não está disponível: $reason';
  }

  @override
  String get eventCouldntAdd => 'Não foi possível adicionar';

  @override
  String eventSkippedFiles(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count arquivos não são fotos nem vídeos, então não foram adicionados.',
      one: '1 arquivo não é foto nem vídeo, então não foi adicionado.',
    );
    return '$_temp0';
  }

  @override
  String get eventAddedHidden =>
      'Adicionado. As imagens estão ocultas nesta captura.';

  @override
  String get eventPremiumHint =>
      'O TabCam Premium transcreve suas digitalizações automaticamente.';

  @override
  String get eventUpgrade => 'Assinar';

  @override
  String get eventNotNow => 'Agora não';

  @override
  String get eventNothingToRead =>
      'Nada para ler: adicione uma digitalização, uma foto ou um PDF.';

  @override
  String get eventReadingTab => 'Lendo a tablatura…';

  @override
  String get eventInCloud =>
      'Transcrevendo na nuvem: de 1 a 3 minutos por página. O texto aparece aqui quando terminar, mesmo se você sair.';

  @override
  String get eventNoTab =>
      'Nenhuma tablatura encontrada nas páginas. Digitalize mais perto e com a folha mais plana.';

  @override
  String get eventReadAgain => 'Ler de novo';

  @override
  String get eventRescanTitle => 'Reescanear as páginas?';

  @override
  String get eventRescanBody =>
      'Cada foto e PDF é lido de novo. Se uma tablatura for encontrada, ela substitui o texto atual, mesmo que você o tenha editado ou marcado como verificado; se não, o texto é mantido.';

  @override
  String eventRescanKept(String reason) {
    return '$reason O texto foi mantido.';
  }

  @override
  String get eventReadFailed => 'Falha ao ler a tablatura.';

  @override
  String get eventReadUnsupported =>
      'Para ler tablaturas, use o app para Android ou iOS, ou o TabCam Premium.';

  @override
  String get eventReadNeedsSignIn =>
      'Para ler tablaturas, você precisa entrar.';

  @override
  String get eventSignIn => 'Entrar';

  @override
  String get eventNoTextYet => 'Ainda não há texto.';

  @override
  String get eventNotReadYet => 'Ainda não lido.';

  @override
  String get eventRead => 'Ler';

  @override
  String get eventKeepOnePage =>
      'Uma captura mantém pelo menos uma página; exclua a captura.';

  @override
  String get eventRename => 'Renomear';

  @override
  String get eventClone => 'Clonar';

  @override
  String get eventShare => 'Compartilhar';

  @override
  String get eventFiles => 'Arquivos';

  @override
  String eventFilePage(int number) {
    return 'Página $number';
  }

  @override
  String eventFileVideo(int number) {
    return 'Vídeo $number';
  }

  @override
  String eventFilePdf(int number) {
    return 'PDF $number';
  }

  @override
  String eventFileRecording(int number) {
    return 'Gravação $number';
  }

  @override
  String get eventText => 'Texto';

  @override
  String get eventAdd => 'Adicionar';

  @override
  String get eventRotate => 'Girar';

  @override
  String get eventCouldntRotate => 'Não foi possível girar';

  @override
  String get eventDelete => 'Excluir';

  @override
  String get eventDeleteFile => 'Excluir arquivo';

  @override
  String get eventDownload => 'Baixar';

  @override
  String get eventDownloadAll => 'Baixar tudo';

  @override
  String get eventCouldntDownload => 'Não foi possível baixar';

  @override
  String get eventFileMore => 'Mais';

  @override
  String get eventCouldntDelete => 'Não foi possível excluir';

  @override
  String get eventReorder => 'Reordenar';

  @override
  String get eventCouldntReorder => 'Não foi possível reordenar';

  @override
  String get eventViewOriginal => 'Original';

  @override
  String get eventViewScan => 'Digitalizado';

  @override
  String get eventFilterTab => 'Tab';

  @override
  String get eventAddScan => 'Digitalizar páginas';

  @override
  String get eventAddScanDetail => 'Mais páginas de tablatura, com a câmera';

  @override
  String get eventAddLibrary => 'Fotos e vídeos';

  @override
  String get eventAddLibraryDetail => 'Da sua galeria de fotos';

  @override
  String get eventAddFiles => 'Arquivos';

  @override
  String get eventAddFilesDetail => 'Arquivos de imagem, vídeo, áudio e PDF';

  @override
  String get eventAddLink => 'Link';

  @override
  String get eventAddLinkDetail => 'Uma aula, uma gravação, a música online';

  @override
  String eventSharedBy(String owner, String access) {
    return 'Compartilhado por $owner · $access';
  }

  @override
  String get eventReadOnly => 'Pode ver e adicionar';

  @override
  String get eventByLink => 'Aberta pelo link · Somente leitura';

  @override
  String linkTabImporting(String site) {
    return 'Importando a página do $site…';
  }

  @override
  String linkTabImported(String site) {
    return 'A página do $site foi adicionada como PDF, para ler a tablatura.';
  }

  @override
  String linkTabPremium(String site) {
    return 'Link adicionado. Na web, importar a página do $site precisa do TabCam Premium.';
  }

  @override
  String linkTabFailed(String site) {
    return 'Link adicionado. Não foi possível importar a página do $site.';
  }

  @override
  String get linkSignIn => 'Entrar';

  @override
  String get linkOpening => 'Abrindo a captura…';

  @override
  String get linkTryAgain => 'Tentar de novo';

  @override
  String get linkUnavailable =>
      'Não foi possível abrir esta captura. O link pode estar errado, o dono pode tê-la apagado ou você pode estar sem conexão.';

  @override
  String get eventCanEdit => 'Pode editar';

  @override
  String eventClonedAs(String title) {
    return 'Clonado como \"$title\"';
  }

  @override
  String eventCouldntClone(String error) {
    return 'Não foi possível clonar: $error';
  }

  @override
  String get eventName => 'Nome';

  @override
  String get eventStudy => 'Estudo';

  @override
  String get eventStudyHelp => 'Opcional: agrupa capturas relacionadas';

  @override
  String get eventCancel => 'Cancelar';

  @override
  String get eventSave => 'Salvar';

  @override
  String get eventGateReadTabTitle => 'Entre para ler tablaturas';

  @override
  String get eventGateReadTabDetail =>
      'Para transformar uma tablatura em texto, você precisa entrar.';

  @override
  String get eventGateShareTitle => 'Entre para compartilhar';

  @override
  String get eventGateShareDetail => 'Para compartilhar, você precisa entrar.';

  @override
  String eventGateBody(String detail) {
    return '$detail Sem entrar, você ainda pode digitalizar e adicionar às suas capturas; elas ficam neste dispositivo.';
  }

  @override
  String get eventSignInGoogle => 'Entrar com o Google';

  @override
  String get eventNoCamera => 'Nenhuma câmera encontrada.';

  @override
  String get eventCameraNotAllowed =>
      'A câmera não está permitida: deixe o TabCam usá-la nas configurações do site no navegador.';

  @override
  String eventCameraFailed(String error) {
    return 'A câmera falhou: $error';
  }

  @override
  String eventCouldntTakePicture(String error) {
    return 'Não foi possível tirar a foto: $error';
  }

  @override
  String eventDiscardPages(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return 'Descartar $_temp0?';
  }

  @override
  String get eventKeepScanning => 'Continuar';

  @override
  String get eventDiscard => 'Descartar';

  @override
  String get eventScanTitle => 'Digitalizar';

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
  String get eventFlipCamera => 'Trocar câmera';

  @override
  String get eventCam => 'Câmera';

  @override
  String get camRec => 'Gravar';

  @override
  String get camStop => 'Parar';

  @override
  String get camPlay => 'Tocar';

  @override
  String get camHideTab => 'Ocultar tablatura';

  @override
  String get camShowTab => 'Mostrar tablatura';

  @override
  String get camPrevious => 'Linha anterior';

  @override
  String get camNext => 'Próxima linha';

  @override
  String get camNoTab =>
      'Ainda não há tablatura em texto: leia a tablatura da captura para tocar junto.';

  @override
  String camTake(int number) {
    return 'Take $number';
  }

  @override
  String camSaved(String name) {
    return '$name adicionado à captura';
  }

  @override
  String camCouldntRecord(String error) {
    return 'Não foi possível gravar: $error';
  }

  @override
  String get camAddingTab => 'Adicionando a tablatura ao vídeo…';

  @override
  String camNoOverlay(String reason) {
    return 'O take foi salvo sem a tablatura: $reason';
  }

  @override
  String camRecordingNoTab(String reason) {
    return 'Gravando sem a tablatura: $reason';
  }

  @override
  String get camAlong => 'Tocar junto com um arquivo';

  @override
  String get camAlongHide => 'Ocultar os arquivos para tocar junto';

  @override
  String get camAlongTitle => 'Tocar junto';

  @override
  String get camAlongPdfs => 'Seguir um PDF';

  @override
  String get camAlongPdfShow => 'Mostrar o PDF ao lado da câmera';

  @override
  String get camAlongPdfHide => 'Ocultar o PDF';

  @override
  String get camAlongPlay => 'Tocar (espaço)';

  @override
  String get camAlongPause => 'Pausar (espaço)';

  @override
  String get camAlongBack => 'Voltar 10 segundos';

  @override
  String get camAlongForward => 'Avançar 10 segundos';

  @override
  String get camAlongRepeatOn => 'Repetir ligado: recomeça ao terminar';

  @override
  String get camAlongRepeatOff => 'Repetir desligado';

  @override
  String camAlongSection(String start, String end) {
    return 'Trecho $start–$end';
  }

  @override
  String get camAlongSectionStart => 'Começar o trecho aqui';

  @override
  String get camAlongSectionEnd => 'Terminar o trecho aqui';

  @override
  String get camAlongSectionClear => 'Tocar tudo';

  @override
  String get camAlongSpeed =>
      'Velocidade: mais devagar à esquerda, mais rápido à direita';

  @override
  String get camAlongSpeedNormal => 'Velocidade normal (1×)';

  @override
  String get camAlongStop => 'Parar';

  @override
  String get camHeadsOn =>
      'Gestos de cabeça ligados: acene para cima ou à direita para a próxima linha, para baixo ou à esquerda para a anterior';

  @override
  String get camHeadsOff => 'Gestos de cabeça desligados';

  @override
  String get camNotAllowed =>
      'A câmera ou o microfone não estão permitidos: deixe o TabCam usá-los nas configurações.';

  @override
  String get eventDone => 'Concluir';

  @override
  String get eventTakePicture => 'Tirar foto';

  @override
  String get eventChoosePhotos => 'Escolher fotos';

  @override
  String get homeTabHome => 'Início';

  @override
  String get homeTabCapture => 'Capturar';

  @override
  String get homeTabProfile => 'Perfil';

  @override
  String homeSignedInAs(String identity) {
    return 'Conectado como $identity';
  }

  @override
  String get homeLinkNotHere => 'Essa captura não está neste dispositivo.';

  @override
  String get homeLinkSignIn =>
      'Entre (Perfil) para abrir a captura deste link.';

  @override
  String get homeLinkNotShared =>
      'Essa captura não está compartilhada com você. Peça ao dono que a compartilhe com seu e-mail.';

  @override
  String homeSaved(String title, String contents) {
    return '\"$title\" salvo ($contents)';
  }

  @override
  String get homeOpen => 'Abrir';

  @override
  String homeScanFailed(String error) {
    return 'Não foi possível digitalizar: $error';
  }

  @override
  String get scanCameraNotAllowed =>
      'a câmera não está permitida. Deixe o TabCam usá-la nas configurações.';

  @override
  String homeAddFailed(String error) {
    return 'Não foi possível adicionar: $error';
  }

  @override
  String homeSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count arquivos não são fotos nem vídeos, então não foram adicionados.',
      one: '1 arquivo não é foto nem vídeo, então não foi adicionado.',
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
      other: '$count vídeos',
      one: '1 vídeo',
    );
    return '$_temp0';
  }

  @override
  String homeAudio(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gravações',
      one: '1 gravação',
    );
    return '$_temp0';
  }

  @override
  String homePdfs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDFs',
      one: '1 PDF',
    );
    return '$_temp0';
  }

  @override
  String homeLinks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count links',
      one: '1 link',
    );
    return '$_temp0';
  }

  @override
  String get homeScan => 'Digitalizar';

  @override
  String get homeScanDetail =>
      'Com a câmera: a página é encontrada, endireitada e limpa, e você pode tirar várias seguidas.';

  @override
  String get homeAdd => 'Adicionar';

  @override
  String get homeAddPhotos => 'Fotos e vídeos';

  @override
  String get homeAddPhotosDetail => 'Da sua galeria';

  @override
  String get homeAddFiles => 'Arquivos';

  @override
  String get homeAddFilesDetail => 'Arquivos de imagem e vídeo';

  @override
  String get homeAddLink => 'Link';

  @override
  String get homeAddLinkDetail =>
      'Uma aula, uma base para tocar junto, um vídeo';

  @override
  String get homeNoSignIn =>
      'O login não está configurado nesta versão: seus eventos ficam neste dispositivo.';

  @override
  String get homeAbout => 'Sobre';

  @override
  String get homeDevelopmentBuild => '(versão de desenvolvimento)';

  @override
  String get homeAboutDetail =>
      'Digitalize tablaturas de violão, leia-as como texto e compartilhe-as.';

  @override
  String get homeLicenses => 'Licenças';

  @override
  String get homeLibraryMine => 'Minhas capturas';

  @override
  String get homeLibraryMineEmpty =>
      'Ainda não há nada seu: vá em Capturar para adicionar.';

  @override
  String get homeLibraryShared => 'Compartilhado comigo';

  @override
  String get homeSearch => 'Buscar capturas';

  @override
  String get homeSearchClear => 'Limpar busca';

  @override
  String homeSearchNone(String query) {
    return 'Nenhuma captura corresponde a “$query”';
  }

  @override
  String get homeLibraryEmpty => 'Ainda não há tablaturas';

  @override
  String get homeLibraryLoading => 'Carregando suas capturas…';

  @override
  String get homeLibraryLoadFailed => 'Não foi possível carregar suas capturas';

  @override
  String get homeLibraryTryAgain => 'Tentar de novo';

  @override
  String get homeLibraryEmptyDetail =>
      'Vá em Capturar para digitalizar uma tablatura com a câmera (a página é encontrada, endireitada e limpa para você) ou para adicionar fotos, vídeos, arquivos e links.';

  @override
  String homeLibraryRemoveTitle(String title) {
    return 'Remover \"$title\"?';
  }

  @override
  String homeLibraryRemoveBody(String owner) {
    return 'Ele sai da sua biblioteca. $owner continua com ele e pode compartilhá-lo com você de novo.';
  }

  @override
  String get homeLibraryCancel => 'Cancelar';

  @override
  String get homeLibraryRemove => 'Remover';

  @override
  String homeLibraryRemoveFailed(String error) {
    return 'Não foi possível remover: $error';
  }

  @override
  String homeLibraryDeleteTitle(String title) {
    return 'Excluir \"$title\"?';
  }

  @override
  String get homeLibraryDeleteBody =>
      'Suas páginas e a tablatura em texto também são excluídas.';

  @override
  String get homeLibraryDelete => 'Excluir';

  @override
  String get homeLibraryImagesHidden => 'imagens ocultas';

  @override
  String get homeLibraryText => 'texto';

  @override
  String homeLibrarySharedBy(String owner) {
    return 'compartilhado por $owner';
  }

  @override
  String get homeLibraryMore => 'Mais';

  @override
  String get homeLibraryRename => 'Renomear';

  @override
  String get homeLibraryShare => 'Compartilhar';

  @override
  String get homeLibraryClone => 'Clonar';

  @override
  String get homeMaintenanceDefault =>
      'Desculpe, o TabCam está em manutenção. Tente novamente mais tarde.';

  @override
  String get textViewTabCopied => 'Tablatura copiada';

  @override
  String get textViewPutCursorOnFret =>
      'Coloque o cursor sobre um número de traste';

  @override
  String get textViewFixPremium => 'Corrigir faz parte do TabCam Premium';

  @override
  String get textViewUpgrade => 'Assinar';

  @override
  String get textViewFixSignIn => 'Entre novamente para usar Corrigir';

  @override
  String get textViewFixUnavailable => 'Corrigir ainda não está disponível';

  @override
  String get textViewCheckFailed =>
      'Não foi possível verificar online agora. Tente mais tarde.';

  @override
  String get textViewTextChanged =>
      'O texto mudou enquanto isso: toque em Corrigir de novo';

  @override
  String get textViewTabMatches =>
      'A tablatura confere com a encontrada online';

  @override
  String get textViewTabNotFound =>
      'Não foi possível encontrar a tablatura desta música online';

  @override
  String textViewApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correções aplicadas',
      one: '1 correção aplicada',
    );
    return '$_temp0';
  }

  @override
  String get textViewReview => 'Revisar';

  @override
  String get textViewReviewTip =>
      'Mostrar as páginas digitalizadas ao lado do texto';

  @override
  String textViewReviewPage(int number) {
    return 'Página $number';
  }

  @override
  String get textViewCopy => 'Copiar';

  @override
  String get textViewFix => 'Corrigir';

  @override
  String get textViewRescan => 'Reescanear';

  @override
  String get textViewRescanTip => 'Ler de novo a tablatura das páginas';

  @override
  String get textViewRescanning => 'Digitalizando as páginas de novo…';

  @override
  String get textViewLookingOnline =>
      'Procurando a tablatura da música online…';

  @override
  String get textViewCorrect => 'Verificado';

  @override
  String get textViewMarkedCorrect => 'Verificado: o evento abre no texto';

  @override
  String get textViewMarkCorrect => 'Marcar a leitura como verificada';

  @override
  String get textViewFretDown => 'Descer traste (o número sob o cursor)';

  @override
  String get textViewFretUp => 'Subir traste (o número sob o cursor)';

  @override
  String get textViewNoteUp => 'Nota uma corda acima (dá a volta)';

  @override
  String get textViewNoteDown => 'Nota uma corda abaixo (dá a volta)';

  @override
  String get textViewPutCursorOnNote =>
      'Coloque o cursor numa nota de uma corda';

  @override
  String get textViewNoStringFree =>
      'Nenhuma outra corda tem espaço para esta nota ali';

  @override
  String get textViewOvertypeOn =>
      'Sobrescrever: digitar substitui caracteres, as colunas não se movem';

  @override
  String get textViewOvertypeOff =>
      'Inserir: digitar empurra a linha para a direita';

  @override
  String get textViewNotation => 'Notação de tablatura';

  @override
  String get textViewNotationHammerOn => 'ligado ascendente (hammer-on)';

  @override
  String get textViewNotationPullOff => 'ligado descendente (pull-off)';

  @override
  String get textViewNotationSlide => 'deslizar para cima, para baixo';

  @override
  String get textViewNotationBend => 'bend (até a nota do 9), r soltar';

  @override
  String get textViewOvertype => 'Sobrescrever';

  @override
  String get textViewSongDialogTitle => 'Corrigir pela tablatura da música';

  @override
  String get textViewSongLabel => 'Música e artista';

  @override
  String get textViewSongHelper =>
      'Buscado em sites de tablatura para corrigir a leitura';

  @override
  String get textViewCancel => 'Cancelar';

  @override
  String get textViewCheck => 'Verificar';

  @override
  String get textViewRemoved => 'removido';

  @override
  String get textViewPrevious => 'Anterior';

  @override
  String get textViewNext => 'Próxima';

  @override
  String textViewPosition(int index, int total) {
    return '$index de $total';
  }

  @override
  String textViewLineColumn(int line, int column) {
    return 'Linha $line, coluna $column';
  }

  @override
  String textViewLineStringColumn(int line, String string, int column) {
    return 'Linha $line ($string), coluna $column';
  }

  @override
  String get textViewReject => 'Rejeitar';

  @override
  String get textViewRejected => 'Rejeitada';

  @override
  String get textViewAccept => 'Aceitar';

  @override
  String get textViewAccepted => 'Aceita';

  @override
  String get textViewAll => 'Todas';

  @override
  String get textViewAcceptAll => 'Aceitar todas';

  @override
  String get textViewRejectAll => 'Rejeitar todas';

  @override
  String get textViewAllMenu => 'Todas…';

  @override
  String textViewDoneCount(int decided, int total) {
    return 'Concluir ($decided/$total)';
  }

  @override
  String get textViewDone => 'Concluir';

  @override
  String get textViewNoTextTab => 'Ainda não há tablatura em texto';

  @override
  String get textViewHiddenNotRead =>
      'As imagens estão ocultas e a tablatura não foi lida.';

  @override
  String get textViewHiddenStillRead =>
      'As imagens estão ocultas. Elas ainda são lidas: o texto aparece aqui.';

  @override
  String get textViewTextTab => 'Tablatura em texto';

  @override
  String get textViewOpen => 'Abrir';

  @override
  String textViewCouldNotOpen(String url) {
    return 'Não foi possível abrir $url';
  }

  @override
  String get textViewLinkCopied => 'Link copiado';

  @override
  String get textViewAddLink => 'Adicionar um link';

  @override
  String get textViewLink => 'Link';

  @override
  String get textViewEnterAddress => 'Digite um endereço web (https://…)';

  @override
  String get textViewTitleOptional => 'Título (opcional)';

  @override
  String get textViewTitleHint => 'Aula, gravação…';

  @override
  String get textViewAdd => 'Adicionar';

  @override
  String get textViewCantPlay => 'Este vídeo não pode ser reproduzido aqui';

  @override
  String get textViewVideo => 'Vídeo';

  @override
  String get textViewAudio => 'Gravação';

  @override
  String get textViewCantPlayAudio =>
      'Esta gravação não pode ser reproduzida aqui';

  @override
  String get textViewPlay => 'Reproduzir';

  @override
  String get textViewPause => 'Pausar';

  @override
  String get textViewCantShowPdf => 'Este PDF não pode ser exibido aqui';

  @override
  String get homePrivacyPolicy => 'Política de privacidade';

  @override
  String get deleteAccountDone => 'Sua conta do TabCam foi excluída.';

  @override
  String get deleteAccountTitle => 'Excluir sua conta?';

  @override
  String get deleteAccountThisDeletes => 'Isto exclui:';

  @override
  String get deleteAccountEvents =>
      'Todos os seus eventos, na nuvem e neste dispositivo.';

  @override
  String get deleteAccountShares =>
      'Seus compartilhamentos: as pessoas com quem você compartilhou capturas deixam de tê-las.';

  @override
  String get deleteAccountSharedWithYou =>
      'As capturas compartilhadas com você: deixam de aparecer aqui.';

  @override
  String get deleteAccountCantUndo => 'Não é possível desfazer.';

  @override
  String get deleteAccountGoogleKept => 'Sua conta do Google não é excluída.';

  @override
  String get deleteAccountPremiumWeb =>
      'Uma assinatura do TabCam Premium não é cancelada: cancele-a no Substack, onde você assinou.';

  @override
  String get deleteAccountPremiumStore =>
      'Uma assinatura do TabCam Premium não é cancelada: ela é gerenciada onde você a comprou.';

  @override
  String get deleteAccountOtherDevices =>
      'Se o TabCam estiver conectado nos seus outros dispositivos, saia neles primeiro para que não enviem os eventos de novo.';

  @override
  String get deleteAccountCancel => 'Cancelar';

  @override
  String get deleteAccountButton => 'Excluir conta';

  @override
  String deleteAccountCouldnt(String error) {
    return 'Não foi possível excluir sua conta: $error';
  }

  @override
  String get deleteAccountDeleting => 'Excluindo sua conta';

  @override
  String get deleteAccountDeleted => 'Conta excluída';

  @override
  String get deleteAccountNotDeleted => 'Conta não excluída';

  @override
  String get deleteAccountClose => 'Fechar';

  @override
  String get deleteAccountTryAgain => 'Tentar de novo';

  @override
  String get deleteAccountStepCloud => 'Excluindo seus arquivos na nuvem…';

  @override
  String deleteAccountStepCloudCount(int done, int total) {
    return 'Excluindo seus arquivos na nuvem ($done de $total)…';
  }

  @override
  String get deleteAccountStepShares => 'Excluindo seus compartilhamentos…';

  @override
  String get deleteAccountStepDevice =>
      'Excluindo seus eventos neste dispositivo…';

  @override
  String deleteAccountStepDeviceCount(int done, int total) {
    return 'Excluindo seus eventos neste dispositivo ($done de $total)…';
  }

  @override
  String get deleteAccountStepSignOut => 'Saindo…';

  @override
  String get deleteAccountSignInAgain =>
      'Entre novamente para excluir sua conta.';

  @override
  String get deleteAccountSignedOutMeanwhile =>
      'Você saiu antes de a conta ser excluída. Seus arquivos na nuvem foram excluídos; entre e exclua a conta de novo para terminar.';

  @override
  String deleteAccountSharesFailed(String reason) {
    return 'Seus arquivos na nuvem foram excluídos, mas não seus compartilhamentos: $reason. Exclua a conta de novo para terminar.';
  }

  @override
  String get deleteAccountSignInAgainShort => 'entre novamente';

  @override
  String deleteAccountSharesFailedBecause(String error) {
    return 'Seus arquivos na nuvem foram excluídos, mas não seus compartilhamentos ($error). Exclua a conta de novo para terminar.';
  }

  @override
  String deleteAccountLeftHere(String error) {
    return 'Sua conta foi excluída e você saiu, mas alguns eventos deste dispositivo não puderam ser excluídos ($error): exclua-os pelo Início.';
  }

  @override
  String deleteAccountSomeFiles(int failed, int total) {
    return '$failed de $total arquivos na nuvem não puderam ser excluídos. Nada mais foi excluído e você continua conectado: tente de novo.';
  }

  @override
  String get deleteAccountKeptAppearing =>
      'Continuaram aparecendo arquivos na sua pasta na nuvem enquanto ela era esvaziada. Nada mais foi excluído: tente de novo.';

  @override
  String deleteAccountFilesHttp(int status) {
    return 'Não foi possível excluir seus arquivos na nuvem (HTTP $status). Nada mais foi excluído: tente de novo.';
  }

  @override
  String deleteAccountFilesCognito(String type) {
    return 'Não foi possível excluir seus arquivos na nuvem ($type). Nada foi excluído: tente de novo.';
  }

  @override
  String deleteAccountFilesError(String error) {
    return 'Não foi possível excluir seus arquivos na nuvem ($error). Nada mais foi excluído: tente de novo.';
  }

  @override
  String get accountPremiumNeedsGoogle => 'O Premium exige entrar com o Google';

  @override
  String get accountSignInWithApple => 'Iniciar sessão com a Apple';

  @override
  String get accountAppleSignInFailed =>
      'Não foi possível iniciar sessão com a Apple';

  @override
  String get accountAppleSignInExpired =>
      'Sua sessão da Apple expirou: entre novamente.';

  @override
  String get accountAppleUnavailable =>
      'Iniciar sessão com a Apple não está disponível neste dispositivo.';

  @override
  String accountPrivateEmail(String provider) {
    return 'ID $provider (e-mail privado)';
  }

  @override
  String get profileLinkedAccounts => 'Contas vinculadas';

  @override
  String get profileLinkedIntro =>
      'Qualquer uma destas contas acessa as mesmas capturas, e o perfil tem as funções de todas.';

  @override
  String get profileOwner => 'Principal';

  @override
  String get profileThisAccount => 'Esta conta';

  @override
  String get profileUnlink => 'Desvincular';

  @override
  String get profileLinkAnother => 'Vincular outra conta';

  @override
  String get profileGetCode => 'Gerar um código';

  @override
  String get profileCodeHow =>
      'Em até 10 minutos, entre com a outra conta e digite este código em Contas vinculadas.';

  @override
  String get profileCopyCode => 'Copiar o código';

  @override
  String get profileHaveCode =>
      'Tem um código da sua outra conta? Digite-o para vincular esta conta a ela.';

  @override
  String get profileCodeLabel => 'Código de vinculação';

  @override
  String get profileLinkThis => 'Vincular esta conta';

  @override
  String get profileLinkThisNote =>
      'Esta conta passa a usar o perfil e as capturas da outra conta.';

  @override
  String get profileCodeWrong =>
      'Esse código está errado, já foi usado ou expirou.';

  @override
  String get profileCantLink =>
      'Esta conta não pode ser vinculada: tem capturas próprias na nuvem ou outras contas vinculadas a ela.';

  @override
  String get profileTooManyTries =>
      'Tentativas demais: espere um minuto e tente de novo.';

  @override
  String profileLinkFailed(String error) {
    return 'Não foi possível vincular: $error';
  }

  @override
  String profileLinked(String profileId) {
    return 'Vinculada: esta conta agora usa o perfil $profileId';
  }

  @override
  String profileId(String profileId) {
    return 'Perfil: $profileId';
  }

  @override
  String profileRoles(String roles) {
    return 'Funções: $roles';
  }

  @override
  String get profileNotOwner =>
      'Só a conta principal do perfil pode excluí-lo. Para sair, desvincule esta conta em Contas vinculadas.';

  @override
  String accountSignedInWith(String provider) {
    return 'Conectado com $provider';
  }

  @override
  String get accountDeleteNote =>
      'Exclui seus eventos na nuvem e neste dispositivo, e seus compartilhamentos.';

  @override
  String get homeAddDocument => 'Documento';

  @override
  String get homeAddDocumentDetail => 'Arquivos PDF';

  @override
  String get eventAddDocument => 'Documento';

  @override
  String get eventAddDocumentDetail => 'Arquivos PDF';

  @override
  String get eventRenameFile => 'Renomear arquivo';

  @override
  String get eventFileDetails => 'Detalhes';

  @override
  String get eventLinkCopied => 'Link copiado';

  @override
  String get textViewFixLinedUp =>
      'Tablatura alinhada: as barras e o fim de cada corda coincidem';

  @override
  String get textViewFixAlreadyLinedUp =>
      'As cordas da tablatura já estão alinhadas';

  @override
  String get textViewFixLinedUpPremium =>
      'Tablatura alinhada. Conferir com a música online faz parte do TabCam Premium.';

  @override
  String get welcomeBody =>
      'Digitalize tablaturas de violão, leia-as como texto e compartilhe-as. Entre para começar: suas capturas ficam em todos os dispositivos em que você entrar.';

  @override
  String get dropFilesToAdd => 'Solte os arquivos para adicioná-los';

  @override
  String get deleteAccountAppleCanceled =>
      'Seus arquivos na nuvem foram apagados, mas não sua conta: a confirmação da Apple foi cancelada. Apague sua conta de novo para terminar.';

  @override
  String get deleteAccountAppleOtherId =>
      'Esse é outro Apple ID: confirme com o Apple ID com que você entrou.';

  @override
  String get eventYourFiles => 'Seus arquivos';

  @override
  String eventYourFilesDetail(String owner) {
    return 'Só você e $owner os veem';
  }

  @override
  String eventFilesFrom(String person) {
    return 'De $person';
  }

  @override
  String get eventSomeone => 'alguém';

  @override
  String get eventPublishHint => 'Só você os vê até publicá-los';

  @override
  String get eventPublish => 'Publicar: todos veem';

  @override
  String get eventUnpublish => 'Publicado: toque para retirar';

  @override
  String get eventPublished => 'Publicado';

  @override
  String eventPublishedSnack(String name) {
    return '$name publicado: agora todos veem';
  }

  @override
  String get eventCouldntPublish => 'Não foi possível publicar';

  @override
  String get emailSignInButton => 'Entrar com e-mail';

  @override
  String get emailSignInTitle => 'Entrar com e-mail';

  @override
  String get emailSignInIntro =>
      'Digite seu endereço de e-mail: enviaremos um código para entrar. Sem senha.';

  @override
  String get emailSignInAddress => 'Endereço de e-mail';

  @override
  String get emailSignInSend => 'Enviar código';

  @override
  String emailSignInSent(String email) {
    return 'Enviamos um código para $email. Digite-o aqui, ou toque no link do e-mail.';
  }

  @override
  String get emailSignInCode => 'Código';

  @override
  String get emailSignInVerify => 'Entrar';

  @override
  String get emailSignInResend => 'Enviar um novo código';

  @override
  String get emailSignInOther => 'Usar outro endereço';

  @override
  String get emailSignInBadAddress => 'Isso não é um endereço de e-mail.';

  @override
  String get emailSignInBadCode =>
      'Esse código não está certo ou expirou: confira, ou envie um novo.';

  @override
  String get emailSignInTooMany =>
      'Tentativas demais: espere alguns minutos e tente de novo.';

  @override
  String emailSignInFailed(String error) {
    return 'Não foi possível entrar: $error';
  }

  @override
  String get emailSignInExpired =>
      'Sua sessão com e-mail expirou: entre de novo.';

  @override
  String get emailSignInUnavailable =>
      'Entrar com e-mail não está configurado nesta versão.';

  @override
  String get ownTabsNote =>
      'O TabCam é para músicos praticando com suas próprias tablaturas. Adicione só o que você tem direito de usar: tablaturas que você escreveu, as do seu professor, as que comprou ou as de uso livre.';
}
