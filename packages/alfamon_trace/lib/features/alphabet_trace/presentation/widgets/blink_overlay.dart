import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/alphabet_trace_provider.dart';

/// White flash when stroke 1 completes (transition to stroke 2).
class BlinkOverlay extends ConsumerStatefulWidget {
  const BlinkOverlay({super.key});

  @override
  ConsumerState<BlinkOverlay> createState() => _BlinkOverlayState();
}

class _BlinkOverlayState extends ConsumerState<BlinkOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(showBlinkProvider, (prev, next) {
      if (next && !_controller.isAnimating) {
        ref.read(showBlinkProvider.notifier).state = false;
        _controller.forward(from: 0).then((_) {
          _controller.reverse();
        });
      }
    });

    if (!_controller.isAnimating && _controller.value == 0) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            final opacity = _controller.value * 0.95;
            return Container(
              color: Color.fromRGBO(255, 255, 255, opacity),
            );
          },
        ),
      ),
    );
  }
}
