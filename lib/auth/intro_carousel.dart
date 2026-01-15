import 'package:flutter/material.dart';

class IntroCarousel extends StatefulWidget {
  const IntroCarousel({
    super.key,
    required this.onGetStarted,
    required this.onLogin,
  });

  final VoidCallback onGetStarted;
  final VoidCallback onLogin;

  @override
  State<IntroCarousel> createState() => _IntroCarouselState();
}

class _IntroCarouselState extends State<IntroCarousel> {
  final _controller = PageController();
  int _index = 0;

  static const int _count = 3;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _count - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      widget.onGetStarted();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _count - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _index = i),
                children: const [
                  _Slide(
                    title: 'Family-friendly vegan recipes',
                    subtitle: 'Fast, realistic meals you’ll actually cook.',
                    icon: Icons.restaurant_menu,
                  ),
                  _Slide(
                    title: 'Meal plans that fit your kids',
                    subtitle: 'Age-aware suggestions and simple swaps.',
                    icon: Icons.calendar_month,
                  ),
                  _Slide(
                    title: 'Less stress, more structure',
                    subtitle: 'Build routines without feeling like forms.',
                    icon: Icons.favorite,
                  ),
                ],
              ),
            ),

            // Bottom controls (static)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _count,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: i == _index ? 14 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: i == _index
                              ? Colors.black.withOpacity(0.85)
                              : Colors.black.withOpacity(0.20),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: isLast ? widget.onGetStarted : _next,
                      child: Text(isLast ? 'Get started' : 'Next'),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextButton(
                    onPressed: widget.onLogin,
                    child: const Text('Already have an account? Log in'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 88),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.black.withOpacity(0.65),
                ),
          ),
        ],
      ),
    );
  }
}
