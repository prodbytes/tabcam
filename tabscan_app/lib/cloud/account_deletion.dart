import 'package:flutter/foundation.dart';

import 'cloud_ocr.dart';
import 'cloud_sync.dart';
import 'cognito.dart';
import 's3.dart';
import 'share_api.dart';

/// What deleting the account is doing.
enum DeletionStep {
  /// Deleting the files in the user's cloud folder.
  cloud,

  /// Deleting the shares (both ways) and the identity, through the share
  /// API.
  shares,

  /// Deleting the events on this device.
  device,

  /// Signing out.
  signOut,
}

/// How far deleting the account is: the step, and in it, [done] of
/// [total] (files or events; 0 of 0 when not counted).
@immutable
class DeletionProgress {
  const DeletionProgress(this.step, {this.done = 0, this.total = 0});

  final DeletionStep step;
  final int done;
  final int total;

  /// "Deleting your files in the cloud (120 of 300)…".
  String get label {
    final count = total > 0 ? ' ($done of $total)' : '';
    return switch (step) {
      DeletionStep.cloud => 'Deleting your files in the cloud$count…',
      DeletionStep.shares => 'Deleting your shares…',
      DeletionStep.device => 'Deleting your events on this device$count…',
      DeletionStep.signOut => 'Signing out…',
    };
  }
}

/// Why deleting the account stopped: what was and wasn't deleted.
class AccountDeletionException implements Exception {
  AccountDeletionException(this.message, {this.deleted = false});

  final String message;

  /// The account was deleted (and the user signed out) all the same: only
  /// something on this device stayed.
  final bool deleted;

  @override
  String toString() => message;
}

/// Deletes the signed-in user's TabScan account, in an order that never
/// leaves them signed out with something undeleted:
///
/// 1. every object in their folder (`<identity>/`: events, page files,
///    transcriptions), listed then deleted in batches, with the identity's
///    own credentials;
/// 2. through the share API: the grants of their captures, the grants to
///    their address, their record in the cloud OCR service, and their
///    Cognito identity;
/// 3. their events on this device (their own, those made signed out, and
///    copies of captures shared with them; another account's stay);
/// 4. signing out.
///
/// Sync is paused throughout, so no pass uploads what's being deleted. A
/// step that fails stops it, with an [AccountDeletionException] saying what
/// was deleted; the user stays signed in, sync resumes, and running it
/// again picks up where it stopped (each step is safe to repeat).
class AccountDeletion {
  AccountDeletion(this.sync);

  final CloudSync sync;

  /// Rounds of listing and deleting the folder: a transcription written
  /// while it's being emptied is caught by the next round.
  static const int rounds = 3;

  Future<void> run({void Function(DeletionProgress)? onProgress}) async {
    void report(DeletionStep step, [int done = 0, int total = 0]) =>
        onProgress?.call(DeletionProgress(step, done: done, total: total));
    final auth = sync.auth;
    final token = auth.idToken;
    final user = auth.user?.id;
    if (token == null || user == null) {
      throw AccountDeletionException('Sign in again to delete your account.');
    }
    report(DeletionStep.cloud);
    await sync.pause();
    final String identity;
    try {
      identity = await _emptyFolder(token, report);
      if (auth.user?.id != user) {
        throw AccountDeletionException(
          'You signed out before your account was deleted. Your files in '
          'the cloud were deleted; sign in and delete it again to finish.',
        );
      }
      if (sync.shares case final shares?) {
        report(DeletionStep.shares);
        try {
          // A token refreshed meanwhile is the same user's.
          await shares.deleteAccount(auth.idToken ?? token);
        } on ShareApiException catch (e) {
          throw AccountDeletionException(
            'Your files in the cloud were deleted, but not your shares: '
            '${e.statusCode == 401 ? 'sign in again' : e.message}. '
            'Delete your account again to finish.',
          );
        } on Object catch (e) {
          throw AccountDeletionException(
            'Your files in the cloud were deleted, but not your shares '
            '($e). Delete your account again to finish.',
          );
        }
      }
    } on Object {
      sync.resume();
      rethrow;
    }
    // The account is gone from the cloud: sign out whatever happens here,
    // and say so if something stayed.
    Object? leftHere;
    try {
      await _deleteHere(identity, report);
    } on Object catch (e) {
      debugPrint('TabScan: deleting the events on this device failed: $e');
      leftHere = e;
    }
    report(DeletionStep.signOut);
    await auth.signOut();
    if (leftHere != null) {
      throw AccountDeletionException(
        'Your account was deleted and you were signed out, but some events '
        "on this device couldn't be deleted ($leftHere): delete them from "
        'Home.',
        deleted: true,
      );
    }
  }

