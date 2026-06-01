import 'dart:typed_data';

enum AttachmentPickKind { image, file }

typedef AttachmentPickHandler =
    Future<PickedAttachment?> Function(AttachmentPickKind kind);

class PickedAttachment {
  const PickedAttachment({
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.bytes,
    this.previewUrl,
  });

  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final Uint8List bytes;
  final String? previewUrl;

  bool get isImage => mimeType.toLowerCase().startsWith('image/');
}
