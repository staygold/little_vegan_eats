import 'package:flutter/material.dart';

class TopHeaderBar extends StatelessWidget {
  const TopHeaderBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Colors.black.withOpacity(0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: const [
          Icon(Icons.eco),
          SizedBox(width: 8),
          Text(
            'Little Vegan Eats',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
