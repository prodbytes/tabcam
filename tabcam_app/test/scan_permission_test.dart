import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabcam_app/capture/page_source.dart';

// What the plugin reports when its fallback can't open the camera app.
const _revoked = CunningDocumentScannerException(
  'error opening camera: Permission Denial: starting Intent '
  '{ act=android.media.action.IMAGE_CAPTURE } with revoked permission '
  'android.permission.CAMERA',
  code: 'ERROR',
);

void main() {
  test('a scan that works asks for nothing', () async {
    var asked = 0;
    final paths = await scanAskingForCamera(
      () async => ['/a.jpg'],
      askForCamera: () async {
        asked++;
        return true;
      },
      notAllowed: 'no camera',
    );
    expect(paths, ['/a.jpg']);
    expect(asked, 0);
  });

  test('without the camera permission it asks, then scans again', () async {
    var scans = 0;
    var asked = 0;
    final paths = await scanAskingForCamera(
      () async {
        if (scans++ == 0) throw _revoked;
        return ['/a.jpg', '/b.jpg'];
      },
      askForCamera: () async {
        asked++;
        return true;
      },
      notAllowed: 'no camera',
    );
    expect(paths, ['/a.jpg', '/b.jpg']);
    expect((scans, asked), (2, 1));
  });

  test('the camera refused, it says so', () async {
    var scans = 0;
    await expectLater(
      scanAskingForCamera(
        () async {
          scans++;
          throw _revoked;
        },
        askForCamera: () async => false,
        notAllowed: 'no camera',
      ),
      throwsA(
        isA<ScanCameraNotAllowed>().having((e) => '$e', 'text', 'no camera'),
      ),
    );
    expect(scans, 1);
  });

  test('other scanner errors pass through', () async {
    const other = CunningDocumentScannerException('boom', code: 'ERROR');
    await expectLater(
      scanAskingForCamera(
        () async => throw other,
        askForCamera: () async => fail('asked for the camera'),
        notAllowed: 'no camera',
      ),
      throwsA(other),
    );
  });
}
