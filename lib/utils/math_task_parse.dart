/// Parser til admin-input, fx `1+1=2` eller `12 - 5 = 7`.
class MathTaskParseResult {
  const MathTaskParseResult({required this.prompt, required this.answer});

  final String prompt;
  final String answer;
}

MathTaskParseResult? parseMathTaskLine(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final idx = t.indexOf('=');
  if (idx <= 0 || idx >= t.length - 1) return null;
  final prompt = t.substring(0, idx).trim();
  final answer = t.substring(idx + 1).trim();
  if (prompt.isEmpty || answer.isEmpty) return null;
  return MathTaskParseResult(prompt: prompt, answer: answer);
}

/// Resultat af indsætning af mange linjer (én opgave pr. linje: `regnestykke=svar`).
class MathBulkParseResult {
  const MathBulkParseResult({
    required this.tasks,
    required this.invalidCount,
    required this.invalidSamples,
  });

  final List<MathTaskParseResult> tasks;
  final int invalidCount;
  final List<String> invalidSamples;
}

/// Tomme linjer springes over. Ugyldige linjer tælles; [invalidSamples] er første eksempler.
MathBulkParseResult parseMathTaskPaste(String raw, {int maxInvalidSamples = 6}) {
  final lines = raw.split(RegExp(r'\r?\n'));
  final tasks = <MathTaskParseResult>[];
  var invalidCount = 0;
  final invalidSamples = <String>[];
  for (final line in lines) {
    final t = line.trim();
    if (t.isEmpty) continue;
    final p = parseMathTaskLine(t);
    if (p != null) {
      tasks.add(p);
    } else {
      invalidCount++;
      if (invalidSamples.length < maxInvalidSamples) {
        invalidSamples.add(t.length > 72 ? '${t.substring(0, 72)}…' : t);
      }
    }
  }
  return MathBulkParseResult(
    tasks: tasks,
    invalidCount: invalidCount,
    invalidSamples: invalidSamples,
  );
}

String _normSpaces(String s) => s.trim().replaceAll(RegExp(r'\s+'), '');

/// Sammenlign barnets svar med forventet (tillader mellemrum; numerisk hvis begge parser).
bool mathAnswersMatch(String expected, String given) {
  final a = _normSpaces(expected).replaceAll(',', '.');
  final b = _normSpaces(given).replaceAll(',', '.');
  if (a == b) return true;
  final na = num.tryParse(a);
  final nb = num.tryParse(b);
  if (na != null && nb != null) return na == nb;
  return false;
}
