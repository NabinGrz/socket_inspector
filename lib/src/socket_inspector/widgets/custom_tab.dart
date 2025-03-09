import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logger_provider.dart';

Widget tabItem({
  required String title,
  required Icon icon,
  required int tabIndex,
}) {
  return Expanded(
    child: Consumer(
      builder: (context, ref, _) {
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            ref.read(socketInspectorProvider.notifier).updateTabIndex(tabIndex);
          },
          child: Ink(
            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color:
                  ref.watch(socketInspectorProvider).tabIndex == tabIndex
                      ? Colors.amber
                      : const Color.fromARGB(255, 78, 175, 255),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [icon, SizedBox(width: 2), Text(title)],
            ),
          ),
        );
      },
    ),
  );
}
