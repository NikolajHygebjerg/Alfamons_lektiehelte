import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Simple navigation state. Offline, no backend.
final navigationProvider = StateProvider<String>((ref) => 'home');
