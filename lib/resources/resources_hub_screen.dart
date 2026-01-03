// lib/resources/resources_hub_screen.dart
import 'dart:ui' show FontVariation;
import 'package:flutter/material.dart';

import '../app/sub_header_bar.dart';
import 'resources_page_screen.dart';

// ✅ NEW: dynamic resources
import 'resource.dart';
import 'resources_repository.dart';

// Top-level constants so ALL widgets/classes in this file can use them.
const Color kResBg = Color(0xFFECF3F4);
const Color kResInk = Color(0xFF044246);
const Color kResSub = Color(0xFF3A6A67);

class ResourcesHubScreen extends StatelessWidget {
  const ResourcesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ✅ keep placeholders exactly as before
    final placeholderItems = _resourceItems();

    return Scaffold(
      backgroundColor: kResBg,
      body: Column(
        children: [
          // ✅ Use app sub header (not AppBar)
          SubHeaderBar(
            title: 'Resources',
            onBack: () => Navigator.of(context).pop(),
          ),

          Expanded(
            child: _HubRefresh(
              // ✅ refresh only affects dynamic list (placeholders stay)
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // ✅ Existing placeholders (unchanged)
                  ..._buildPlaceholderList(context, placeholderItems),

                  // ✅ NEW: Dynamic WP resources section (added, doesn't replace placeholders)
                  const SizedBox(height: 18),
                  const _SectionHeader(title: 'LATEST FROM LVE'),
                  const SizedBox(height: 10),

                  // ✅ key lets parent refresh trigger rebuild
                  _DynamicResourcesList(key: _HubRefresh.dynamicKey),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPlaceholderList(
    BuildContext context,
    List<_ResourceItem> items,
  ) {
    return [
      ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final item = items[i];

          return ResourceTile(
            title: item.title,
            subtitle: item.subtitle,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  // ✅ page screen no longer has ResourcePageScreen(title/body)
                  builder: (_) => ResourcePageScreen.fromText(
                    title: item.title,
                    body: item.body,
                  ),
                ),
              );
            },
          );
        },
      ),
    ];
  }

  List<_ResourceItem> _resourceItems() {
    return const [
      _ResourceItem(
        title: 'Getting started',
        subtitle: 'How to use LVE day-to-day.',
        body:
            'This is a placeholder.\n\nAdd your real “getting started” content here.',
      ),
      _ResourceItem(
        title: 'Baby-led weaning basics',
        subtitle: 'A simple guide for starting solids.',
        body: 'This is a placeholder.\n\nAdd your real BLW basics content here.',
      ),
      _ResourceItem(
        title: 'Allergies and swaps',
        subtitle: 'Common allergens and safe substitutions.',
        body: 'This is a placeholder.\n\nAdd your allergy + swap guidance here.',
      ),
      _ResourceItem(
        title: 'Picky eating',
        subtitle: 'Practical strategies without pressure.',
        body: 'This is a placeholder.\n\nAdd your picky eating guidance here.',
      ),
      _ResourceItem(
        title: 'Batch cooking',
        subtitle: 'Save time with simple prep routines.',
        body: 'This is a placeholder.\n\nAdd your batch cooking guidance here.',
      ),
      _ResourceItem(
        title: 'Lunchbox ideas',
        subtitle: 'Easy options for daycare and school.',
        body: 'This is a placeholder.\n\nAdd your lunchbox guidance here.',
      ),
      _ResourceItem(
        title: 'Supplements (vegan kids)',
        subtitle: 'What parents commonly ask about.',
        body: 'This is a placeholder.\n\nAdd your supplements guidance here.',
      ),
      _ResourceItem(
        title: 'Protein and iron',
        subtitle: 'Simple ways to build balanced plates.',
        body: 'This is a placeholder.\n\nAdd your nutrition guidance here.',
      ),
      _ResourceItem(
        title: 'Choking vs gagging',
        subtitle: 'What’s normal, what’s not.',
        body: 'This is a placeholder.\n\nAdd your safety guidance here.',
      ),
      _ResourceItem(
        title: 'Food exposure checklist',
        subtitle: 'Build variety over time.',
        body: 'This is a placeholder.\n\nAdd your exposure checklist here.',
      ),
    ];
  }
}

