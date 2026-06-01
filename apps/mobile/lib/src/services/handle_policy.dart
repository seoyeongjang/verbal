const handleMinLength = 3;
const handleMaxLength = 30;

final _handleAllowedCharacters = RegExp(
  r'^[A-Za-z0-9_\u1100-\u11FF\u3130-\u318F\uAC00-\uD7A3\u3040-\u30FF\u31F0-\u31FF\u3400-\u4DBF\u4E00-\u9FFF]+$',
);

String normalizeHandle(String value) {
  final trimmed = value.trim();
  final withoutPrefix = trimmed.startsWith('@')
      ? trimmed.substring(1)
      : trimmed;
  return withoutPrefix.toLowerCase();
}

String? validateHandle(String value) {
  final handle = normalizeHandle(value);
  if (handle.isEmpty) {
    return '아이디를 입력해 주세요.';
  }
  if (handle.length < handleMinLength || handle.length > handleMaxLength) {
    return '아이디는 $handleMinLength~$handleMaxLength자여야 합니다.';
  }
  if (!_handleAllowedCharacters.hasMatch(handle)) {
    return '아이디는 한글, 영어, 일본어, 중국어, 숫자, _만 사용할 수 있습니다.';
  }
  return null;
}

void ensureValidHandle(String value) {
  final error = validateHandle(value);
  if (error != null) {
    throw ArgumentError(error);
  }
}

List<String> normalizeAndValidateHandles(Iterable<String> values) {
  return values.map((value) {
    ensureValidHandle(value);
    return normalizeHandle(value);
  }).toList();
}
