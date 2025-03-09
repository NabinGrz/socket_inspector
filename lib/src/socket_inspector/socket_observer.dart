import 'dart:collection';
import 'dart:convert';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:intl/intl.dart';

class SocketLog {
  final String timestamp;
  final String event;
  final String? message;
  final int? messageSize; // Size of the message in bytes
  final bool? isSending;

  SocketLog({
    required this.timestamp,
    required this.event,
    this.message,
    this.messageSize,
    this.isSending,
  });
}

class SocketObserver {
  static final SocketObserver _instance = SocketObserver._internal();

  // Store logs with a limit to prevent memory overflow.
  static const int maxLogs = 1000;
  final List<SocketLog> _logs = [];

  final List<void Function(List<SocketLog>)> _listeners = [];
  bool _isRecording = true; // Enable/disable logging dynamically

  SocketObserver._internal();

  static SocketObserver get instance => _instance;
  late io.Socket connectedSocket;
  String formattedTimestamp(DateTime timestamp) {
    return DateFormat('hh:mm:ss a').format(timestamp); // AM/PM format
  }

  /// Logs a socket event
  void logEvent(String event, {String? message, bool? isSending}) {
    if (!_isRecording) return;

    final int? messageSize =
        message != null ? utf8.encode(message).length : null;

    final log = SocketLog(
      timestamp: formattedTimestamp(DateTime.now()),
      event: event,
      message: message ?? "",
      messageSize: messageSize,
      isSending: isSending,
    );

    // Maintain maximum log size
    if (_logs.length >= maxLogs) {
      _logs.removeAt(0);
    }

    _logs.add(log);
    _notifyListeners();
  }

  String prettifyJson(dynamic jsonString) {
    String prettyJson = const JsonEncoder.withIndent('  ').convert(jsonString);
    return prettyJson;
  }

  /// Attaches the observer to a socket instance
  void attachSocket(io.Socket socket) {
    connectedSocket = socket;
    socket.on('connect', (_) => logEvent('Connected'));
    socket.on('disconnect', (_) => logEvent('Disconnected'));
    socket.on(
      'error',
      (data) => logEvent('Error', message: data.toString()),
    );
    socket.onAny(
      (event, data) {
        try {
          final value = data as Map<dynamic, dynamic>?;
          String? prettyMessage;
          if (value != null && value.isNotEmpty) {
            prettyMessage = prettifyJson(value); // Prettify JSON if applicable
          }
          logEvent(event, message: prettyMessage, isSending: false);
        } catch (e) {
          logEvent('Error in onAny', message: e.toString());
        }
      },
    );
    socket.onAnyOutgoing(
      (event, data) {
        try {
          final value = data as Map<dynamic, dynamic>?;
          String? prettyMessage;
          if (value != null && value.isNotEmpty) {
            prettyMessage = prettifyJson(value); // Prettify JSON if applicable
          }
          logEvent(event, message: prettyMessage, isSending: true);
        } catch (e) {
          logEvent('Error in onAnyOutgoing', message: e.toString());
        }
      },
    );
  }

  /// Provides an unmodifiable view of logs
  UnmodifiableListView<SocketLog> get logs => UnmodifiableListView(_logs);

  /// Clears all logs
  void clearLogs() {
    _logs.clear();
    _notifyListeners();
  }

  /// Starts or stops recording logs
  void toggleRecording(bool isRecording) {
    _isRecording = isRecording;
  }

  /// Exports logs to a JSON string
  String exportLogsAsJson() {
    final logMap = _logs.map((log) {
      return {
        'timestamp': DateTime.parse(log.timestamp).toIso8601String(),
        'event': log.event,
        'message': log.message,
        'size': log.messageSize,
      };
    }).toList();

    return jsonEncode(logMap);
  }

  /// Adds a listener for log updates
  void addListener(void Function(List<SocketLog>) listener) {
    _listeners.add(listener);
  }

  /// Removes a listener
  void removeListener(void Function(List<SocketLog>) listener) {
    _listeners.remove(listener);
  }

  /// Notifies all listeners about log changes
  void _notifyListeners() {
    for (var listener in _listeners) {
      listener(_logs);
    }
  }
}
