import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../services/tts_setup_launcher.dart';
import '../services/tts_setup_prefs.dart';

enum TtsIntroMode {
  /// Første besøg på admin-dashboard.
  adminOnboarding,

  /// Før matematikhjælp med «Lyt».
  reminder,

  /// Åbnet fra Admin → Indstillinger (ændrer ikke gemte valg).
  adminSettingsMenu,
}

enum _TtsAdminResult { decline, remindOnUse, configureDone }

enum _TtsReminderResult { stopReminding, continueAnyway, configureOpened }

bool _isMacPlatform() =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

/// Første gang på admin + valgfri påmindelse + genåbn fra indstillinger (statiske show-metoder, ikke en Widget).
class TtsSetupIntro {
  TtsSetupIntro._();

  static bool _adminShowing = false;
  static bool _reminderShowing = false;

  static String _platformHintsShort() {
    if (kIsWeb) {
      return 'I browseren afhænger oplæsning af talesprog i system/browser. '
          'Brug helst ny Chrome eller Edge.';
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return 'Systemindstillinger → Tilgængelighed → «Læs og tal» '
            '(nyere macOS; ældre vejledninger sagde «Talt indhold») → '
            'hent dansk under Systemstemme / Administrer stemmer.';
      case TargetPlatform.iOS:
        return 'Indstillinger → Tilgængelighed → Talt indhold → Stemmer.';
      case TargetPlatform.android:
        return 'Indstillinger → Tekst-til-tale / Sprog → Taleoutput.';
      case TargetPlatform.windows:
        return 'Indstillinger → Tid og sprog → Tale.';
      case TargetPlatform.linux:
        return 'Installér dansk talemotor for tilgængelighed (afhænger af distro).';
      case TargetPlatform.fuchsia:
        return 'Tjek systemets talesprog.';
    }
  }

  /// Udvidet trin-for-trin på Mac så teksten kan læses mens Systemindstillinger er åbne.
  static String _macGuidanceBody(bool forKidContext) {
    final intro = forKidContext
        ? 'Før oplæsning i matematikhjælp virker, skal denne Mac have dansk '
            'tale (tekst-til-tale).\n\n'
        : 'Når barnet bruger matematikhjælp, kan teksten læses højt. Det '
            'kræver dansk tekst-til-tale på denne Mac.\n\n';
    return '${intro}Gør sådan på Mac:\n'
        '1. Klik på Apple-symbol øverst til venstre → «Systemindstillinger».\n'
        '2. I venstre spalte: «Tilgængelighed» (scroll ned hvis du ikke ser listen).\n'
        '3. Vælg «Læs og tal» (på engelsk Mac: «Read & Speak»). Den findes '
        'ikke under «Tale» sammen med Livetale – det er et andet sted.\n'
        '   · Finder du den ikke: brug søgefeltet øverst i '
        'Systemindstillinger og søg efter «Læs og tal» eller «systemstemme».\n'
        '4. Åbn «Systemstemme» / «Administrer stemmer» og hent mindst én dansk stemme – '
        'vælg helst «Forbedret» eller «Premium» frem for «Standard» (naturligere lyd).\n'
        '5. Vælg den danske stemme som aktiv systemstemme, hvis du får valget.\n\n'
        'Du kan lade denne dialog stå åben, mens du arbejder i '
        'Systemindstillinger – brug «Åbn Systemindstillinger», hvis vinduet '
        'ligger bagved andre vinduer.';
  }

  static String _bodyForMode(TtsIntroMode mode) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      switch (mode) {
        case TtsIntroMode.adminOnboarding:
          return _macGuidanceBody(false);
        case TtsIntroMode.reminder:
          return _macGuidanceBody(true);
        case TtsIntroMode.adminSettingsMenu:
          return _macGuidanceBody(false);
      }
    }
    final hint = _platformHintsShort();
    switch (mode) {
      case TtsIntroMode.adminOnboarding:
        return 'Når barnet bruger matematikhjælp, kan teksten læses højt. '
            'Det kræver, at enheden har dansk tekst-til-tale.\n\n· $hint';
      case TtsIntroMode.reminder:
        return 'Du skal bruge tale til oplæsning.\n\n· $hint';
      case TtsIntroMode.adminSettingsMenu:
        return 'Matematikhjælp kan læse tekst højt, hvis enheden har dansk '
            'tekst-til-tale.\n\n· $hint';
    }
  }

  static String _titleForMode(TtsIntroMode mode) {
    switch (mode) {
      case TtsIntroMode.adminOnboarding:
        return 'Oplæsning i matematikhjælp';
      case TtsIntroMode.reminder:
        return 'Indstil tale til oplæsning';
      case TtsIntroMode.adminSettingsMenu:
        return 'Tale til matematikhjælp';
    }
  }

  static Future<void> showIfNeededForAdmin(BuildContext context) async {
    if (_adminShowing) return;
    if (!context.mounted) return;
    if (await TtsSetupPrefs.isAdminIntroDone()) return;
    if (!context.mounted) return;
    _adminShowing = true;
    try {
      final result = await showDialog<_TtsAdminResult>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _TtsIntroDialogShell(mode: TtsIntroMode.adminOnboarding),
      );
      switch (result) {
        case _TtsAdminResult.remindOnUse:
          await TtsSetupPrefs.completeAdminIntro(remindWhenUsing: true);
          break;
        case _TtsAdminResult.configureDone:
          if (!_isMacPlatform()) {
            await TtsSetupPrefs.completeAdminIntro(remindWhenUsing: false);
            final ok = await openTtsOrSpeechSettings();
            if (context.mounted && !ok) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Kunne ikke åbne systemindstillinger. Brug vejledningen ovenfor.',
                  ),
                ),
              );
            }
          }
          break;
        case _TtsAdminResult.decline:
        case null:
          await TtsSetupPrefs.completeAdminIntro(remindWhenUsing: false);
          break;
      }
    } finally {
      _adminShowing = false;
    }
  }

  /// Fra Admin → Indstillinger (påvirker ikke «første gang»-flag).
  static Future<void> showFromAdminSettings(BuildContext context) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) =>
          _TtsIntroDialogShell(mode: TtsIntroMode.adminSettingsMenu),
    );
  }

  static Future<void> showReminderIfNeeded(BuildContext context) async {
    if (_reminderShowing) return;
    if (!context.mounted) return;
    if (!await TtsSetupPrefs.shouldRemindWhenUsing()) return;
    if (!context.mounted) return;
    _reminderShowing = true;
    try {
      final choice = await showDialog<_TtsReminderResult>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => _TtsIntroDialogShell(mode: TtsIntroMode.reminder),
      );
      switch (choice) {
        case _TtsReminderResult.configureOpened:
          final ok = await openTtsOrSpeechSettings();
          if (context.mounted && !ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Kunne ikke åbne systemindstillinger.'),
              ),
            );
          }
          break;
        case _TtsReminderResult.stopReminding:
          await TtsSetupPrefs.clearRemindWhenUsing();
          break;
        case _TtsReminderResult.continueAnyway:
        case null:
          break;
      }
    } finally {
      _reminderShowing = false;
    }
  }
}

