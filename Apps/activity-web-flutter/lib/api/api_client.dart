import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

/// HTTP + WebSocket client for the daemon's web gateway. Uses the same origin
/// when the Flutter build is served from the daemon (relative URLs); falls
/// back to `http://localhost:8765` during `flutter run` for development.
class ApiClient {
  final Uri baseUri;
  final http.Client _http;

  ApiClient({Uri? baseUri, http.Client? client})
      : baseUri = baseUri ?? _defaultBase(),
        _http = client ?? http.Client();

  static Uri _defaultBase() {
    if (kDebugMode) {
      return Uri.parse('http://127.0.0.1:8765');
    }
    return Uri.base; // Same origin in production.
  }

  Uri _api(String path, [Map<String, String>? query]) =>
      baseUri.replace(path: path, queryParameters: query);

  Future<StatusResponse> status() async {
    final r = await _http.get(_api('/api/status'));
    _checkOk(r);
    return StatusResponse.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<ProcessesPage> listProcesses({
    String sort = 'memory',
    String order = 'desc',
    int limit = 50,
  }) async {
    final r = await _http.get(_api('/api/processes', {
      'sort': sort,
      'order': order,
      'limit': '$limit',
    }));
    _checkOk(r);
    return ProcessesPage.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<TimelineSession>> timeline({
    DateTime? from,
    DateTime? to,
    int? limit,
  }) async {
    final query = <String, String>{};
    if (from != null) query['from'] = from.toIso8601String();
    if (to != null) query['to'] = to.toIso8601String();
    if (limit != null) query['limit'] = '$limit';
    final r = await _http.get(_api('/api/timeline', query));
    _checkOk(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final sessions = body['sessions'] as List<dynamic>;
    return sessions
        .map((s) => TimelineSession.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  Future<List<dynamic>> rules() async {
    final r = await _http.get(_api('/api/rules'));
    _checkOk(r);
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return body['rules'] as List<dynamic>;
  }

  /// Live MCP audit stream. Re-emits the most recent error if the socket
  /// drops; the dashboard handles reconnection by re-invoking this stream.
  Stream<AuditRecord> auditStream() {
    final wsUri = baseUri.replace(
      scheme: baseUri.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/events',
    );
    final channel = WebSocketChannel.connect(wsUri);
    return channel.stream.map((raw) {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      return AuditRecord.fromJson(json);
    });
  }

  void _checkOk(http.Response r) {
    if (r.statusCode >= 400) {
      throw Exception('HTTP ${r.statusCode}: ${r.body}');
    }
  }
}
