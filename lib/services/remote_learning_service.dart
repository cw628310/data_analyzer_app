import 'dart:convert';

import 'package:http/http.dart' as http;

class RemoteLearningService {
  static const String _baseUrl = String.fromEnvironment(
    'LEARNING_API_BASE_URL',
    defaultValue: '',
  );

  bool get enabled => _baseUrl.trim().isNotEmpty;

  Future<String> learnSideSummary({
    required String sideName,
    required String reference,
    required String summary,
  }) {
    return _learn(
      path: '/learn/side-summary',
      fallbackSummary: summary,
      payload: {
        'sideName': sideName,
        'reference': reference,
        'summary': summary,
      },
    );
  }

  Future<String> learnCombinedSummary({
    required String reference,
    required String leftReference,
    required String rightReference,
    required String summary,
  }) {
    return _learn(
      path: '/learn/combined-summary',
      fallbackSummary: summary,
      payload: {
        'reference': reference,
        'leftReference': leftReference,
        'rightReference': rightReference,
        'summary': summary,
      },
    );
  }

  Future<String> _learn({
    required String path,
    required String fallbackSummary,
    required Map<String, Object?> payload,
  }) async {
    if (!enabled) {
      return fallbackSummary;
    }

    try {
      final uri = Uri.parse('${_baseUrl.trim()}$path');
      final response = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return fallbackSummary;
      }

      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) {
        final optimizedSummary = data['optimizedSummary'];
        if (optimizedSummary is String && optimizedSummary.trim().isNotEmpty) {
          return optimizedSummary;
        }
      }
      return fallbackSummary;
    } catch (_) {
      return fallbackSummary;
    }
  }
}