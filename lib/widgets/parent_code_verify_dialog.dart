import 'package:flutter/material.dart';

import '../services/parent_code_service.dart';

/// Spørg om 4-cifret forældrekode og sammenlign med [ParentCodeService.fetchApprovalCode].
/// Viser snackbar hvis kode mangler eller er forkert.
Future<bool> showParentCodeVerificationDialog(
  BuildContext context, {
  required String title,
  required String explanation,
}) async {
  final stored = await ParentCodeService.fetchApprovalCode();
  if (stored == null || stored.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Forældrekode er ikke sat endnu. Brug voksen-administrationen først, '
            'eller opret koden under Indstillinger.',
          ),
        ),
      );
    }
    return false;
  }

  if (!context.mounted) return false;
  final code = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ParentCodeVerifyDialog(
      title: title,
      explanation: explanation,
    ),
  );
  if (code == null) return false;
  if (code.trim() != stored) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Forkert forældrekode')),
      );
    }
    return false;
  }
  return true;
}

class _ParentCodeVerifyDialog extends StatefulWidget {
  const _ParentCodeVerifyDialog({
    required this.title,
    required this.explanation,
  });

  final String title;
  final String explanation;

  @override
  State<_ParentCodeVerifyDialog> createState() => _ParentCodeVerifyDialogState();
}

class _ParentCodeVerifyDialogState extends State<_ParentCodeVerifyDialog> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.explanation,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            maxLength: 4,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            decoration: const InputDecoration(
              hintText: '••••',
              counterText: '',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuller'),
        ),
        FilledButton(
          onPressed: _controller.text.length == 4 ? _submit : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF5A1A0D),
          ),
          child: const Text('Bekræft'),
        ),
      ],
    );
  }

  void _submit() {
    if (_controller.text.length != 4) return;
    Navigator.of(context).pop(_controller.text);
  }
}
