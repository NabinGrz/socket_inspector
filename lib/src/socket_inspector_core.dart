import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:socket_inspector/src/socket_event.dart';
import 'package:socket_inspector/src/socket_filter.dart';

class SocketSession {
  final String id;
  final String name;
  final DateTime startTime;
  DateTime? endTime;
  final List<SocketEvent> events;
  final String? description;

  SocketSession({
    required this.id,
    required this.name,
    required this.startTime,
    this.endTime,
    this.events = const [],
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime?.toIso8601String(),
    'events': events.map((e) => e.toJson()).toList(),
    'description': description,
  };

  factory SocketSession.fromJson(Map<String, dynamic> json) {
    return SocketSession(
      id: json['id'],
      name: json['name'],
      startTime: DateTime.parse(json['startTime']),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      events:
          (json['events'] as List?)
              ?.map((e) => SocketEvent.fromJson(e))
              .toList() ??
          [],
      description: json['description'],
    );
  }
}

class SocketInspectorCore {
  static final SocketInspectorCore _instance = SocketInspectorCore._internal();
  factory SocketInspectorCore() => _instance;
  SocketInspectorCore._internal();

  final _controller = StreamController<SocketEvent>.broadcast();
  final List<SocketEvent> _events = [];
  final List<SocketSession> _sessions = [];
  SocketSession? _currentSession;
  SocketEventFilter _filter = const SocketEventFilter();

  Stream<SocketEvent> get stream => _controller.stream;
  List<SocketEvent> get history => List.unmodifiable(_events);
  List<SocketEvent> get filteredHistory =>
      _events.where(_filter.matches).toList();
  List<SocketSession> get sessions => List.unmodifiable(_sessions);
  SocketSession? get currentSession => _currentSession;
  SocketEventFilter get filter => _filter;
  SocketEventStats get stats => SocketEventStats.fromEvents(filteredHistory);

  void startSession(String name, {String? description}) {
    if (_currentSession != null) {
      endCurrentSession();
    }

    _currentSession = SocketSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      startTime: DateTime.now(),
      description: description,
    );
    _sessions.add(_currentSession!);
  }

  void endCurrentSession() {
    if (_currentSession != null) {
      _currentSession!.endTime = DateTime.now();
      _currentSession = null;
    }
  }

  void log(SocketEvent event, [String? message]) {
    _events.add(event);
    _currentSession?.events.add(event);
    _controller.add(event);

    if (message != null) {
      print("SocketInspector: $message");
    }

    // Auto-save session periodically
    _autoSaveSession();
  }

  void updateFilter(SocketEventFilter newFilter) {
    _filter = newFilter;
    // Notify listeners that filter has changed
    if (_events.isNotEmpty) {
      _controller.add(_events.last);
    }
  }

  void clear() {
    _events.clear();
    _currentSession?.events.clear();
  }

  void clearAll() {
    _events.clear();
    _sessions.clear();
    _currentSession = null;
  }

  // Export functionality
  Future<String> exportToJson({List<SocketEvent>? events}) async {
    final eventsToExport = events ?? filteredHistory;
    final exportData = {
      'exportTime': DateTime.now().toIso8601String(),
      'filter': _serializeFilter(),
      'stats': stats.toJson(),
      'events': eventsToExport.map((e) => e.toJson()).toList(),
      'session': _currentSession?.toJson(),
    };
    return jsonEncode(exportData);
  }

  Future<String> exportToCsv({List<SocketEvent>? events}) async {
    final eventsToExport = events ?? filteredHistory;
    final buffer = StringBuffer();

    // CSV header
    buffer.writeln(
      'Timestamp,Type,Event Name,Data Size (bytes),Latency (ms),Severity,Error Code,Data Preview',
    );

    for (final event in eventsToExport) {
      final dataPreview =
          event.rawData?.replaceAll('\n', ' ').replaceAll('"', '""') ?? '';
      final preview =
          dataPreview.length > 100
              ? '${dataPreview.substring(0, 100)}...'
              : dataPreview;

      buffer.writeln(
        [
          event.timestamp.toIso8601String(),
          event.type.name,
          event.eventName ?? '',
          event.dataSizeBytes,
          event.metrics.latencyMs ?? '',
          event.severity.name,
          event.metrics.errorCode ?? '',
          '"$preview"',
        ].join(','),
      );
    }

    return buffer.toString();
  }

  Future<File> saveSession(SocketSession session) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/socket_session_${session.id}.json');
    await file.writeAsString(jsonEncode(session.toJson()));
    return file;
  }

  Future<SocketSession> loadSession(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final json = jsonDecode(content);
    return SocketSession.fromJson(json);
  }

  Future<List<File>> getSessionFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    final files =
        directory
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  f.path.contains('socket_session_') &&
                  f.path.endsWith('.json'),
            )
            .toList();
    return files;
  }

  void _autoSaveSession() {
    if (_currentSession != null && _currentSession!.events.length % 10 == 0) {
      saveSession(_currentSession!);
    }
  }

  Map<String, dynamic> _serializeFilter() {
    return {
      'allowedTypes': _filter.allowedTypes.map((e) => e.name).toList(),
      'allowedSeverities':
          _filter.allowedSeverities.map((e) => e.name).toList(),
      'startTime': _filter.startTime?.toIso8601String(),
      'endTime': _filter.endTime?.toIso8601String(),
      'searchText': _filter.searchText,
      'useRegex': _filter.useRegex,
      'eventNameFilter': _filter.eventNameFilter,
      'maxLatency': _filter.maxLatency,
      'minDataSize': _filter.minDataSize,
      'maxDataSize': _filter.maxDataSize,
    };
  }

  // Replay functionality
  Future<void> replayEvents(
    List<SocketEvent> events, {
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    for (final event in events) {
      await Future.delayed(delay);
      _controller.add(event);
    }
  }

  // Performance monitoring
  void trackLatency(String eventId, DateTime startTime) {
    final endTime = DateTime.now();
    final latency = endTime.difference(startTime).inMilliseconds;

    // Find and update the event with latency
    final eventIndex = _events.indexWhere((e) => e.id == eventId);
    if (eventIndex != -1) {
      final event = _events[eventIndex];
      final updatedEvent = SocketEvent(
        type: event.type,
        eventName: event.eventName,
        data: event.data,
        severity: event.severity,
        metrics: SocketEventMetrics(
          latencyMs: latency,
          dataSizeBytes: event.metrics.dataSizeBytes,
          errorCode: event.metrics.errorCode,
          errorMessage: event.metrics.errorMessage,
          connectionDuration: event.metrics.connectionDuration,
          retryCount: event.metrics.retryCount,
        ),
        sessionId: event.sessionId,
        headers: event.headers,
        id: event.id,
      );

      _events[eventIndex] = updatedEvent;
      _controller.add(updatedEvent);
    }
  }
}
