import 'package:socket_inspector/src/socket_event.dart';

class SocketEventFilter {
  final Set<SocketEventType> allowedTypes;
  final Set<EventSeverity> allowedSeverities;
  final DateTime? startTime;
  final DateTime? endTime;
  final String? searchText;
  final bool useRegex;
  final String? eventNameFilter;
  final int? maxLatency;
  final int? minDataSize;
  final int? maxDataSize;

  const SocketEventFilter({
    this.allowedTypes = const {},
    this.allowedSeverities = const {},
    this.startTime,
    this.endTime,
    this.searchText,
    this.useRegex = false,
    this.eventNameFilter,
    this.maxLatency,
    this.minDataSize,
    this.maxDataSize,
  });

  bool matches(SocketEvent event) {
    // Filter by event type
    if (allowedTypes.isNotEmpty && !allowedTypes.contains(event.type)) {
      return false;
    }

    // Filter by severity
    if (allowedSeverities.isNotEmpty &&
        !allowedSeverities.contains(event.severity)) {
      return false;
    }

    // Filter by time range
    if (startTime != null && event.timestamp.isBefore(startTime!)) {
      return false;
    }
    if (endTime != null && event.timestamp.isAfter(endTime!)) {
      return false;
    }

    // Filter by event name
    if (eventNameFilter != null && eventNameFilter!.isNotEmpty) {
      if (useRegex) {
        try {
          final regex = RegExp(eventNameFilter!, caseSensitive: false);
          if (event.eventName == null || !regex.hasMatch(event.eventName!)) {
            return false;
          }
        } catch (_) {
          // Invalid regex, fallback to contains
          if (event.eventName == null ||
              !event.eventName!.toLowerCase().contains(
                eventNameFilter!.toLowerCase(),
              )) {
            return false;
          }
        }
      } else {
        if (event.eventName == null ||
            !event.eventName!.toLowerCase().contains(
              eventNameFilter!.toLowerCase(),
            )) {
          return false;
        }
      }
    }

    // Filter by search text in data
    if (searchText != null && searchText!.isNotEmpty) {
      final searchTarget =
          "${event.eventName ?? ''} ${event.rawData ?? ''} ${event.metrics.errorMessage ?? ''}";
      if (useRegex) {
        try {
          final regex = RegExp(searchText!, caseSensitive: false);
          if (!regex.hasMatch(searchTarget)) {
            return false;
          }
        } catch (_) {
          // Invalid regex, fallback to contains
          if (!searchTarget.toLowerCase().contains(searchText!.toLowerCase())) {
            return false;
          }
        }
      } else {
        if (!searchTarget.toLowerCase().contains(searchText!.toLowerCase())) {
          return false;
        }
      }
    }

    // Filter by latency
    if (maxLatency != null && event.metrics.latencyMs != null) {
      if (event.metrics.latencyMs! > maxLatency!) {
        return false;
      }
    }

    // Filter by data size
    if (minDataSize != null && event.dataSizeBytes < minDataSize!) {
      return false;
    }
    if (maxDataSize != null && event.dataSizeBytes > maxDataSize!) {
      return false;
    }

    return true;
  }

  SocketEventFilter copyWith({
    Set<SocketEventType>? allowedTypes,
    Set<EventSeverity>? allowedSeverities,
    DateTime? startTime,
    DateTime? endTime,
    String? searchText,
    bool? useRegex,
    String? eventNameFilter,
    int? maxLatency,
    int? minDataSize,
    int? maxDataSize,
  }) {
    return SocketEventFilter(
      allowedTypes: allowedTypes ?? this.allowedTypes,
      allowedSeverities: allowedSeverities ?? this.allowedSeverities,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      searchText: searchText ?? this.searchText,
      useRegex: useRegex ?? this.useRegex,
      eventNameFilter: eventNameFilter ?? this.eventNameFilter,
      maxLatency: maxLatency ?? this.maxLatency,
      minDataSize: minDataSize ?? this.minDataSize,
      maxDataSize: maxDataSize ?? this.maxDataSize,
    );
  }

