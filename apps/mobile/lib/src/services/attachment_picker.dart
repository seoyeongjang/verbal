import 'attachment_picker_stub.dart'
    if (dart.library.html) 'attachment_picker_web.dart'
    as platform;
import 'attachment_picker_types.dart';

export 'attachment_picker_types.dart';

class AttachmentPicker {
  const AttachmentPicker._();

  static AttachmentPickHandler? debugPick;

  static Future<PickedAttachment?> pick(AttachmentPickKind kind) {
    final override = debugPick;
    if (override != null) {
      return override(kind);
    }
    return platform.pickAttachment(kind);
  }
}
