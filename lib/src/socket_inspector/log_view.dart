import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_inspector/src/socket_inspector/logger_provider.dart';

import 'socket_observer.dart';
import 'widgets/custom_tab.dart';
import 'widgets/socket_event_list_tile.dart';

class LogView extends ConsumerStatefulWidget {
  const LogView({super.key});

  @override
  ConsumerState<LogView> createState() => _LogViewState();
}

class _LogViewState extends ConsumerState<LogView>
    with SingleTickerProviderStateMixin {
  late TabController tabController;
  final searchController = TextEditingController();

  @override
  void initState() {
    tabController = TabController(length: 3, vsync: this);
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (timeStamp) {
        controller.updateLogs(SocketObserver.instance.logs);
        SocketObserver.instance.addListener(_updateLogs);
      },
    );
  }

  @override
  void dispose() {
    SocketObserver.instance.removeListener(_updateLogs);
    tabController.dispose();
    super.dispose();
  }

  void _updateLogs(List<SocketLog> updatedLogs) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        controller.updateLogs(updatedLogs);
      },
    );
  }

  List<SocketLog> get allLogs => watchSearch.logs.reversed.toList();

  SocketInspectNotifier get controller =>
      ref.read(socketInspectorProvider.notifier);
  SocketInspectNotifier get watchSearch => ref.watch(socketInspectorProvider);

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        controller.clearAll();
        searchController.clear();
      },
      child: Scaffold(
        appBar: AppBar(
          title: watchSearch.isSearching
              ? TextFormField(
                  // onTapOutside: (event) {
                  //   FocusScope.of(context).unfocus();
                  // },
                  autofocus: true,
                  controller: searchController,
                  onChanged: controller.onChangeSearch,
                  decoration: InputDecoration(
                      hintText: "Enter event,message...",
                      border: OutlineInputBorder(),
                      suffixIcon: watchSearch.searchText.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                controller.updateSearchText("");
                                controller.updateIsSearching();
                                controller.updateLogs(controller.originalLogs);
                                searchController.clear();
                              },
                              icon: Icon(
                                Icons.clear,
                                color: Colors.black,
                              ))),
                )
              : Text('Socket Inspector'),
          actions: [
            IconButton(
              onPressed: () {
                // setState(() {
                //   isSearching = !isSearching;
                // });
                controller.updateIsSearching();
              },
              icon: Platform.isIOS
                  ? Icon(CupertinoIcons.search)
                  : Icon(Icons.search),
            )
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.check_circle_outlined,
                  color: Colors.green,
                ),
                SizedBox(
                  width: 6,
                ),
                Text(
                  "Connected to ${SocketObserver.instance.connectedSocket.io.uri}",
                  style: TextStyle(
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            SizedBox(
              height: 16,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                tabItem(
                  title: "All",
                  icon: Icon(Icons.list, color: Colors.black),
                  tabIndex: 0,
                ),
                SizedBox(
                  width: 8,
                ),
                tabItem(
                  title: "Send",
                  icon: Icon(Icons.arrow_upward, color: Colors.green),
                  tabIndex: 1,
                ),
                SizedBox(
                  width: 8,
                ),
                tabItem(
                  title: "Received",
                  icon: Icon(Icons.arrow_downward, color: Colors.red),
                  tabIndex: 2,
                ),
                SizedBox(
                  width: 8,
                ),
              ],
            ),
            SizedBox(
              height: 14,
            ),
            allLogs.isEmpty
                ? const Center(child: Text('No logs yet.'))
                : Expanded(
                    child: ListView.builder(
                      itemCount: allLogs.length,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        final log = allLogs[index];
                        return SocketEventListTile(log: log);
                      },
                    ),
                  ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => SocketObserver.instance.clearLogs(),
          tooltip: 'Clear Logs',
          child: const Icon(Icons.delete),
        ),
      ),
    );
  }
}
