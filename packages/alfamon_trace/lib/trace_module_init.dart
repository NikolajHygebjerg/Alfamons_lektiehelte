import 'package:hive_flutter/hive_flutter.dart';

import 'features/alphabet_trace/data/letter_progress_adapter.dart';
import 'features/alphabet_trace/data/progress_storage.dart';

/// Kald én gang fra appens [main] før [runApp] (efter [WidgetsFlutterBinding.ensureInitialized]).
Future<ProgressStorage> initAlfamonTraceModule() async {
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(LetterProgressAdapter());
  }
  final box = await ProgressStorage.openBox();
  return ProgressStorage(box);
}
