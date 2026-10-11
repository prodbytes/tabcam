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
      'Entre para ler tablaturas, compartilhar e ter seus eventos com backup em todos os dispositivos em que você entrar. Sem entrar, você ainda pode capturar; tudo fica neste dispositivo.';

  @override
  String get accountSignInPremium =>
      'Com a sessão iniciada, o TabScan Premium transcreve suas digitalizações na nuvem enquanto sincronizam.';

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
  String get accountPremiumTitle => 'TabScan Premium';

  @override
  String get accountPremiumActive =>
      'Suas digitalizações são transcritos na nuvem enquanto sincronizam: a tablatura em texto aparece sozinha no evento.';

  @override
  String accountPremiumUntil(String date) {
    return 'Premium até $date.';
  }

  @override
  String accountPremiumInactive(String email) {
    return 'O TabScan Premium não está ativo para $email.';
  }

  @override
  String accountPremiumOffer(String email) {
    return 'Tenha cada digitalização transcrita automaticamente na nuvem, com mais precisão do que no celular, e leia tablaturas na web também. Assine com $email.';
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
  String get accountPeopleTitle => 'Compartilhar com pessoas';

  @override
  String get accountPeopleIntro =>
      'As pessoas que você adicionar encontram esta captura ao entrar no TabScan com esse e-mail. Nenhum e-mail é enviado.';

  @override
  String get accountPeopleEmail => 'E-mail';

  @override
  String get accountPeopleAdd => 'Adicionar';

  @override
  String get accountPeopleEnterEmail => 'Digite um endereço de e-mail';

  @override
  String get accountPeopleNone => 'Ainda não compartilhado.';

  @override
  String accountPeopleRemove(String email) {
    return 'Remover $email';
  }

  @override
  String get accountPeopleRoleTooltip => 'O que podem fazer';

  @override
  String get accountPeopleCanEdit => 'Pode editar';

  @override
  String get accountPeopleReadOnly => 'Somente leitura';

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
      'Abre esta captura no TabScan, para você e as pessoas com quem ela é compartilhada';

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
      'Um zip com os vídeos, a tablatura em texto e os links (as fotos e digitalizações estão ocultas)';

  @override
  String get accountShareFilesDetail =>
      'Um zip com tudo: fotos, digitalizações, vídeos, a tablatura em texto e os links';

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
      'O TabScan Premium transcreve suas digitalizações automaticamente.';

  @override
  String get eventUpgrade => 'Assinar';

  @override
  String get eventNotNow => 'Agora não';

  @override
  String get eventNothingToRead =>
      'Nada para ler: adicione uma digitalização ou foto.';

  @override
  String get eventReadingTab => 'Lendo a tablatura…';

  @override
  String get eventInCloud =>
      'Transcrevendo na nuvem. O texto aparece aqui quando terminar.';

  @override
  String get eventNoTab =>
      'Nenhuma tablatura encontrada nas páginas. Digitalize mais perto e com a folha mais plana.';

  @override
  String get eventReadAgain => 'Ler de novo';

  @override
  String get eventReadFailed => 'Falha ao ler a tablatura.';

  @override
  String get eventReadUnsupported =>
      'Para ler tablaturas, use o app para Android ou iOS, ou o TabScan Premium.';

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
  String get eventShareWithPeople => 'Compartilhar com pessoas';

  @override
  String get eventClone => 'Clonar';

  @override
  String get eventShare => 'Compartilhar';

  @override
  String get eventPages => 'Páginas';

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
  String get eventAddFilesDetail => 'Arquivos de imagem e vídeo';

  @override
  String get eventAddLink => 'Link';

  @override
  String get eventAddLinkDetail => 'Uma aula, uma gravação, a música online';

  @override
  String eventSharedBy(String owner, String access) {
    return 'Compartilhado por $owner · $access';
  }

  @override
  String get eventReadOnly => 'Somente leitura';

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
  String get eventSong => 'Música';

  @override
  String get eventArtist => 'Artista';

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
      'A câmera não está permitida: deixe o TabScan usá-la nas configurações do site no navegador.';

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
  String get homeAddLinkDetail => 'Uma aula, uma gravação, a música online';

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
  String get homeLibraryEmpty => 'Ainda não há tablaturas';

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
      'Desculpe, o TabScan está em manutenção. Tente novamente mais tarde.';

  @override
  String get textViewTabCopied => 'Tablatura copiada';

  @override
  String get textViewPutCursorOnFret =>
      'Coloque o cursor sobre um número de traste';

  @override
  String get textViewFixPremium => 'Corrigir faz parte do TabScan Premium';

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
  String get textViewCopy => 'Copiar';

  @override
  String get textViewFix => 'Corrigir';

  @override
  String get textViewLookingOnline =>
      'Procurando a tablatura da música online…';

  @override
  String get textViewCorrect => 'Correto';

  @override
  String get textViewMarkedCorrect =>
      'Marcado como correto: o evento abre no texto';

  @override
  String get textViewMarkCorrect => 'Marcar a leitura como correta';

  @override
  String get textViewFretDown => 'Descer traste (o número sob o cursor)';

  @override
  String get textViewFretUp => 'Subir traste (o número sob o cursor)';

  @override
  String get textViewOvertypeOn =>
      'Sobrescrever: digitar substitui caracteres, as colunas não se movem';

  @override
  String get textViewOvertypeOff =>
      'Inserir: digitar empurra a linha para a direita';

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
}
