import 'package:flutter/material.dart';

import '../api/api_client.dart';

/// Lists currently persisted rules. Rule shape is rendered generically — the
/// daemon emits the full Rule struct, the UI shows name, mode, and trigger.
class RulesView extends StatefulWidget {
  const RulesView({super.key, required this.api});

  final ApiClient api;

  @override
  State<RulesView> createState() => _RulesViewState();
}

class _RulesViewState extends State<RulesView> {
  Future<List<dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() => _future = widget.api.rules());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Rules', style: theme.textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Persisted automation rules. Edit/create from the macOS app for now.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _future,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                      child: Text('${snap.error}',
                          style:
                              TextStyle(color: theme.colorScheme.error)));
                }
                final rules = snap.data ?? [];
                if (rules.isEmpty) {
                  return Center(
                    child: Text(
                      'No rules yet.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }
                return Card(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) =>
                        _RuleRow(rule: rules[i] as Map<String, dynamic>),
                    itemCount: rules.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule});

  final Map<String, dynamic> rule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (rule['name'] as String?) ?? 'unnamed';
    final mode = (rule['mode'] as String?) ?? 'unknown';
    final trigger = rule['trigger'];
    final triggerLabel = _label(trigger);
    final modeColor = mode == 'active'
        ? theme.colorScheme.primary
        : (mode == 'disabled'
            ? theme.colorScheme.onSurfaceVariant
            : Colors.orange);
    return ListTile(
      leading: Icon(Icons.rule, color: modeColor),
      title: Text(name,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(triggerLabel),
      trailing: Chip(
        label: Text(mode),
        backgroundColor: modeColor.withValues(alpha: 0.15),
        labelStyle: TextStyle(color: modeColor),
      ),
    );
  }

  String _label(dynamic trigger) {
    if (trigger is Map<String, dynamic>) {
      if (trigger['appFocused'] != null) {
        final focus = trigger['appFocused'] as Map<String, dynamic>;
        return 'when ${focus['bundleID']} is focused';
      }
      if (trigger['idleEntered'] != null) {
        final idle = trigger['idleEntered'] as Map<String, dynamic>;
        return 'after ${idle['after']}s idle';
      }
      if (trigger['idleEnded'] != null) return 'when idle ends';
    }
    return 'custom trigger';
  }
}
