import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'socket_observer.dart';

final socketInspectorProvider =
    ChangeNotifierProvider.autoDispose((ref) => SocketInspectNotifier());

class SocketInspectNotifier extends ChangeNotifier {
  List<SocketLog> logs = [];
  List<SocketLog> originalLogs = [];
  bool isSearching = false;
  String searchText = "";
  int tabIndex = 0;

  // Updates logs based on search and tab selection
  updateLogs(List<SocketLog> val) {
    originalLogs = val;
    updateLogsBasedOnSearch();
  }

  // Toggles search state
  updateIsSearching() {
    isSearching = !isSearching;
    notifyListeners();
  }

  // Updates search text
  updateSearchText(String val) {
    searchText = val;
    updateLogsBasedOnSearch();
  }

  // Updates the tab index and applies corresponding filters
  updateTabIndex(int val) {
    tabIndex = val;
    updateLogsBasedOnSearch();
  }

  // Clears all logs and resets search state
  clearAll() {
    logs.clear();
    searchText = "";
    isSearching = false;
    notifyListeners();
  }

  // Handles search input changes
  onChangeSearch(String pattern) {
    searchText = pattern;
    updateLogsBasedOnSearch();
  }

  // Filters logs based on search pattern and sending state
  List<SocketLog> filterLog(
      List<SocketLog> val, String pattern, bool? isSending) {
    final results = val.where(
      (element) {
        bool val = isSending == null ? true : element.isSending == isSending;
        bool containsEvent =
            element.event.toLowerCase().contains(pattern.toLowerCase());
        bool containsMessage =
            element.message?.toLowerCase().contains(pattern.toLowerCase()) ??
                false;
        return (containsMessage || containsEvent) && val;
      },
    ).toList();
    return results;
  }

  // Helper method to update logs based on the current tab and search text
  void updateLogsBasedOnSearch() {
    if (searchText.isEmpty) {
      logs = _getLogsBasedOnTab();
    } else {
      logs = filterLog(originalLogs, searchText, _getIsSendingForTab());
    }
    notifyListeners();
  }

  // Gets logs based on the current tab index
  List<SocketLog> _getLogsBasedOnTab() {
    switch (tabIndex) {
      case 1:
        return originalLogs
            .where((element) => element.isSending == true)
            .toList();
      case 2:
        return originalLogs
            .where((element) => element.isSending == false)
            .toList();
      default:
        return originalLogs;
    }
  }

  // Returns the sending state (true for sending, false for receiving, null for all)
  bool? _getIsSendingForTab() {
    if (tabIndex == 1) return true;
    if (tabIndex == 2) return false;
    return null;
  }
}
