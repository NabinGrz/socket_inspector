import 'package:flutter/material.dart';

import '../socket_observer.dart';

class SocketEventListTile extends StatelessWidget {
  const SocketEventListTile({
    super.key,
    required this.log,
  });

  final SocketLog log;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            log.isSending == true
                ? Icon(
                    Icons.arrow_upward,
                    color: Colors.green,
                    size: 20,
                  )
                : Icon(
                    Icons.arrow_downward,
                    color: Colors.red,
                    size: 20,
                  ),
            SizedBox(
              width: 8,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Event [${log.event}]",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(
                    height: 4,
                  ),
                  SelectableText(
                    "Response: ${log.message}",
                    // textAlign: TextAlign.justify,
                    style: TextStyle(
                      fontSize: 12,
                    ),
                  ),
                  SizedBox(
                    height: 4,
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${log.timestamp}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (log.messageSize != null)
                        Text(
                          '${log.messageSize} bytes',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        Divider()
      ],
    );
  }
}
