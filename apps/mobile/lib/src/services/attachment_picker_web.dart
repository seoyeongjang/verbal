import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'attachment_picker_types.dart';

Future<PickedAttachment?> pickAttachment(AttachmentPickKind kind) async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = false
    ..accept = kind == AttachmentPickKind.image ? 'image/*' : '';
  input.style.display = 'none';

  final body = web.document.body;
  if (body == null) {
    throw StateError('파일 선택기를 열 수 없습니다.');
  }

  final completer = Completer<PickedAttachment?>();

  void complete(PickedAttachment? value) {
    if (!completer.isCompleted) {
      completer.complete(value);
    }
    input.remove();
  }

  void fail(Object error, StackTrace stackTrace) {
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
    input.remove();
  }

  Future<void> readSelection() async {
    final file = input.files?.item(0);
    if (file == null) {
      complete(null);
      return;
    }

    try {
      final buffer = (await file.arrayBuffer().toDart).toDart;
      final bytes = buffer.asUint8List();
      final mimeType = file.type.trim().isEmpty
          ? _mimeTypeFromName(file.name)
          : file.type.trim();
      final previewUrl = mimeType.startsWith('image/')
          ? web.URL.createObjectURL(file)
          : null;
      complete(
        PickedAttachment(
          fileName: file.name,
          mimeType: mimeType,
          sizeBytes: file.size,
          bytes: bytes,
          previewUrl: previewUrl,
        ),
      );
    } catch (error, stackTrace) {
      fail(error, stackTrace);
    }
  }

  input.addEventListener(
    'change',
    ((web.Event _) => unawaited(readSelection())).toJS,
  );
  input.addEventListener('cancel', ((web.Event _) => complete(null)).toJS);

  body.appendChild(input);
  input.click();

  return completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () {
      input.remove();
      return null;
    },
  );
}

String _mimeTypeFromName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) {
    return 'image/png';
  }
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (lower.endsWith('.gif')) {
    return 'image/gif';
  }
  if (lower.endsWith('.webp')) {
    return 'image/webp';
  }
  if (lower.endsWith('.pdf')) {
    return 'application/pdf';
  }
  if (lower.endsWith('.txt')) {
    return 'text/plain';
  }
  if (lower.endsWith('.zip')) {
    return 'application/zip';
  }
  return 'application/octet-stream';
}