  /// Deletes every object under the user's folder; their identity ID.
  Future<String> _emptyFolder(
    String token,
    void Function(DeletionStep, [int, int]) report,
  ) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final session = await sync.credentials.session(token);
        final identity = session.identityId;
        final creds = session.credentials;
        for (var round = 0; round < rounds; round++) {
          final keys = (await sync.bucket.listETags(
            '$identity/',
            credentials: creds,
          )).keys.toList();
          if (keys.isEmpty) return identity;
          final failed = <String>[];
          var done = 0;
          report(DeletionStep.cloud, 0, keys.length);
          for (var i = 0; i < keys.length; i += S3Bucket.maxBatch) {
            final batch = keys.sublist(
              i,
              i + S3Bucket.maxBatch < keys.length
                  ? i + S3Bucket.maxBatch
                  : keys.length,
            );
            failed.addAll(
              await sync.bucket.deleteBatch(batch, credentials: creds),
            );
            done += batch.length;
            report(DeletionStep.cloud, done, keys.length);
          }
          if (failed.isNotEmpty) {
            debugPrint('TabScan: account deletion left $failed');
            throw AccountDeletionException(
              "${failed.length} of ${keys.length} files in the cloud couldn't "
              'be deleted. Nothing else was deleted, and you are still '
              'signed in: try again.',
            );
          }
        }
        throw AccountDeletionException(
          'Files kept appearing in your cloud folder while it was being '
          'emptied. Nothing else was deleted: try again.',
        );
      } on S3Exception catch (e) {
        // Expired credentials, or a clock S3 just corrected: once more.
        if (attempt == 0 && (e.credentialsRejected || e.clockSkewed)) {
          if (e.credentialsRejected) sync.credentials.clear();
          continue;
        }
        throw AccountDeletionException(
          "Your files in the cloud couldn't be deleted (HTTP "
          '${e.statusCode}). Nothing else was deleted: try again.',
        );
      } on CognitoException catch (e) {
        throw AccountDeletionException(
          e.needsSignIn
              ? 'Sign in again to delete your account.'
              : "Your files in the cloud couldn't be deleted (${e.type}). "
                    'Nothing was deleted: try again.',
        );
      } on AccountDeletionException {
        rethrow;
      } on Object catch (e) {
        throw AccountDeletionException(
          "Your files in the cloud couldn't be deleted ($e). Nothing else "
          'was deleted: try again.',
        );
      }
    }
  }

  /// Deletes the user's events on this device ([identity]'s, those of no
  /// one yet, and copies of captures shared with them), tombstones too,
  /// and forgets what synced.
  Future<void> _deleteHere(
    String identity,
    void Function(DeletionStep, [int, int]) report,
  ) async {
    final library = sync.library;
    final mine = [
      for (final e in library.all)
        if (e.isShared || e.owner == null || e.owner == identity) e,
    ];
    report(DeletionStep.device, 0, mine.length);
    for (final (i, event) in mine.indexed) {
      await library.removeLocal(event);
      report(DeletionStep.device, i + 1, mine.length);
    }
    await library.writeMeta(CloudSync.stateName, '{}');
    await library.writeMeta(CloudOcr.stateName, '{}');
  }
}
