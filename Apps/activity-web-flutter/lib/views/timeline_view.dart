import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../api/models.dart';

/// Activity timeline — historical sessions from the SQLite store. Polled.
class TimelineView extends StatefulWidget {
  const TimelineView({super.key, required this.api});

  final ApiClient api;

  @override
  State<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends State<TimelineView> {
  Future<List<TimelineSession>>? _future;
  Duration _window = const Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      final to = DateTime.now();
      final from = to.subtract(_window);
      _future = widget.api.timeline(from: from, to: to, limit: 200);
    });
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
              Text('Timeline', style: theme.textTheme.headlineSmall),
              const Spacer(),
              SegmentedButton<Duration>(
                segments: const [
                  ButtonSegment(
                      value: Duration(hours: 1), label: Text('1h')),
                  ButtonSegment(
                      value: Duration(hours: 6), label: Text('6h')),
                  ButtonSegment(
                      value: Duration(days: 1), label: Text('24h')),
                ],
                selected: {_window},
                onSelectionChanged: (s) {
                  setState(() => _window = s.first);
                  _refresh();
                },
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refresh,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<TimelineSession>>(
              future: _future,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _error(theme, snap.error);
                }
                final sessions = snap.data ?? [];
                if (sessions.isEmpty) {
                  return _empty(theme);
                }
                return Card(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemBuilder: (_, i) => _SessionRow(
                        session: sessions[i]),
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: sessions.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(ThemeData theme) => Center(
        child: Text(
          'No sessions in this window.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );

  Widget _error(ThemeData theme, Object? err) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '$err',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      );
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final TimelineSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('HH:mm:ss');
    final dur = session.end.difference(session.start);
    return ListTile(
      leading: Icon(
        session.label == 'idle'
            ? Icons.bedtime_outlined
            : Icons.window_outlined,
        color: theme.colorScheme.primary,
      ),
      title: Text(session.label,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${fmt.format(session.start.toLocal())}'
        ' → ${fmt.format(session.end.toLocal())}'
        '   (${_humanDuration(dur)})',
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  static String _humanDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    }
    return '${d.inSeconds}s';
  }
}
