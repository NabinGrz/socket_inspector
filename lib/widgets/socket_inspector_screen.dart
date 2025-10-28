import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:socket_inspector/src/inspectable_web_socket.dart';
import 'package:socket_inspector/src/socket_event.dart';
import 'package:socket_inspector/src/socket_filter.dart';
import 'package:socket_inspector/src/socket_inspector_core.dart';

class SocketInspectorScreen extends StatefulWidget {
  final InspectableSocketIO socket;
  const SocketInspectorScreen({super.key, required this.socket});

  @override
  State<SocketInspectorScreen> createState() => _SocketInspectorScreenState();
}

class _SocketInspectorScreenState extends State<SocketInspectorScreen>
    with TickerProviderStateMixin {
  final SocketInspectorCore inspector = SocketInspectorCore();
  // late InspectableSocketIO socket;
  late TabController _tabController;
  bool _useRegex = false;
  final _searchController = TextEditingController();
  final _eventNameController = TextEditingController();
  final Set<SocketEventType> _selectedTypes = {};
  final Set<EventSeverity> _selectedSeverities = {};
  final _uriController = TextEditingController(
    text: 'http://192.168.110.80:3000',
  );
  bool _isConnected = false;
  final _messageController = TextEditingController();
  int _burstCount = 10;

  // void _initializeSocket() {
  //   socket = InspectableSocketIO(
  //     _uriController.text,
  //     options: {
  //       'transports': ['websocket'],
  //       'autoConnect': false,
  //     },
  //   );
  //   socket.connect();
  //   // testAutomation = SocketTestAutomation(socket);
  // }

  InspectableSocketIO get socket => widget.socket;
  @override
  void initState() {
    _tabController = TabController(length: 5, vsync: this);
    // _initializeSocket();
    super.initState();
  }

  Future<void> _exportData(String format) async {
    try {
      String content;
      String fileName;

      if (format == 'json') {
        content = await inspector.exportToJson();
        fileName =
            'socket_inspector_${DateTime.now().millisecondsSinceEpoch}.json';
      } else {
        content = await inspector.exportToCsv();
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
    // testAutomation.dispose();
    inspector.endCurrentSession();
    socket.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Socket.IO Inspector"),
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
          //   onPressed: () => socket.emit('chat message', {'data': dataToEmit}),
          // ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              inspector.clear();
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
          // _buildTestsTab(),
          // _buildControlsTab(),
        ],
      ),
      // body: StreamBuilder<SocketEvent>(
      //   stream: inspector.stream,
      //   builder: (context, _) {
      //     final events = inspector.history.reversed.toList();
      //     return ListView.builder(
      //       itemCount: events.length,
      //       itemBuilder: (context, index) {
      //         final e = events[index];
      //         return Card(
      //           margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      //           child: ListTile(
      //             leading: Icon(
      //               _iconForType(e.type),
      //               color: _colorForType(e.type),
      //             ),
      //             title: Text("event -> ${e.eventName ?? e.type.name}"),
      //             subtitle: Text("data: ${_formatData(e.data)}"),
      //             trailing: Text(
      //               "${e.timestamp.hour}:${e.timestamp.minute}:${e.timestamp.second}",
      //               style: const TextStyle(fontSize: 12),
      //             ),
      //           ),
      //         );
      //       },
      //     );
      //   },
      // ),
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
      stream: inspector.stream,
      builder: (context, _) {
        final events = inspector.filteredHistory.reversed.toList();

        if (events.isEmpty) {
          return const Center(child: Text('No events to display'));
        }

        return ListView.builder(
          itemCount: events.length,
          itemBuilder: (context, index) {
            final event = events[index];
            return _buildEventCard(event);
          },
        );
      },
    );
  }

  Widget _buildEventCard(SocketEvent event) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      // color: _getEventBackgroundColor(event),
      child: ExpansionTile(
        leading: Icon(
          _iconForType(event.type),
          color: _colorForType(event.type),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                event.eventName ?? event.type.name,
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
                const Text(
                  'Data:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SelectableText(
                    event.formattedData.isEmpty
                        ? 'No data'
                        : event.formattedData,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: event.formattedData),
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
              ],
            ),
          ),
        ],
      ),
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
    inspector.updateFilter(filter);
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
            'Active Filters: ${inspector.filter.hasActiveFilters ? "Yes" : "None"}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),

          // Search filters
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

          // Event type filters
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

          // Severity filters
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
    final stats = inspector.stats;

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

  // Widget _buildTestsTab() {
  //   return Padding(
  //     padding: const EdgeInsets.all(16),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.start,
  //       children: [
  //         Text(
  //           'Test Automation',
  //           style: Theme.of(context).textTheme.titleLarge,
  //         ),
  //         const SizedBox(height: 16),

  //         // Predefined test buttons
  //         Text('Quick Tests', style: Theme.of(context).textTheme.titleMedium),
  //         const SizedBox(height: 8),
  //         Wrap(
  //           spacing: 8,
  //           children: [
  //             ElevatedButton(
  //               onPressed: () => _runQuickTest('connection'),
  //               child: const Text('Connection Test'),
  //             ),
  //             ElevatedButton(
  //               onPressed: () => _runQuickTest('message'),
  //               child: const Text('Message Test'),
  //             ),
  //             ElevatedButton(
  //               onPressed: () => _runQuickTest('load'),
  //               child: const Text('Load Test'),
  //             ),
  //             ElevatedButton(
  //               onPressed: () => _runQuickTest('error_recovery'),
  //               child: const Text('Error Recovery'),
  //             ),
  //           ],
  //         ),

  //         const SizedBox(height: 24),
  //         Text('Test Results', style: Theme.of(context).textTheme.titleMedium),
  //         const SizedBox(height: 8),

  //         Expanded(
  //           child: StreamBuilder<TestCase>(
  //             stream: testAutomation.testUpdates,
  //             builder: (context, snapshot) {
  //               final testCases = testAutomation.testCases;

  //               if (testCases.isEmpty) {
  //                 return const Center(
  //                   child: Text(
  //                     'No tests run yet. Click a quick test button to start.',
  //                   ),
  //                 );
  //               }

  //               return ListView.builder(
  //                 itemCount: testCases.length,
  //                 itemBuilder: (context, index) {
  //                   final testCase = testCases[index];
  //                   return _buildTestCaseCard(testCase);
  //                 },
  //               );
  //             },
  //           ),
  //         ),

  //         const SizedBox(height: 16),
  //         Row(
  //           children: [
  //             ElevatedButton.icon(
  //               icon: const Icon(Icons.play_arrow),
  //               label: const Text('Run All Tests'),
  //               onPressed: _runAllTests,
  //             ),
  //             const SizedBox(width: 8),
  //             // ElevatedButton.icon(
  //             //   icon: const Icon(Icons.stop),
  //             //   label: const Text('Cancel Current'),
  //             //   onPressed: testAutomation.cancelCurrentTest,
  //             // ),
  //             // const SizedBox(width: 8),
  //             // ElevatedButton.icon(
  //             //   icon: const Icon(Icons.analytics),
  //             //   label: const Text('Generate Report'),
  //             //   onPressed: _generateTestReport,
  //             // ),
  //           ],
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // Widget _buildTestCaseCard(TestCase testCase) {
  //   Color statusColor;
  //   IconData statusIcon;

  //   switch (testCase.status) {
  //     case TestStatus.pending:
  //       statusColor = Colors.grey;
  //       statusIcon = Icons.schedule;
  //       break;
  //     case TestStatus.running:
  //       statusColor = Colors.blue;
  //       statusIcon = Icons.play_arrow;
  //       break;
  //     case TestStatus.passed:
  //       statusColor = Colors.green;
  //       statusIcon = Icons.check_circle;
  //       break;
  //     case TestStatus.failed:
  //       statusColor = Colors.red;
  //       statusIcon = Icons.error;
  //       break;
  //     case TestStatus.cancelled:
  //       statusColor = Colors.orange;
  //       statusIcon = Icons.cancel;
  //       break;
  //   }

  //   return Card(
  //     margin: const EdgeInsets.symmetric(vertical: 4),
  //     child: ExpansionTile(
  //       leading: Icon(statusIcon, color: statusColor),
  //       title: Text(testCase.name),
  //       subtitle: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Text(testCase.description),
  //           Text(
  //             'Status: ${testCase.status.name} ${testCase.executionTime != null ? "(${testCase.executionTime!.inMilliseconds}ms)" : ""}',
  //             style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
  //           ),
  //         ],
  //       ),
  //       children: [
  //         Padding(
  //           padding: const EdgeInsets.all(16),
  //           child: Column(
  //             crossAxisAlignment: CrossAxisAlignment.start,
  //             children: [
  //               if (testCase.errorMessage != null) ...[
  //                 Text(
  //                   'Error:',
  //                   style: TextStyle(
  //                     color: Colors.red,
  //                     fontWeight: FontWeight.bold,
  //                   ),
  //                 ),
  //                 Text(
  //                   testCase.errorMessage!,
  //                   style: TextStyle(color: Colors.red),
  //                 ),
  //                 const SizedBox(height: 8),
  //               ],
  //               Text(
  //                 'Steps:',
  //                 style: const TextStyle(fontWeight: FontWeight.bold),
  //               ),
  //               ...testCase.steps.map(
  //                 (step) => Padding(
  //                   padding: const EdgeInsets.only(left: 16, top: 4),
  //                   child: Row(
  //                     children: [
  //                       Icon(
  //                         step.completed ? Icons.check : Icons.schedule,
  //                         size: 16,
  //                         color: step.completed ? Colors.green : Colors.grey,
  //                       ),
  //                       const SizedBox(width: 8),
  //                       Expanded(
  //                         child: Text(
  //                           '${step.action}: ${step.result ?? "Pending"}',
  //                         ),
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //               ),
  //               const SizedBox(height: 8),
  //               Text('Events Recorded: ${testCase.recordedEvents.length}'),
  //               if (testCase.recordedEvents.isNotEmpty)
  //                 ElevatedButton(
  //                   onPressed: () => _showTestEventDetails(testCase),
  //                   child: const Text('View Events'),
  //                 ),
  //             ],
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  // void _runQuickTest(String testType) async {
  //   TestCase testCase;

  //   switch (testType) {
  //     case 'connection':
  //       testCase = testAutomation.createConnectionTest();
  //       break;
  //     case 'message':
  //       testCase = testAutomation.createMessageTest();
  //       break;
  //     case 'load':
  //       testCase = testAutomation.createLoadTest();
  //       break;
  //     case 'error_recovery':
  //       testCase = testAutomation.createErrorRecoveryTest();
  //       break;
  //     default:
  //       return;
  //   }

  //   setState(() {});

  //   try {
  //     await testAutomation.runTestCase(testCase);
  //     setState(() {});

  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text(
  //             'Test "${testCase.name}" completed: ${testCase.status.name}',
  //           ),
  //           backgroundColor:
  //               testCase.status == TestStatus.passed
  //                   ? Colors.green
  //                   : Colors.red,
  //         ),
  //       );
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Test failed: $e'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   }
  // }

  // void _runAllTests() async {
  //   try {
  //     final results = await testAutomation.runAllTests();
  //     setState(() {});

  //     final passed = results.where((t) => t.status == TestStatus.passed).length;
  //     final total = results.length;

  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('All tests completed: $passed/$total passed'),
  //           backgroundColor: passed == total ? Colors.green : Colors.orange,
  //         ),
  //       );
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Test suite failed: $e'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   }
  // }

  // void _generateTestReport() async {
  //   try {
  //     final report = testAutomation.getPerformanceReport(
  //       testAutomation.testCases,
  //     );
  //     final reportJson = report.toString();

  //     final directory = await getTemporaryDirectory();
  //     final file = File(
  //       '${directory.path}/test_report_${DateTime.now().millisecondsSinceEpoch}.txt',
  //     );
  //     await file.writeAsString(reportJson);

  //     await OpenFilex.open(file.path);

  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('Test report generated: ${file.path}')),
  //       );
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Report generation failed: $e'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   }
  // }

  // void _showTestEventDetails(TestCase testCase) {
  //   showDialog(
  //     context: context,
  //     builder:
  //         (context) => AlertDialog(
  //           title: Text('Events for ${testCase.name}'),
  //           content: SizedBox(
  //             width: double.maxFinite,
  //             height: 400,
  //             child: ListView.builder(
  //               itemCount: testCase.recordedEvents.length,
  //               itemBuilder: (context, index) {
  //                 final event = testCase.recordedEvents[index];
  //                 return ListTile(
  //                   leading: Icon(_iconForType(event.type)),
  //                   title: Text(event.eventName ?? event.type.name),
  //                   subtitle: Text(event.formattedTimestamp),
  //                   trailing:
  //                       event.metrics.latencyMs != null
  //                           ? Text('${event.metrics.latencyMs}ms')
  //                           : null,
  //                 );
  //               },
  //             ),
  //           ),
  //           actions: [
  //             TextButton(
  //               onPressed: () => Navigator.pop(context),
  //               child: const Text('Close'),
  //             ),
  //           ],
  //         ),
  //   );
  // }

  Widget _buildControlsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Connection controls
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

          Row(
            children: [
              ElevatedButton.icon(
                icon: Icon(_isConnected ? Icons.link_off : Icons.link),
                label: Text(_isConnected ? 'Disconnect' : 'Connect'),
                onPressed: () {
                  if (_isConnected) {
                    socket.disconnect();
                    setState(() => _isConnected = false);
                  } else {
                    // _initializeSocket();
                    socket.connectToSocket();
                    setState(() => _isConnected = true);
                  }
                },
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.bug_report),
                label: const Text('Simulate Error'),
                onPressed: socket.simulateError,
              ),
            ],
          ),

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
                onPressed: () {
                  if (_messageController.text.isNotEmpty) {
                    socket.sendTestMessage(_messageController.text);
                  }
                },
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
              ElevatedButton(
                onPressed: () => socket.sendBurstMessages(_burstCount),
                child: const Text('Send Burst'),
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
                  onPressed: inspector.endCurrentSession,
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

  // void _showExportDialog() {
  //   showDialog(
  //     context: context,
  //     builder:
  //         (context) => AlertDialog(
  //           title: const Text('Export Data'),
  //           content: const Text('Choose export format:'),
  //           actions: [
  //             TextButton(
  //               onPressed: () {
  //                 Navigator.pop(context);
  //                 _exportData('json');
  //               },
  //               child: const Text('JSON'),
  //             ),
  //             TextButton(
  //               onPressed: () {
  //                 Navigator.pop(context);
  //                 _exportData('csv');
  //               },
  //               child: const Text('CSV'),
  //             ),
  //             TextButton(
  //               onPressed: () => Navigator.pop(context),
  //               child: const Text('Cancel'),
  //             ),
  //           ],
  //         ),
  //   );
  // }

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
                    inspector.startSession(
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
    if (inspector.currentSession != null) {
      try {
        final file = await inspector.saveSession(inspector.currentSession!);
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
    await inspector.replayEvents([event]);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Event replayed')));
    }
  }

  // Helper methods for UI styling
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
        return Colors.grey;
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

  Color _getEventBackgroundColor(SocketEvent event) {
    switch (event.severity) {
      case EventSeverity.info:
        return Colors.white;
      case EventSeverity.warning:
        return Colors.amber.shade50;
      case EventSeverity.error:
        return Colors.red.shade50;
      case EventSeverity.critical:
        return Colors.red.shade100;
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
