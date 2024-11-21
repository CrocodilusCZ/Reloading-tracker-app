import 'package:flutter/material.dart';

class HeaderWidget extends StatelessWidget {
  final String username;

  const HeaderWidget({Key? key, required this.username}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.person, size: 40, color: Colors.blueGrey),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                username,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                'Verze aplikace: Shooting_companion_0.9',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
