import 'package:flutter/material.dart';
import 'recipe_repository.dart';

class RecipesBootstrapGate extends StatefulWidget {
  final Widget child;

  const RecipesBootstrapGate({super.key, required this.child});

  @override
  State<RecipesBootstrapGate> createState() => _RecipesBootstrapGateState();
}

class _RecipesBootstrapGateState extends State<RecipesBootstrapGate> {
  late Future<void> _bootstrap;

  @override
  void initState() {
    super.initState();
    _bootstrap = _run();
  }

  Future<void> _run() async {
    debugPrint('[RecipesBootstrap] start');
    final recipes = await RecipeRepository.ensureRecipesLoaded();
    debugPrint('[RecipesBootstrap] done: ${recipes.length}');
    if (recipes.isEmpty) {
      throw Exception('No recipes available (cache empty and API returned 0).');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrap,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Preparing recipes…'),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not load recipes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text('${snapshot.error}', textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() => _bootstrap = _run()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return widget.child;
      },
    );
  }
}
