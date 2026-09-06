import 'dart:convert';
import 'dart:io';

class WakeUpScheduleException implements Exception {
  const WakeUpScheduleException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WakeUpScheduleService {
  const WakeUpScheduleService();

  Future<String> fetchShareData({
    required String authToken,
    required String shareCode,
  }) async {
    final uri = Uri.https('wakeup.api.pmnet.work', '/share', {
      'authToken': authToken,
      'shareCode': shareCode,
    });
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
        throw WakeUpScheduleException('服务器返回 ${response.statusCode}');
      }
      return decodeWakeUpShareResponse(body);
    } on WakeUpScheduleException {
      rethrow;
    } on SocketException {
      throw const WakeUpScheduleException('无法连接课程表服务器，请检查网络');
    } on FormatException {
      throw const WakeUpScheduleException('服务器返回了无法解析的数据');
    } catch (_) {
      throw const WakeUpScheduleException('课程表同步失败，请稍后重试');
    } finally {
      client.close(force: true);
    }
  }
}

String decodeWakeUpShareResponse(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const WakeUpScheduleException('服务器响应格式无效');
  }
  final success = decoded['success'] == true;
  final message = decoded['message'] as String? ?? '获取失败';
  if (!success) throw WakeUpScheduleException(message);
  final data = decoded['data'];
  final shareData = data is Map<String, dynamic>
      ? data['shareData'] as String? ?? ''
      : '';
  if (shareData.trim().isEmpty) {
    throw const WakeUpScheduleException('分享码已过期或课程表为空');
  }
  return shareData;
}