  bool get hasActiveFilters {
    return allowedTypes.isNotEmpty ||
        allowedSeverities.isNotEmpty ||
        startTime != null ||
        endTime != null ||
        (searchText?.isNotEmpty ?? false) ||
        (eventNameFilter?.isNotEmpty ?? false) ||
        maxLatency != null ||
        minDataSize != null ||
        maxDataSize != null;
  }
}

class SocketEventStats {
  final int totalEvents;
  final int connectEvents;
  final int disconnectEvents;
  final int messagesSent;
  final int messagesReceived;
  final int errorEvents;
  final double averageLatency;
  final int totalDataTransferred;
  final DateTime? firstEventTime;
  final DateTime? lastEventTime;
  final Map<SocketEventType, int> eventTypeCounts;
  final Map<EventSeverity, int> severityCounts;

  const SocketEventStats({
    required this.totalEvents,
    required this.connectEvents,
    required this.disconnectEvents,
    required this.messagesSent,
    required this.messagesReceived,
    required this.errorEvents,
    required this.averageLatency,
    required this.totalDataTransferred,
    this.firstEventTime,
    this.lastEventTime,
    required this.eventTypeCounts,
    required this.severityCounts,
  });

  static SocketEventStats fromEvents(List<SocketEvent> events) {
    if (events.isEmpty) {
      return const SocketEventStats(
        totalEvents: 0,
        connectEvents: 0,
        disconnectEvents: 0,
        messagesSent: 0,
        messagesReceived: 0,
        errorEvents: 0,
        averageLatency: 0.0,
        totalDataTransferred: 0,
        eventTypeCounts: {},
        severityCounts: {},
      );
    }

    final eventTypeCounts = <SocketEventType, int>{};
    final severityCounts = <EventSeverity, int>{};
    var totalLatency = 0;
    var latencyCount = 0;
    var totalDataTransferred = 0;

    for (final event in events) {
      eventTypeCounts[event.type] = (eventTypeCounts[event.type] ?? 0) + 1;
      severityCounts[event.severity] =
          (severityCounts[event.severity] ?? 0) + 1;

      if (event.metrics.latencyMs != null) {
        totalLatency += event.metrics.latencyMs!;
        latencyCount++;
      }

      totalDataTransferred += event.dataSizeBytes;
    }

    events.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return SocketEventStats(
      totalEvents: events.length,
      connectEvents: eventTypeCounts[SocketEventType.connect] ?? 0,
      disconnectEvents: eventTypeCounts[SocketEventType.disconnect] ?? 0,
      messagesSent: eventTypeCounts[SocketEventType.messageSent] ?? 0,
      messagesReceived: eventTypeCounts[SocketEventType.messageReceived] ?? 0,
      errorEvents: eventTypeCounts[SocketEventType.error] ?? 0,
      averageLatency: latencyCount > 0 ? totalLatency / latencyCount : 0.0,
      totalDataTransferred: totalDataTransferred,
      firstEventTime: events.isNotEmpty ? events.first.timestamp : null,
      lastEventTime: events.isNotEmpty ? events.last.timestamp : null,
      eventTypeCounts: eventTypeCounts,
      severityCounts: severityCounts,
    );
  }

  Map<String, dynamic> toJson() => {
    'totalEvents': totalEvents,
    'connectEvents': connectEvents,
    'disconnectEvents': disconnectEvents,
    'messagesSent': messagesSent,
    'messagesReceived': messagesReceived,
    'errorEvents': errorEvents,
    'averageLatency': averageLatency,
    'totalDataTransferred': totalDataTransferred,
    'firstEventTime': firstEventTime?.toIso8601String(),
    'lastEventTime': lastEventTime?.toIso8601String(),
    'eventTypeCounts': eventTypeCounts.map((k, v) => MapEntry(k.name, v)),
    'severityCounts': severityCounts.map((k, v) => MapEntry(k.name, v)),
  };
}
