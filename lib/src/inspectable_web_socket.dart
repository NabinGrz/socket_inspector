import 'dart:async';

import 'package:socket_inspector/socket_inspector.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class InspectableSocketIO {
  IO.Socket? socket;
  final SocketInspectorCore inspector = SocketInspectorCore();
  final String sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  DateTime? _lastPingTime;
  final Map<String, DateTime> _pendingRequests = {};

  InspectableSocketIO(this.socket) {
    // startListening();
  }

  void startListening() {
    print("Starting to listen to socket events");
    try {
      socket?.onConnect((data) {
        inspector.log(
          SocketEvent(
            type: SocketEventType.connect,
            payload: data,
            severity: EventSeverity.info,
            sessionId: sessionId,
            from: "onConnect",
          ),
          "onConnect",
        );
        print("Socket Connection Status: ${socket?.connected}");
      });

      socket?.onDisconnect((data) {
        inspector.log(
          SocketEvent(
            type: SocketEventType.disconnect,
            payload: data,
            severity: EventSeverity.warning,
            sessionId: sessionId,
            from: "onDisconnect",
          ),
          "onDisconnect",
        );
      });

      socket?.onReconnect((data) {
        inspector.log(
          SocketEvent(
            type: SocketEventType.reconnect,
            payload: data,
            severity: EventSeverity.info,
            metrics: SocketEventMetrics(
              retryCount: data is Map ? data['attempt'] : null,
            ),
            sessionId: sessionId,
            from: "onReconnect",
          ),
          "onReconnect",
        );
        print("Reconnected: $data");
      });

      socket?.onError((err) {
        inspector.log(
          SocketEvent(
            type: SocketEventType.error,
            payload: err,
            severity: EventSeverity.error,
            metrics: SocketEventMetrics(
              errorCode: 'SOCKET_ERROR',
              errorMessage: err.toString(),
            ),
            sessionId: sessionId,
            from: "onError",
          ),
          "onError",
        );
        print("Error: $err");
      });

      // Add ping/pong monitoring
      socket?.on('ping', (data) {
        _lastPingTime = DateTime.now();
        inspector.log(
          SocketEvent(
            type: SocketEventType.ping,
            payload: data,
            sessionId: sessionId,
            from: "onPing",
          ),
          "onPing",
        );
      });

      socket?.on('pong', (data) {
        final pongTime = DateTime.now();
        int? latency;
        if (_lastPingTime != null) {
          latency = pongTime.difference(_lastPingTime!).inMilliseconds;
        }

        inspector.log(
          SocketEvent(
            type: SocketEventType.pong,
            payload: data,
            metrics: SocketEventMetrics(latencyMs: latency),
            sessionId: sessionId,
            from: "onPong",
          ),
          "onPong",
        );
      });

      // socket?.onAny((event, [data]) {
      //   print(
      //     " ################ ON ANY Received event: $event with data: $data",
      //   );
      //   inspector.log(
      //     SocketEvent(
      //       type: SocketEventType.messageReceived,
      //       eventName: event,
      //       payload: data,
      //       severity: EventSeverity.info,
      //       metrics: SocketEventMetrics(
      //         dataSizeBytes: _calculateDataSize(data),
      //       ),
      //       sessionId: sessionId,
      //       from: "onAny",
      //     ),
      //     "onAny",
      //   );
      // });
      // socket?.on("privateMessage", (data) {
      //   print(" ################ ON Received privateMessage: $data");
      //   // inspector.log(
      //   //   SocketEvent(
      //   //     type: SocketEventType.messageReceived,
      //   //     eventName: "statusUpdate",
      //   //     payload: data,
      //   //     severity: EventSeverity.info,
      //   //     metrics: SocketEventMetrics(
      //   //       dataSizeBytes: _calculateDataSize(data),
      //   //     ),
      //   //     sessionId: sessionId,
      //   //     from: "onStatusUpdate",
      //   //   ),
      //   //   "onStatusUpdate",
      //   // );
      // });
      // socket?.on("statusUpdate", (data) {
      //   print(" ################ ON Received statusUpdate: $data");
      //   // inspector.log(
      //   //   SocketEvent(
      //   //     type: SocketEventType.messageReceived,
      //   //     eventName: "statusUpdate",
      //   //     payload: data,
      //   //     severity: EventSeverity.info,
      //   //     metrics: SocketEventMetrics(
      //   //       dataSizeBytes: _calculateDataSize(data),
      //   //     ),
      //   //     sessionId: sessionId,
      //   //     from: "onStatusUpdate",
      //   //   ),
      //   //   "onStatusUpdate",
      //   // );
      // });

      socket?.onAny((event, [data]) {
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
            payload: data,
            severity: EventSeverity.info,
            metrics: SocketEventMetrics(
              latencyMs: latency,
              dataSizeBytes: _calculateDataSize(data),
            ),
            sessionId: sessionId,
            from: "onAny",
          ),
          "onAny",
        );
      });
    } on Exception catch (e) {
      print(e);
    }
  }

  void emit(String event, dynamic data) {
    final eventId = '${DateTime.now().millisecondsSinceEpoch}_$event';
    _pendingRequests[eventId] = DateTime.now();

    socket?.emit(event, data);
    inspector.log(
      SocketEvent(
        type: SocketEventType.messageSent,
        eventName: event,
        payload: data,
        severity: EventSeverity.info,
        metrics: SocketEventMetrics(dataSizeBytes: _calculateDataSize(data)),
        sessionId: sessionId,
        from: "emit",
      ),
      "emit",
    );
  }

  Future<dynamic> emitWithAckAsync(String event, dynamic payload) async {
    final completer = Completer<dynamic>();
    final eventId = '${DateTime.now().millisecondsSinceEpoch}_$event';
    _pendingRequests[eventId] = DateTime.now();

    socket?.emitWithAck(
      event,
      payload,
      ack: (response) {
        inspector.log(
          SocketEvent(
            type: SocketEventType.messageSent,
            eventName: event,
            payload: payload,
            response: response,
            severity: EventSeverity.info,
            metrics: SocketEventMetrics(
              dataSizeBytes: _calculateDataSize(response),
            ),
            sessionId: sessionId,
            from: "emitWithAckAsync",
          ),
          "emitWithAckAsync",
        );

        if (!completer.isCompleted) {
          completer.complete(response);
        }
      },
    );

    // return completer.future;
    // Return a default response if server never responds
    return completer.future.timeout(
      Duration(seconds: 5),
      onTimeout: () {
        return {'status': 'no_response', 'event': event};
      },
    );
  }

  // void on(String event, Function(dynamic) handler) {
  //   socket?.on(event, (data) {
  //     inspector.log(
  //       SocketEvent(
  //         type: SocketEventType.messageReceived,
  //         eventName: event,
  //         payload: data,
  //         severity: EventSeverity.info,
  //         metrics: SocketEventMetrics(dataSizeBytes: _calculateDataSize(data)),
  //         sessionId: sessionId,
  //         from: "on",
  //       ),
  //       "on",
  //     );
  //     handler(data);
  //   });
  // }

  void disconnect() {
    socket?.disconnect();
    inspector.log(
      SocketEvent(
        type: SocketEventType.disconnect,
        payload: {'manual': true},
        severity: EventSeverity.info,
        sessionId: sessionId,
        from: "disconnect",
      ),
      "disconnect",
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
        payload: {'simulated': true, 'error': 'Test error for QA purposes'},
        severity: EventSeverity.error,
        metrics: SocketEventMetrics(
          errorCode: 'SIMULATED_ERROR',
          errorMessage: 'This is a simulated error for testing purposes',
        ),
        sessionId: sessionId,
        from: "simulateError",
      ),
      "simulateError",
    );
  }
}
