import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/letter_images.dart';
import '../../logic/alphabet_trace_provider.dart';
import '../../models/letter.dart';
import '../../utils/play_tale.dart';

/// Full-screen grid of 29 Danish letters using images from Assets/bogstaver.
/// Plays bogstavmusik.mp3 when shown.
class LetterSelector extends ConsumerStatefulWidget {
  const LetterSelector({super.key});

  @override
  ConsumerState<LetterSelector> createState() => _LetterSelectorState();
}

class _LetterSelectorState extends ConsumerState<LetterSelector> {
  static const _activatableLetters = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'Æ', 'Ø', 'Å'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isFirstVisit = !ref.read(hasVisitedLetterScreenProvider);
      ref.read(letterScreenMusicProvider).start(isFirstVisit: isFirstVisit);
    });
  }

  @override
  void dispose() {
    ref.read(letterScreenMusicProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lettersAsync = ref.watch(lettersProvider);
    final selectedLetter = ref.watch(selectedLetterProvider);

    return lettersAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      error: (e, _) => Center(
        child: Text('Fejl: $e', style: const TextStyle(color: Colors.white)),
      ),
      data: (letters) => Container(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const crossAxisCount = 6;
            const rowCount = 5;
            const padding = 12.0;
            const spacing = 10.0;
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final availableW = width - 2 * padding - (crossAxisCount - 1) * spacing;
            final availableH = height - 2 * padding - (rowCount - 1) * spacing;
            final cellWidth = availableW / crossAxisCount;
            final cellHeight = availableH / rowCount;
            final cellSize = cellWidth < cellHeight ? cellWidth : cellHeight;

            return Padding(
              padding: const EdgeInsets.all(padding),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  childAspectRatio: 1,
                  mainAxisExtent: cellSize,
                ),
                itemCount: danishAlphabet.length,
                itemBuilder: (context, index) {
                  final char = danishAlphabet[index];
                  final path = letterImagePaths[char];
                  if (path == null) return const SizedBox.shrink();

                  final isActivatable = _activatableLetters.contains(char);
                  final isSelected = selectedLetter?.character == char;

                  return _LetterImageTile(
                    assetPath: path,
                    letter: char,
                    isActivatable: isActivatable,
                    isSelected: isSelected,
                    onTap: isActivatable
                        ? () => _selectLetter(ref, letters, char)
                        : null,
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  void _selectLetter(WidgetRef ref, List<Letter> letters, String char) async {
    ref.read(hasVisitedLetterScreenProvider.notifier).state = true;
    final letterMusic = ref.read(letterScreenMusicProvider);
    await letterMusic.stop();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final letter = letters.firstWhere(
      (l) => l.character == char,
      orElse: () => letters.first,
    );
    ref.read(selectedLetterProvider.notifier).state = letter;
    ref.read(tracingProgressProvider.notifier).state = 0;
    ref.read(showRevealProvider.notifier).state = false;
    ref.read(currentStrokeIndexProvider.notifier).state = 0;
    ref.read(completedTracePointsProvider.notifier).state = [];
    ref.read(showRetryOverlayProvider.notifier).state = false;
    ref.read(showBlinkProvider.notifier).state = false;
    ref.read(currentStrokeProgressProvider.notifier).state = 0;
    ref.read(hasStartedCurrentStrokeProvider.notifier).state = false;
    await playTaleAndWait(ref, letter.alfamonTalePath);
    if (!mounted) return;
    final music = ref.read(drawingMusicProvider);
    await music.start(stopOtherMusic: () => letterMusic.stop());
    music.setMuted(ref.read(musicMutedProvider));
  }
}

class _LetterImageTile extends StatelessWidget {
  const _LetterImageTile({
    required this.assetPath,
    required this.letter,
    required this.isActivatable,
    required this.isSelected,
    this.onTap,
  });

  final String assetPath;
  final String letter;
  final bool isActivatable;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.all(4),
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Center(
          child: Text(
            letter,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      return Material(
        color: isSelected ? Colors.white24 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: child,
        ),
      );
    }
    return child;
  }
}
