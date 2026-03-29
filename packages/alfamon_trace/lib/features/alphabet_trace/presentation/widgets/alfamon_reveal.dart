import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/alphabet_trace_provider.dart';
import '../../models/letter.dart';

/// When letter is fully traced: animate it flying off and reveal Alfamon image.
class AlfamonReveal extends ConsumerStatefulWidget {
  const AlfamonReveal({
    super.key,
    this.onGenindlaes,
    this.onAfbryd,
    this.onNaeste,
  });

  final VoidCallback? onGenindlaes;
  final VoidCallback? onAfbryd;
  final VoidCallback? onNaeste;

  @override
  ConsumerState<AlfamonReveal> createState() => _AlfamonRevealState();
}

class _AlfamonRevealState extends ConsumerState<AlfamonReveal>
    with TickerProviderStateMixin {
  late AnimationController _explosionController;
  late AnimationController _revealController;
  late Animation<double> _explosionAnimation;
  late Animation<double> _revealAnimation;

  @override
  void initState() {
    super.initState();
    _explosionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _explosionAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _explosionController, curve: Curves.easeOut),
    );
    _revealAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _revealController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _explosionController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  void _runReveal() {
    _explosionController.forward().then((_) {
      _revealController.forward();
    });
  }

  @override
  Widget build(BuildContext context) {
    final letter = ref.watch(selectedLetterProvider);
    final showReveal = ref.watch(showRevealProvider);

    if (letter == null || !showReveal) return const SizedBox.shrink();

    return _AlfamonRevealContent(
      ref: ref,
      letter: letter,
      explosionAnimation: _explosionAnimation,
      revealAnimation: _revealAnimation,
      onInit: _runReveal,
      onGenindlaes: widget.onGenindlaes,
      onAfbryd: widget.onAfbryd,
      onNaeste: widget.onNaeste,
    );
  }
}

class _AlfamonRevealContent extends StatefulWidget {
  const _AlfamonRevealContent({
    required this.ref,
    required this.letter,
    required this.explosionAnimation,
    required this.revealAnimation,
    required this.onInit,
    this.onGenindlaes,
    this.onAfbryd,
    this.onNaeste,
  });

  final WidgetRef ref;
  final Letter letter;
  final Animation<double> explosionAnimation;
  final Animation<double> revealAnimation;
  final VoidCallback onInit;
  final VoidCallback? onGenindlaes;
  final VoidCallback? onAfbryd;
  final VoidCallback? onNaeste;

  @override
  State<_AlfamonRevealContent> createState() => _AlfamonRevealContentState();
}

class _AlfamonRevealContentState extends State<_AlfamonRevealContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onInit();
      _playSuccessSound();
    });
  }

  Future<void> _playSuccessSound() async {
    final path = widget.letter.alfamonSuccessSoundPath;
    if (path == null || path.isEmpty) return;
    try {
      await widget.ref.read(oneShotAudioProvider).play(path);
    } catch (e) {
      if (kDebugMode) debugPrint('Success audio error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([
              widget.explosionAnimation,
              widget.revealAnimation,
            ]),
            builder: (context, child) {
              return Stack(
                alignment: Alignment.center,
                fit: StackFit.expand,
                children: [
                  if (widget.explosionAnimation.value < 1)
                    Positioned.fill(
                      child: _ExplosionOverlay(
                        progress: widget.explosionAnimation.value,
                      ),
                    ),
                  Opacity(
                    opacity: widget.revealAnimation.value,
                    child: _AlfamonImage(letter: widget.letter),
                  ),
                ],
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: SafeArea(
              child:               Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RevealIconButton(
                    icon: Icons.replay,
                    onPressed: widget.onGenindlaes,
                  ),
                  const SizedBox(width: 32),
                  _RevealIconButton(
                    icon: Icons.close,
                    onPressed: widget.onAfbryd,
                  ),
                  const SizedBox(width: 32),
                  _RevealIconButton(
                    icon: Icons.arrow_forward,
                    onPressed: widget.onNaeste,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Large child-friendly icon-only button.
class _RevealIconButton extends StatelessWidget {
  const _RevealIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(56),
        child: Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, size: 56, color: Colors.blue.shade700),
        ),
      ),
    );
  }
}

/// Explosion overlay: flash and expanding burst.
class _ExplosionOverlay extends StatelessWidget {
  const _ExplosionOverlay({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _ExplosionPainter(progress: progress),
          );
        },
      ),
    );
  }
}

class _ExplosionPainter extends CustomPainter {
  _ExplosionPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.longestSide * 0.6;

    // Flash (white/orange burst)
    final flashOpacity = (1 - progress).clamp(0.0, 1.0) * 0.8;
    final flashPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromRGBO(255, 200, 100, flashOpacity),
          Color.fromRGBO(255, 150, 50, flashOpacity * 0.5),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));
    canvas.drawCircle(center, maxRadius, flashPaint);

    // Expanding ring
    final ringRadius = maxRadius * 0.3 + progress * maxRadius * 0.5;
    final ringPaint = Paint()
      ..color = Color.fromRGBO(255, 180, 80, (1 - progress) * 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20;
    canvas.drawCircle(center, ringRadius, ringPaint);
  }

  @override
  bool shouldRepaint(_ExplosionPainter old) => old.progress != progress;
}

/// Alfamon image - fills entire screen.
class _AlfamonImage extends StatelessWidget {
  const _AlfamonImage({required this.letter});

  final Letter letter;

  @override
  Widget build(BuildContext context) {
    final assetPath = letter.alfamonAssetPath;
    if (assetPath != null && assetPath.isNotEmpty) {
      return Image.asset(
        assetPath,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) =>
            _AlfamonPlaceholder(letter: letter),
      );
    }
    return _AlfamonPlaceholder(letter: letter);
  }
}

/// Placeholder for Alfamon image (offline, no assets yet).
class _AlfamonPlaceholder extends StatelessWidget {
  const _AlfamonPlaceholder({required this.letter});

  final Letter letter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        color: Colors.blue.shade100,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.blue.shade300, width: 4),
      ),
      child: Center(
        child: Text(
          '${letter.character} Alfamon',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade800,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
