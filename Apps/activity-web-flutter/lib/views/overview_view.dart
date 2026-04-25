import 'package:flutter/material.dart';
import 'dart:async';

import '../api/api_client.dart';
import '../api/models.dart';

/// Overview surface: status pills + the most recent five audit events.
/// Polls `/api/status` every 5s and tails `/ws/events` live.
class OverviewView extends StatefulWidget {
  const OverviewView({super.key, required this.api});

  final ApiClient api;

  @override
  State<OverviewView> createState() => _OverviewViewState();
}

class _OverviewViewState extends State<OverviewView> {
  StatusResponse? _status;
  Object? _statusError;
  Timer? _statusTimer;
  StreamSubscription<AuditRecord>? _wsSub;
  final List<AuditRecord> _recent = [];

  @override
  void initState() {
    super.initState();
    _refreshStatus();
    _statusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshStatus(),
    );
    _connectStream();
  }

  Future<void> _refreshStatus() async {
    try {
      final s = await widget.api.status();
      if (mounted) setState(() {
        _status = s;
        _statusError = null;
      });
    } catch (e) {
      if (mounted) setState(() => _statusError = e);
    }
  }

  void _connectStream() {
    _wsSub?.cancel();
    _wsSub = widget.api.auditStream().listen(
      (r) {
        if (!mounted) return;
        setState(() {
          _recent.insert(0, r);
          if (_recent.length > 5) _recent.removeLast();
        });
      },
      onError: (_) {
        // Reconnect after a short delay.
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (mounted) _connectStream();
        });
      },
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          Text('Agent Activity', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Live view of what the MCP agent is doing right now.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          _statusCard(theme),
          const SizedBox(height: 24),
          Text('Recent tool calls', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_recent.isEmpty)
            _empty(theme, 'Waiting for the agent\'s next call…')
          else
            ..._recent.map((r) => _AuditTile(record: r)),
        ],
      ),
    );
  }

  Widget _statusCard(ThemeData theme) {
    if (_statusError != null) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Daemon unreachable: $_statusError',
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
        ),
      );
    }
    final s = _status;
    if (s == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: LinearProgressIndicator(),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Pill(
                  label: 'Sources',
                  value: s.sources.isEmpty ? '—' : s.sources.join(', '),
                ),
                _Pill(
                  label: 'Captured events',
                  value: '${s.capturedEventCount}',
                ),
                _Pill(
                  label: 'Actions',
                  value: s.actionsEnabled ? 'enabled' : 'disabled',
                  highlight: s.actionsEnabled,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Permissions', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: s.permissions.entries
                  .map((e) => Chip(label: Text('${e.key}: ${e.value}')))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(ThemeData theme, String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            msg,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: highlight
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.record});

  final AuditRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcomeColor =
        _outcomeColor(record.outcome, theme.colorScheme);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(Icons.bolt_outlined, color: outcomeColor),
        title: Text(record.tool,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(record.outcome,
            style: TextStyle(color: outcomeColor)),
        trailing: Text(
          _hhmmss(record.timestamp),
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }

  static Color _outcomeColor(String outcome, ColorScheme s) {
    if (outcome == 'succeeded') return s.primary;
    if (outcome == 'rate_limited') return Colors.orange;
    if (outcome.startsWith('error')) return s.error;
    return s.onSurfaceVariant;
  }

  static String _hhmmss(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
  }
}