/// ✅ Wraps the hub list in pull-to-refresh.
/// When pulled, it forces the dynamic list to refresh from WP (bypassing cache).
class _HubRefresh extends StatefulWidget {
  final Widget child;
  const _HubRefresh({required this.child});

  // key used to force rebuild of the dynamic section
  static final GlobalKey<_DynamicResourcesListState> dynamicKey =
      GlobalKey<_DynamicResourcesListState>();

  @override
  State<_HubRefresh> createState() => _HubRefreshState();
}

class _HubRefreshState extends State<_HubRefresh> {
  Future<void> _onRefresh() async {
    // trigger dynamic list refresh + wait until it completes
    await _HubRefresh.dynamicKey.currentState?.refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: widget.child,
    );
  }
}

class _DynamicResourcesList extends StatefulWidget {
  const _DynamicResourcesList({super.key});

  @override
  State<_DynamicResourcesList> createState() => _DynamicResourcesListState();
}

class _DynamicResourcesListState extends State<_DynamicResourcesList> {
  final _repo = ResourcesRepository();
  late Future<List<Resource>> _future;

  @override
  void initState() {
    super.initState();
    _future = _repo.getResources();
  }

  /// ✅ called by pull-to-refresh
  Future<void> refresh({bool force = false}) async {
    setState(() {
      _future = _repo.getResources(forceRefresh: force);
    });
    // wait for fetch to complete so RefreshIndicator stops nicely
    try {
      await _future;
    } catch (_) {
      // swallow: UI will show error box
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Resource>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _LoadingBox();
        }

        if (snap.hasError) {
          return _ErrorBox(
            onRetry: () => refresh(force: true),
          );
        }

        final items = snap.data ?? const <Resource>[];
        if (items.isEmpty) {
          return const _EmptyBox();
        }

        // ✅ keep it compact on hub: show latest 6
        final top = items.take(6).toList();

        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: top.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final r = top[i];

            return ResourceTile(
              title: r.title,
              subtitle: _subtitleFromExcerpt(r.excerptHtml),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    // ✅ page screen now expects a Resource for dynamic pages
                    builder: (_) => ResourcePageScreen.fromResource(
                      resource: r,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _subtitleFromExcerpt(String html) {
    final txt = html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('\n', ' ')
        .trim();

    if (txt.isEmpty) return 'Tap to read';
    if (txt.length <= 72) return txt;
    return '${txt.substring(0, 72).trim()}…';
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w900,
          fontVariations: [FontVariation('wght', 900)],
          letterSpacing: 0.8,
          color: kResInk,
        ),
      ),
    );
  }
}

class _LoadingBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Loading resources…',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w600,
                fontVariations: [FontVariation('wght', 600)],
                color: kResSub,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorBox({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Couldn’t load resources.',
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w600,
                fontVariations: [FontVariation('wght', 600)],
                color: kResSub,
              ),
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  const _EmptyBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'No published resources yet.',
        style: TextStyle(
          fontFamily: 'Montserrat',
          fontWeight: FontWeight.w600,
          fontVariations: [FontVariation('wght', 600)],
          color: kResSub,
        ),
      ),
    );
  }
}

class ResourceTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const ResourceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w900,
                        fontVariations: [FontVariation('wght', 900)],
                        letterSpacing: 0.6,
                        color: kResInk,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w600,
                        fontVariations: [FontVariation('wght', 600)],
                        color: kResSub,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right, color: kResInk),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceItem {
  final String title;
  final String subtitle;
  final String body;

  const _ResourceItem({
    required this.title,
    required this.subtitle,
    required this.body,
  });
}
