import 'dart:convert';
import 'dart:io';

Future<bool?> realtimeRelayProviderAvailable({
  required String relayRootUrl,
  required String provider,
  Duration timeout = const Duration(milliseconds: 700),
}) async {
  final uri = Uri.tryParse(relayRootUrl.trim());
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  final healthUri = uri.replace(path: '/', query: '', fragment: '');
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(healthUri).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final body = await utf8.decodeStream(response).timeout(timeout);
    final data = jsonDecode(body);
    if (data is! Map<String, dynamic>) {
      return null;
    }
    final providers = data['providers'];
    if (providers is! Map<String, dynamic>) {
      return null;
    }
    final value = providers[provider.trim().toLowerCase()];
    return value is bool ? value : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}
