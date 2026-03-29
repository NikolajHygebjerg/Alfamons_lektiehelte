import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../alphabet_trace/alphabet_trace.dart';

/// Welcome screen with full-screen image and play button.
class TraceHomeScreen extends ConsumerStatefulWidget {
  const TraceHomeScreen({super.key});

  @override
  ConsumerState<TraceHomeScreen> createState() => _TraceHomeScreenState();
}

class _TraceHomeScreenState extends ConsumerState<TraceHomeScreen> {
  Timer? _parentalTimer;

  void _onParentalPressDown() {
    _parentalTimer?.cancel();
    _parentalTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Forældreindstillinger – coming soon')),
        );
      }
    });
  }

  void _onParentalPressUp() {
    _parentalTimer?.cancel();
    _parentalTimer = null;
  }

  @override
  void dispose() {
    _parentalTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black26,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
        title: const Text('Tegn bogstaver'),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'packages/alfamon_trace/Assets/welcome.jpg',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.blue.shade50,
              child: const Center(
                child: Text('Welcome', style: TextStyle(fontSize: 48)),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Center(
              child: _PlayButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AlphabetTraceScreen(),
                    ),
                  );
                },
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 48,
            child: GestureDetector(
              onTapDown: (_) => _onParentalPressDown(),
              onTapUp: (_) => _onParentalPressUp(),
              onTapCancel: _onParentalPressUp,
              child: const SizedBox.expand(),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(80),
        child: Container(
          width: 160,
          height: 160,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(
            Icons.play_arrow,
            size: 100,
            color: Colors.blue.shade700,
          ),
        ),
      ),
    );
  }
}
