import 'package:flutter/material.dart';

class ReuseCandidate {
  final String sourceDayKey;
  final String sourceSlot;
  final int recipeId;
  final String recipeTitle;

  ReuseCandidate({
    required this.sourceDayKey,
    required this.sourceSlot,
    required this.recipeId,
    required this.recipeTitle,
  });
}

// ✅ This is the return type object
class ReusePick {
  final String fromDayKey;
  final String fromSlot;

  const ReusePick({
    required this.fromDayKey,
    required this.fromSlot,
  });
}

class ReuseRecipePage extends StatelessWidget {
  final String headerLabel;
  final List<ReuseCandidate> candidates;
  final String Function(String dayKey) formatDayPretty;

  const ReuseRecipePage({
    super.key,
    required this.headerLabel,
    required this.candidates,
    required this.formatDayPretty,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(headerLabel),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ),
      body: candidates.isEmpty
          ? const Center(child: Text('No reusable meals found.'))
          : ListView.separated(
              itemCount: candidates.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = candidates[i];
                return ListTile(
                  title: Text(c.recipeTitle),
                  subtitle: Text(
                    '${formatDayPretty(c.sourceDayKey)} • ${c.sourceSlot.replaceAll('_', ' ').toUpperCase()}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // ✅ Pop a ReusePick object directly
                    Navigator.of(context).pop(
                      ReusePick(
                        fromDayKey: c.sourceDayKey,
                        fromSlot: c.sourceSlot,
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}