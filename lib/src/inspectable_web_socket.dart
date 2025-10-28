import 'package:socket_inspector/src/socket_event.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import 'socket_inspector_core.dart';

class InspectableSocketIO {
  // final String uri;
  // final Map<String, dynamic> options;
  final IO.Socket? socket;
  final SocketInspectorCore inspector = SocketInspectorCore();
  final String sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  DateTime? _lastPingTime;
  final Map<String, DateTime> _pendingRequests = {};

  InspectableSocketIO(this.socket);

  IO.Socket? get _socket => socket;
  void startListening() {
    // try {
    //   _socket = IO.io(
    //     uri,
    //     IO.OptionBuilder()
    //         .setTransports(['websocket'])
    //         .disableAutoConnect()
    //         .build(),
    //   );

    //   _socket?.connect();

    //   // Track connection attempt
    //   inspector.log(
    //     SocketEvent(
    //       type: SocketEventType.connectionAttempt,
    //       data: {'uri': uri, 'options': options},
    //       sessionId: sessionId,
    //     ),
    //   );
    // } on Exception catch (e) {
    //   inspector.log(
    //     SocketEvent(
    //       type: SocketEventType.error,
    //       data: {'error': e.toString(), 'context': 'connection_setup'},
    //       severity: EventSeverity.error,
    //       metrics: SocketEventMetrics(
    //         errorCode: 'CONNECTION_SETUP_ERROR',
    //         errorMessage: e.toString(),
    //       ),
    //       sessionId: sessionId,
    //     ),
    //   );
    // }

    // Connection events
    _socket?.onConnect((data) {
      inspector.log(
        SocketEvent(
          type: SocketEventType.connect,
          data: data,
          severity: EventSeverity.info,
          sessionId: sessionId,
        ),
      );
      print("Socket Connection Status: ${_socket?.connected}");
    });

    _socket?.onDisconnect((data) {
      inspector.log(
        SocketEvent(
          type: SocketEventType.disconnect,
          data: data,
          severity: EventSeverity.warning,
          sessionId: sessionId,
        ),
      );
    });

    _socket?.onReconnect((data) {
      inspector.log(
        SocketEvent(
          type: SocketEventType.reconnect,
          data: data,
          severity: EventSeverity.info,
          metrics: SocketEventMetrics(
            retryCount: data is Map ? data['attempt'] : null,
          ),
          sessionId: sessionId,
        ),
      );
      print("Reconnected: $data");
    });

    _socket?.onError((err) {
      inspector.log(
        SocketEvent(
          type: SocketEventType.error,
          data: err,
          severity: EventSeverity.error,
          metrics: SocketEventMetrics(
            errorCode: 'SOCKET_ERROR',
            errorMessage: err.toString(),
          ),
          sessionId: sessionId,
        ),
      );
      print("Error: $err");
    });

    // Add ping/pong monitoring
    _socket?.on('ping', (data) {
      _lastPingTime = DateTime.now();
      inspector.log(
        SocketEvent(
          type: SocketEventType.ping,
          data: data,
          sessionId: sessionId,
        ),
      );
    });

    _socket?.on('pong', (data) {
      final pongTime = DateTime.now();
      int? latency;
      if (_lastPingTime != null) {
        latency = pongTime.difference(_lastPingTime!).inMilliseconds;
      }

      inspector.log(
        SocketEvent(
          type: SocketEventType.pong,
          data: data,
          metrics: SocketEventMetrics(latencyMs: latency),
          sessionId: sessionId,
        ),
      );
    });

    // Catch all incoming messages
    _socket?.onAny((event, data) {
      print(" ################ Received event: $event with data: $data");

      // Check if this is a response to a tracked request
      String? requestId =
          _pendingRequests.keys.where((id) => event.contains(id)).firstOrNull;

      int? latency;
      if (requestId != null) {
        final requestTime = _pendingRequests.remove(requestId);
        if (requestTime != null) {
          latency = DateTime.now().difference(requestTime).inMilliseconds;
        }
      }

      inspector.log(
        SocketEvent(
          type: SocketEventType.messageReceived,
          eventName: event,
          data: data,
          severity: EventSeverity.info,
          metrics: SocketEventMetrics(
            latencyMs: latency,
            dataSizeBytes: _calculateDataSize(data),
          ),
          sessionId: sessionId,
        ),
      );
    });
  }

  void emit(String event, dynamic data) {
    final eventId = '${DateTime.now().millisecondsSinceEpoch}_$event';
    _pendingRequests[eventId] = DateTime.now();

    _socket?.emit(event, data);
    inspector.log(
      SocketEvent(
        type: SocketEventType.messageSent,
        eventName: event,
        data: data,
        severity: EventSeverity.info,
        metrics: SocketEventMetrics(dataSizeBytes: _calculateDataSize(data)),
        sessionId: sessionId,
      ),
    );
  }

  void on(String event, Function(dynamic) handler) {
    _socket?.on(event, (data) {
      inspector.log(
        SocketEvent(
          type: SocketEventType.messageReceived,
          eventName: event,
          data: data,
          severity: EventSeverity.info,
          metrics: SocketEventMetrics(dataSizeBytes: _calculateDataSize(data)),
          sessionId: sessionId,
        ),
      );
      handler(data);
    });
  }

  void disconnect() {
    _socket?.disconnect();
    inspector.log(
      SocketEvent(
        type: SocketEventType.disconnect,
        data: {'manual': true},
        severity: EventSeverity.info,
        sessionId: sessionId,
      ),
    );
  }

  int _calculateDataSize(dynamic data) {
    if (data == null) return 0;
    try {
      return data.toString().length;
    } catch (_) {
      return 0;
    }
  }

  // Test utility methods for QA
  void sendTestMessage(String message) {
    emit('test_message', {
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
      'test_id': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void sendBurstMessages(
    int count, {
    Duration delay = const Duration(milliseconds: 100),
  }) async {
    for (int i = 0; i < count; i++) {
      sendTestMessage('Burst message $i of $count');
      if (i < count - 1) {
        await Future.delayed(delay);
      }
    }
  }

  void simulateError() {
    inspector.log(
      SocketEvent(
        type: SocketEventType.error,
        data: {'simulated': true, 'error': 'Test error for QA purposes'},
        severity: EventSeverity.error,
        metrics: SocketEventMetrics(
          errorCode: 'SIMULATED_ERROR',
          errorMessage: 'This is a simulated error for testing purposes',
        ),
        sessionId: sessionId,
      ),
    );
  }
}
