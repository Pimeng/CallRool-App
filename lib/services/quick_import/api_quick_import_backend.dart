import 'dart:convert';
import 'dart:io';

import 'quick_import_backend.dart';

class ApiQuickImportBackend implements QuickImportBackend {
  const ApiQuickImportBackend();

  static final Uri _endpoint = Uri.https('wakeup.api.pmnet.work', '/share');

  @override
  bool get requiresAuthToken => true;

  @override
  Future<String> fetchShareData({
    required String authToken,
    required String shareCode,
  }) async {
    final uri = _endpoint.replace(
      queryParameters: {'authToken': authToken, 'shareCode': shareCode},
    );
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final body = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw QuickImportException('服务器返回 ${response.statusCode}');
      }
      return decodeQuickImportApiResponse(body);
    } on QuickImportException {
      rethrow;
    } on SocketException {
      throw const QuickImportException('无法连接课程表服务器，请检查网络');
    } on FormatException {
      throw const QuickImportException('服务器返回了无法解析的数据');
    } catch (_) {
      throw const QuickImportException('课程表同步失败，请稍后重试');
    } finally {
      client.close(force: true);
    }
  }
}
