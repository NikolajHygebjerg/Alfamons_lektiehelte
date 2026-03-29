import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/alphabet_trace/logic/alphabet_trace_provider.dart';
import 'features/alphabet_trace/presentation/alphabet_trace_screen.dart';

/// Rod for `/trace` (bogstavgitter). Stopper al Trace-lyd når ruten forlades.
class TraceRouteScreen extends ConsumerStatefulWidget {
  const TraceRouteScreen({super.key});

  @override
  ConsumerState<TraceRouteScreen> createState() => _TraceRouteScreenState();
}

class _TraceRouteScreenState extends ConsumerState<TraceRouteScreen> {
  @override
  void dispose() {
    unawaited(stopAllAudio(ref));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const AlphabetTraceScreen();
}
