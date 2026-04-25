import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../api/models.dart';

/// Live MCP audit feed. Streams every `tools/call` outcome as it happens.
/// Filterable by outcome class and tool name.
class AuditView extends StatefulWidget {
  const AuditView({super.key, required this.api});

  final ApiClient api;

  @override
  State<AuditView> createState() => _AuditViewState();
}

class _AuditViewState extends State<AuditView> {
  final List<AuditRecord> _records = [];
  StreamSubscription<AuditRecord>? _sub;
  String _outcomeFilter = 'all';
  String _toolFilter = '';

  @override
  void initState() {
    super.initState();
    _connect();
  }

  void _connect() {
    _sub?.cancel();
    _sub = widget.api.auditStream().listen(
      (r) {
        if (!mounted) return;
        setState(() {
          _records.insert(0, r);
          if (_records.length > 500) _records.removeLast();
        });
      },
      onError: (_) => Future<void>.delayed(
          const Duration(seconds: 2), () => mounted ? _connect() : null),
      cancelOnError: true,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Iterable<AuditRecord> get _filtered {
    return _records.where((r) {
      if (_outcomeFilter != 'all') {
        if (_outcomeFilter == 'error' && !r.outcome.startsWith('error')) {
          return false;
        }
        if (_outcomeFilter != 'error' && r.outcome != _outcomeFilter) {
          return false;
        }
      }
      if (_toolFilter.isNotEmpty &&
          !r.tool.toLowerCase().contains(_toolFilter.toLowerCase())) {
        return false;
      }
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered.toList();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Audit Trail', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'Every MCP tool call the agent makes — succeeded, error, or rate-limited.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          _filterRow(),
          const SizedBox(height: 16),
          Expanded(
            child: filtered.isEmpty
                ? _empty(theme)
                : Card(
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemBuilder: (_, i) =>
                          _AuditRow(record: filtered[i]),
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemCount: filtered.length,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterRow() {
    return Row(
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('All')),
            ButtonSegment(value: 'succeeded', label: Text('OK')),
            ButtonSegment(value: 'rate_limited', label: Text('Rate-limited')),
            ButtonSegment(value: 'error', label: Text('Errors')),
          ],
          selected: {_outcomeFilter},
          onSelectionChanged: (s) =>
              setState(() => _outcomeFilter = s.first),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 240,
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Filter by tool name…',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _toolFilter = v),
          ),
        ),
      ],
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hourglass_empty,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('No tool calls yet.',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'The feed will populate as the agent runs.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.record});

  final AuditRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcomeColor = _outcomeColor(record.outcome, theme.colorScheme);
    final time = DateFormat('HH:mm:ss').format(record.timestamp.toLocal());
    return ListTile(
      leading: SizedBox(
        width: 72,
        child: Text(time,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ),
      title: Text(record.tool,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(
        record.outcome,
        style: TextStyle(color: outcomeColor),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.expand_more),
        tooltip: 'View params',
        onPressed: () => _showParams(context, record),
      ),
    );
  }

  void _showParams(BuildContext context, AuditRecord r) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${r.tool} — params'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Text(
              const JsonEncoderPretty().convert(r.params),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close')),
        ],
      ),
    );
  }

  static Color _outcomeColor(String outcome, ColorScheme s) {
    if (outcome == 'succeeded') return s.primary;
    if (outcome == 'rate_limited') return Colors.orange;
    if (outcome.startsWith('error')) return s.error;
    return s.onSurfaceVariant;
  }
}

class JsonEncoderPretty {
  const JsonEncoderPretty();
  String convert(dynamic value) {
    return _stringify(value, 0);
  }

  String _stringify(dynamic v, int indent) {
    final pad = '  ' * indent;
    if (v is Map) {
      if (v.isEmpty) return '{}';
      final inner = v.entries
          .map((e) => '$pad  "${e.key}": ${_stringify(e.value, indent + 1)}')
          .join(',\n');
      return '{\n$inner\n$pad}';
    }
    if (v is List) {
      if (v.isEmpty) return '[]';
      final inner =
          v.map((x) => '$pad  ${_stringify(x, indent + 1)}').join(',\n');
      return '[\n$inner\n$pad]';
    }
    if (v is String) return '"$v"';
    return v.toString();
  }
}
