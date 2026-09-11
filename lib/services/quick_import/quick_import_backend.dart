import 'dart:convert';

abstract interface class QuickImportBackend {
  bool get requiresAuthToken;

  Future<String> fetchShareData({
    required String authToken,
    required String shareCode,
  });
}

class QuickImportException implements Exception {
  const QuickImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

String extractWakeUpShareCode(String input) {
  final trimmed = input.trim();
  final labeledCode = RegExp(
    r'分享口令(?:为|是)?\s*[：:]?\s*[「『“\"]?\s*([A-Za-z0-9_-]+)',
  ).firstMatch(trimmed)?.group(1);
  if (labeledCode != null && labeledCode.isNotEmpty) return labeledCode;

  final embeddedCode = RegExp(r'[A-Fa-f0-9]{32}').firstMatch(trimmed)?.group(0);
  return embeddedCode ?? trimmed;
}

String decodeQuickImportApiResponse(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const QuickImportException('服务器响应格式无效');
  }
  final success = decoded['success'] == true;
  final message = decoded['message'] as String? ?? '获取失败';
  if (!success) throw QuickImportException(message);

  final data = decoded['data'];
  final shareData = switch (data) {
    String value => value,
    Map<String, dynamic> value => value['shareData'] as String? ?? '',
    _ => '',
  };
  if (shareData.trim().isEmpty) {
    throw const QuickImportException('分享码已过期或课程表为空');
  }
  return shareData;
}
