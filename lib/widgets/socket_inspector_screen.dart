import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:socket_inspector/src/socket_event.dart';
import 'package:socket_inspector/src/socket_filter.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../src/socket_inspector_core.dart';

class SocketInspectorScreen extends StatefulWidget {
  final IO.Socket socket;
  const SocketInspectorScreen({super.key, required this.socket});

  @override
  State<SocketInspectorScreen> createState() => _SocketInspectorScreenState();
}

class _SocketInspectorScreenState extends State<SocketInspectorScreen>
    with TickerProviderStateMixin {
  final SocketInspectorCore inspectorCore = SocketInspectorCore();

  late TabController _tabController;
  bool _useRegex = false;
  final _searchController = TextEditingController();
  final _eventNameController = TextEditingController();
  final Set<SocketEventType> _selectedTypes = {};
  final Set<EventSeverity> _selectedSeverities = {};
  final _uriController = TextEditingController();
  final bool _isConnected = false;
  final _messageController = TextEditingController();
  int _burstCount = 10;

  IO.Socket get socket => widget.socket;
  @override
  void initState() {
    _tabController = TabController(length: 5, vsync: this);

    _uriController.text = socket.io.uri;
    super.initState();
  }

  Future<void> _exportData(String format) async {
    try {
      String content;
      String fileName;

      if (format == 'json') {
        content = await inspectorCore.exportToJson();
        fileName =
            'socket_inspector_${DateTime.now().millisecondsSinceEpoch}.json';
      } else {
        content = await inspectorCore.exportToCsv();
        fileName =
            'socket_inspector_${DateTime.now().millisecondsSinceEpoch}.csv';
      }

      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/$fileName');
      await file.writeAsString(content);

      await OpenFilex.open(file.path);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Exported to ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _eventNameController.dispose();
    _uriController.dispose();
    _messageController.dispose();

    inspectorCore.endCurrentSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Socket.IO Inspector"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Events'),
            Tab(icon: Icon(Icons.filter_alt), text: 'Filters'),
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
            Tab(icon: Icon(Icons.science), text: 'Tests'),
            Tab(icon: Icon(Icons.settings), text: 'Controls'),
          ],
        ),
        actions: [
          // IconButton(
          //   icon: const Icon(Icons.add),
          //   onPressed: () async {
          //     inspectableSocketIO.emitWithAckAsync('privateMessage', {
          //       'to': 'AsxaAHGzqJmPl2r3AAAL',
          //       'message': Uuid().v4().substring(0, 8),
          //     });
          //   },
          // ),
          // IconButton(
          //   icon: const Icon(Icons.add),
          //   onPressed: () async {
          //     inspectableSocketIO.emitWithAckAsync('privateMessage', {
          //       'to': 'mfLeBcxfY5mLQa2eAAAP',
          //       'message': Uuid().v4().substring(0, 8),
          //     });
          //   },
          // ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              inspectorCore.clear();
              setState(() {});
            },
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.link_off),
        onPressed: () => socket.disconnect(),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEventsTab(),
          _buildFiltersTab(),
          _buildAnalyticsTab(),
          _buildAnalyticsTab(),
          _buildControlsTab(),
        ],
      ),
    );
  }

  String _formatData(dynamic data) {
    if (data == null) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  Widget _buildEventsTab() {
    return StreamBuilder<SocketEvent>(
      stream: inspectorCore.stream,
      builder: (context, _) {
        final events = inspectorCore.filteredHistory.reversed.toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 8),
            Text(
              'Server: ${socket.io.uri}',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
            Text(
              'Transports: ${socket.io.options?['transports']?.join(', ')}',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
            Text(
              'Status: ${socket.connected ? "Connected 🟢" : "Disconnected 🔴"}',
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
            SizedBox(height: 8),
            events.isEmpty
                ? Center(child: Text('No events to display'))
                : Expanded(
                  child: ListView.separated(
                    itemCount: events.length,
                    separatorBuilder:
                        (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return _buildEventCard(event);
                    },
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _buildEventCard(SocketEvent event) {
    return ExpansionTile(
      leading: Icon(_iconForType(event.type), color: _colorForType(event.type)),
      title: Row(
        children: [
          Expanded(
            child: Text(
              "event: ${event.eventName ?? event.type.name}.  ${event.from}",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (event.metrics.latencyMs != null)
            Chip(
              label: Text('${event.metrics.latencyMs}ms'),
              backgroundColor: _getLatencyColor(event.metrics.latencyMs!),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          Text(event.formattedTimestamp),
          const SizedBox(width: 8),
          Text('${event.dataSizeBytes} bytes'),
          const SizedBox(width: 8),
          Text(event.severity.name.toUpperCase()),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Event ID:', event.id),
              _buildInfoRow('Session ID:', event.sessionId ?? 'N/A'),
              if (event.metrics.errorCode != null)
                _buildInfoRow('Error Code:', event.metrics.errorCode!),
              if (event.metrics.errorMessage != null)
                _buildInfoRow('Error Message:', event.metrics.errorMessage!),
              if (event.metrics.retryCount != null)
                _buildInfoRow(
                  'Retry Count:',
                  event.metrics.retryCount.toString(),
                ),
              const SizedBox(height: 8),
              Text(
                event.type == SocketEventType.messageSent
                    ? 'Payload:'
                    : 'Response:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  event.formattedPayload.isEmpty
                      ? 'No data'
                      : event.formattedPayload,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy Payload'),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: event.formattedPayload),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.replay),
                    label: const Text('Replay'),
                    onPressed: () => _replayEvent(event),
                  ),
                ],
              ),
              if (event.type == SocketEventType.messageSent) ...{
                const SizedBox(height: 8),
                const Text(
                  'Response:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    event.formattedResponse.isEmpty
                        ? 'No data'
                        : event.formattedResponse,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 8),
              },
              ElevatedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy Response'),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: event.formattedResponse),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _applyFilters() {
    final filter = SocketEventFilter(
      allowedTypes: _selectedTypes,
      allowedSeverities: _selectedSeverities,
      searchText:
          _searchController.text.isEmpty ? null : _searchController.text,
      eventNameFilter:
          _eventNameController.text.isEmpty ? null : _eventNameController.text,
      useRegex: _useRegex,
    );
    inspectorCore.updateFilter(filter);
    setState(() {});
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  Widget _buildFiltersTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Active Filters: ${inspectorCore.filter.hasActiveFilters ? "Yes" : "None"}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: 'Search in data',
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _useRegex,
                    onChanged:
                        (value) => setState(() => _useRegex = value ?? false),
                  ),
                  const Text('Regex'),
                ],
              ),
            ),
            onChanged: (_) => _applyFilters(),
          ),
          const SizedBox(height: 8),

          TextField(
            controller: _eventNameController,
            decoration: const InputDecoration(
              labelText: 'Filter by event name',
            ),
            onChanged: (_) => _applyFilters(),
          ),
          const SizedBox(height: 16),

          Text('Event Types:', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            children:
                SocketEventType.values.map((type) {
                  return FilterChip(
                    label: Text(type.name),
                    selected: _selectedTypes.contains(type),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedTypes.add(type);
                        } else {
                          _selectedTypes.remove(type);
                        }
                      });
                      _applyFilters();
                    },
                  );
                }).toList(),
          ),
          const SizedBox(height: 16),

          Text('Severities:', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            children:
                EventSeverity.values.map((severity) {
                  return FilterChip(
                    label: Text(
                      severity.name,
                      style: TextStyle(color: Colors.black),
                    ),
                    selected: _selectedSeverities.contains(severity),
                    backgroundColor: _getSeverityColor(severity),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedSeverities.add(severity);
                        } else {
                          _selectedSeverities.remove(severity);
                        }
                      });
                      _applyFilters();
                    },
                  );
                }).toList(),
          ),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedTypes.clear();
                _selectedSeverities.clear();
                _searchController.clear();
                _eventNameController.clear();
                _useRegex = false;
              });
              _applyFilters();
            },
            child: const Text('Clear All Filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    final stats = inspectorCore.stats;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Session Analytics',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Analytics'),
                onPressed: () => setState(() {}),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildStatsCard('Total Events', stats.totalEvents.toString()),
          _buildStatsCard('Messages Sent', stats.messagesSent.toString()),
          _buildStatsCard(
            'Messages Received',
            stats.messagesReceived.toString(),
          ),
          _buildStatsCard('Errors', stats.errorEvents.toString()),
          _buildStatsCard(
            'Average Latency',
            '${stats.averageLatency.toStringAsFixed(1)}ms',
          ),
          _buildStatsCard(
            'Data Transferred',
            '${(stats.totalDataTransferred / 1024).toStringAsFixed(1)} KB',
          ),

          const SizedBox(height: 16),
          Text(
            'Event Type Distribution',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ...stats.eventTypeCounts.entries.map((entry) {
            return ListTile(
              leading: Icon(_iconForType(entry.key)),
              title: Text(entry.key.name),
              trailing: Text(entry.value.toString()),
            );
          }),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStatsCard(String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildControlsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connection', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          TextField(
            controller: _uriController,
            decoration: const InputDecoration(
              labelText: 'Server URI',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          const SizedBox(height: 8),

          const SizedBox(height: 24),
          Text('Test Messages', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),

          TextField(
            controller: _messageController,
            decoration: const InputDecoration(
              labelText: 'Test Message',
              prefixIcon: Icon(Icons.message),
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Send Message'),
                onPressed: () {},
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.send_and_archive),
                label: const Text('Hello World'),
                onPressed:
                    () => socket.emit('message', {'msg': 'Hello from Flutter'}),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Text('Burst Testing', style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              Text('Count: $_burstCount'),
              Expanded(
                child: Slider(
                  value: _burstCount.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  onChanged:
                      (value) => setState(() => _burstCount = value.round()),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Text(
            'Session Management',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('New Session'),
                  onPressed: () => _showNewSessionDialog(),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.stop),
                  label: const Text('End Session'),
                  onPressed: inspectorCore.endCurrentSession,
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save Session'),
                  onPressed: _saveCurrentSession,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showNewSessionDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('New Session'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Session Name'),
                ),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    inspectorCore.startSession(
                      nameController.text,
                      description: descController.text,
                    );
                    Navigator.pop(context);
                    setState(() {});
                  }
                },
                child: const Text('Start'),
              ),
            ],
          ),
    );
  }

  void _saveCurrentSession() async {
    if (inspectorCore.currentSession != null) {
      try {
        final file = await inspectorCore.saveSession(
          inspectorCore.currentSession!,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Session saved to ${file.path}')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Save failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _replayEvent(SocketEvent event) async {
    await inspectorCore.replayEvents([event]);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Event replayed')));
    }
  }

  IconData _iconForType(SocketEventType type) {
    switch (type) {
      case SocketEventType.connect:
        return Icons.link;
      case SocketEventType.disconnect:
        return Icons.link_off;
      case SocketEventType.messageSent:
        return Icons.arrow_upward;
      case SocketEventType.messageReceived:
        return Icons.arrow_downward;
      case SocketEventType.error:
        return Icons.error;
      case SocketEventType.reconnect:
        return Icons.refresh;
      case SocketEventType.connectionAttempt:
        return Icons.wifi_find;
      case SocketEventType.timeout:
        return Icons.timer_off;
      case SocketEventType.ping:
        return Icons.network_ping;
      case SocketEventType.pong:
        return Icons.network_check;
    }
  }

  Color _colorForType(SocketEventType type) {
    switch (type) {
      case SocketEventType.connect:
        return Colors.green;
      case SocketEventType.disconnect:
        return Colors.red;
      case SocketEventType.messageSent:
        return Colors.blue;
      case SocketEventType.messageReceived:
        return Colors.orange;
      case SocketEventType.error:
        return Colors.red;
      case SocketEventType.reconnect:
        return Colors.purple;
      case SocketEventType.connectionAttempt:
        return Colors.cyan;
      case SocketEventType.timeout:
        return Colors.amber;
      case SocketEventType.ping:
        return Colors.lightGreen;
      case SocketEventType.pong:
        return Colors.teal;
    }
  }

  Color _getSeverityColor(EventSeverity severity) {
    switch (severity) {
      case EventSeverity.info:
        return Colors.blue.shade100;
      case EventSeverity.warning:
        return Colors.orange.shade100;
      case EventSeverity.error:
        return Colors.red.shade100;
      case EventSeverity.critical:
        return Colors.red.shade200;
    }
  }

  Color _getLatencyColor(int latencyMs) {
    if (latencyMs < 100) return Colors.green.shade100;
    if (latencyMs < 500) return Colors.orange.shade100;
    return Colors.red.shade100;
  }
}
