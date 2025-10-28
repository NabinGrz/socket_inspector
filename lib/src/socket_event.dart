import 'dart:convert';

import 'package:equatable/equatable.dart';

enum SocketEventType {
  connect,
  disconnect,
  messageSent,
  messageReceived,
  error,
  reconnect,
  connectionAttempt,
  timeout,
  ping,
  pong,
}

enum EventSeverity { info, warning, error, critical }

class SocketEventMetrics {
  final int? latencyMs;
  final int? dataSizeBytes;
  final String? errorCode;
  final String? errorMessage;
  final Duration? connectionDuration;
  final int? retryCount;

  const SocketEventMetrics({
    this.latencyMs,
    this.dataSizeBytes,
    this.errorCode,
    this.errorMessage,
    this.connectionDuration,
    this.retryCount,
  });

  Map<String, dynamic> toJson() => {
    'latencyMs': latencyMs,
    'dataSizeBytes': dataSizeBytes,
    'errorCode': errorCode,
    'errorMessage': errorMessage,
    'connectionDurationMs': connectionDuration?.inMilliseconds,
    'retryCount': retryCount,
  };

  factory SocketEventMetrics.fromJson(Map<String, dynamic> json) {
    return SocketEventMetrics(
      latencyMs: json['latencyMs'],
      dataSizeBytes: json['dataSizeBytes'],
      errorCode: json['errorCode'],
      errorMessage: json['errorMessage'],
      connectionDuration:
          json['connectionDurationMs'] != null
              ? Duration(milliseconds: json['connectionDurationMs'])
              : null,
      retryCount: json['retryCount'],
    );
  }
}

class SocketEvent extends Equatable {
  final String id;
  final SocketEventType type;
  final String? eventName;
  final dynamic data;
  final DateTime timestamp;
  final EventSeverity severity;
  final SocketEventMetrics metrics;
  final String? sessionId;
  final Map<String, dynamic>? headers;
  final String? rawData;

  SocketEvent({
    required this.type,
    this.eventName,
    this.data,
    this.severity = EventSeverity.info,
    this.metrics = const SocketEventMetrics(),
    this.sessionId,
    this.headers,
    String? id,
  }) : timestamp = DateTime.now(),
       id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
       rawData = _serializeData(data);

  static String? _serializeData(dynamic data) {
    if (data == null) return null;
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }

  String get formattedData {
    if (data == null) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  int get dataSizeBytes => rawData?.length ?? 0;

  String get formattedTimestamp {
    return "${timestamp.hour.toString().padLeft(2, '0')}:"
        "${timestamp.minute.toString().padLeft(2, '0')}:"
        "${timestamp.second.toString().padLeft(2, '0')}."
        "${timestamp.millisecond.toString().padLeft(3, '0')}";
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'eventName': eventName,
    'data': data,
    'timestamp': timestamp.toIso8601String(),
    'severity': severity.name,
    'metrics': metrics.toJson(),
    'sessionId': sessionId,
    'headers': headers,
    'rawData': rawData,
    'dataSizeBytes': dataSizeBytes,
  };

  factory SocketEvent.fromJson(Map<String, dynamic> json) {
    return SocketEvent(
      type: SocketEventType.values.firstWhere((e) => e.name == json['type']),
      eventName: json['eventName'],
      data: json['data'],
      severity: EventSeverity.values.firstWhere(
        (e) => e.name == json['severity'],
      ),
      metrics: SocketEventMetrics.fromJson(json['metrics'] ?? {}),
      sessionId: json['sessionId'],
      headers: json['headers'],
      id: json['id'],
    );
  }

  @override
  List<Object?> get props => [
    id,
    type,
    eventName,
    data,
    timestamp,
    severity,
    metrics,
    sessionId,
  ];
}
