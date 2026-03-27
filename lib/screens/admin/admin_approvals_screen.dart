import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/task_completion_service.dart';
import '../../widgets/admin/admin_menu_toolbar_button.dart';

class AdminApprovalsScreen extends StatefulWidget {
  const AdminApprovalsScreen({super.key});

  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await Supabase.instance.client
          .from('task_instances')
          .select('''
            id,
            kid_id,
            date,
            task:tasks(id, title),
            kid:kids(name)
          ''')
          .eq('status', 'needs_approval')
          .order('date', ascending: false);

      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(res as List);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _approve(Map<String, dynamic> item) async {
    final taskInstanceId = item['id'] as String;
    final kidId = item['kid_id'] as String;
    final taskName = (item['task'] as Map?)?['title'] ?? 'Opgave';
    final kidName = (item['kid'] as Map?)?['name'] ?? 'Barn';

    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ApprovalCodeDialog(
        taskName: taskName,
        kidName: kidName,
      ),
    );

    if (code == null || code.isEmpty) return;

    try {
      await TaskCompletionService.approve(
        taskInstanceId: taskInstanceId,
        kidId: kidId,
        parentCode: code,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opgave godkendt')),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fejl: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Godkend opgaver'),
        backgroundColor: const Color(0xFF5A1A0D),
        foregroundColor: Colors.white,
        actions: [
          const AdminMenuToolbarButton(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Prøv igen'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Ingen opgaver venter på godkendelse',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      itemBuilder: (context, i) {
        final item = _items[i];
        final taskName = (item['task'] as Map?)?['title'] ?? 'Opgave';
        final kidName = (item['kid'] as Map?)?['name'] ?? 'Barn';
        final date = item['date'] as String? ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: const Color(0xFFF9C433).withOpacity(0.9),
          child: ListTile(
            title: Text(taskName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('$kidName · $date'),
            trailing: ElevatedButton(
              onPressed: () => _approve(item),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5A1A0D),
                foregroundColor: Colors.white,
              ),
              child: const Text('Godkend'),
            ),
          ),
        );
      },
    );
  }
}

class _ApprovalCodeDialog extends StatefulWidget {
  final String taskName;
  final String kidName;

  const _ApprovalCodeDialog({
    required this.taskName,
    required this.kidName,
  });

  @override
  State<_ApprovalCodeDialog> createState() => _ApprovalCodeDialogState();
}

class _ApprovalCodeDialogState extends State<_ApprovalCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Indtast forældrekode'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Godkend "${widget.taskName}" for ${widget.kidName}'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Forældrekode',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuller'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF5A1A0D),
            foregroundColor: Colors.white,
          ),
          child: const Text('Godkend'),
        ),
      ],
    );
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }
}