class _TtsIntroDialogShell extends StatefulWidget {
  const _TtsIntroDialogShell({required this.mode});

  final TtsIntroMode mode;

  @override
  State<_TtsIntroDialogShell> createState() => _TtsIntroDialogShellState();
}

class _TtsIntroDialogShellState extends State<_TtsIntroDialogShell> {
  /// På Mac: efter «Indstil»/«Åbn Systemindstillinger» forbliver dialogen med vejledning.
  bool _macAwaitingClose = false;

  bool get _mac => _isMacPlatform();

  Future<void> _openSettings() async {
    final ok = await openTtsOrSpeechSettings();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kunne ikke åbne systemindstillinger automatisk.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final title = TtsSetupIntro._titleForMode(mode);
    final body = TtsSetupIntro._bodyForMode(mode);

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: _mac ? 420 : 320,
        child: SingleChildScrollView(
          child: Text(
            body,
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
        ),
      ),
      actions: _buildActions(context, mode),
    );
  }

  List<Widget> _buildActions(BuildContext context, TtsIntroMode mode) {
    if (mode == TtsIntroMode.adminSettingsMenu) {
      if (_mac && _macAwaitingClose) {
        return [
          TextButton(
            onPressed: () async {
              await _openSettings();
            },
            child: const Text('Åbn Systemindstillinger igen'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF5A1A0D),
            ),
            child: const Text('Luk'),
          ),
        ];
      }
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Luk'),
        ),
        FilledButton(
          onPressed: () async {
            await _openSettings();
            if (mounted && _mac) {
              setState(() => _macAwaitingClose = true);
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5A1A0D),
          ),
          child: const Text('Åbn Systemindstillinger'),
        ),
      ];
    }

    if (mode == TtsIntroMode.adminOnboarding) {
      if (_mac && _macAwaitingClose) {
        return [
          TextButton(
            onPressed: () async {
              await _openSettings();
            },
            child: const Text('Åbn Systemindstillinger igen'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(_TtsAdminResult.configureDone),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF5A1A0D),
            ),
            child: const Text('Luk'),
          ),
        ];
      }
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_TtsAdminResult.decline),
          child: const Text('Afvis'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_TtsAdminResult.remindOnUse),
          child: const Text('Vis igen ved brug'),
        ),
        FilledButton(
          onPressed: () async {
            if (_mac) {
              await TtsSetupPrefs.completeAdminIntro(remindWhenUsing: false);
              await _openSettings();
              if (mounted) setState(() => _macAwaitingClose = true);
            } else {
              Navigator.of(context).pop(_TtsAdminResult.configureDone);
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5A1A0D),
          ),
          child: const Text('Indstil'),
        ),
      ];
    }

    // reminder
    if (_mac && _macAwaitingClose) {
      return [
        TextButton(
          onPressed: () async {
            await _openSettings();
          },
          child: const Text('Åbn Systemindstillinger igen'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_TtsReminderResult.stopReminding),
          child: const Text('Vis ikke mere'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_TtsReminderResult.continueAnyway),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5A1A0D),
          ),
          child: const Text('Fortsæt'),
        ),
      ];
    }

    return [
      TextButton(
        onPressed: () =>
            Navigator.of(context).pop(_TtsReminderResult.stopReminding),
        child: const Text('Vis ikke mere'),
      ),
      TextButton(
        onPressed: () =>
            Navigator.of(context).pop(_TtsReminderResult.continueAnyway),
        child: const Text('Fortsæt'),
      ),
      FilledButton(
        onPressed: () async {
          if (_mac) {
            await _openSettings();
            if (mounted) setState(() => _macAwaitingClose = true);
          } else {
            Navigator.of(context).pop(_TtsReminderResult.configureOpened);
          }
        },
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF5A1A0D),
        ),
        child: const Text('Indstil'),
      ),
    ];
  }
}
