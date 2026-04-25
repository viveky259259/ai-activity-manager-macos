import 'dart:async';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';

/// Live snapshot of running processes — what `list_processes` MCP returns.
/// Polled every 5s with a manual refresh button.
class ProcessesView extends StatefulWidget {
  const ProcessesView({super.key, required this.api});

  final ApiClient api;

  @override
  State<ProcessesView> createState() => _ProcessesViewState();
}

class _ProcessesViewState extends State<ProcessesView> {
  ProcessesPage? _page;
  Object? _error;
  Timer? _timer;
  String _sort = 'memory';
  String _order = 'desc';

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refresh(),
    );
  }

  Future<void> _refresh() async {
    try {
      final p = await widget.api.listProcesses(
        sort: _sort,
        order: _order,
        limit: 100,
      );
      if (mounted) setState(() {
        _page = p;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
              Text('Processes', style: theme.textTheme.headlineSmall),
              const Spacer(),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'memory', label: Text('Memory')),
                  ButtonSegment(value: 'cpu', label: Text('CPU')),
                  ButtonSegment(value: 'name', label: Text('Name')),
                ],
                selected: {_sort},
                onSelectionChanged: (s) {
                  setState(() => _sort = s.first);
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
          if (_page != null) _systemMemoryCard(theme),
          const SizedBox(height: 16),
          Expanded(child: _body(theme)),
        ],
      ),
    );
  }

  Widget _systemMemoryCard(ThemeData theme) {
    final p = _page!;
    final used = p.systemMemoryUsedBytes ?? 0;
    final total = p.systemMemoryTotalBytes ?? 0;
    final pct = total > 0 ? used / total : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System memory', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0, 1),
                      minHeight: 10,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_gb(used)} / ${_gb(total)}'
                  '   (${(pct * 100).toStringAsFixed(0)}%)',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_error != null) {
      return Center(
          child: Text('$_error', style: TextStyle(color: theme.colorScheme.error)));
    }
    final p = _page;
    if (p == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Card(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => _ProcessRow(snap: p.processes[i]),
        itemCount: p.processes.length,
      ),
    );
  }

  static String _gb(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({required this.snap});

  final ProcessSnapshot snap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mb = snap.memoryBytes / (1024 * 1024);
    return ListTile(
      leading: SizedBox(
        width: 60,
        child: Text('${snap.pid}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            )),
      ),
      title: Text(snap.name,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(snap.bundleID ?? '—',
          style: theme.textTheme.bodySmall),
      trailing: Wrap(
        spacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (snap.category != null)
            Chip(
              label: Text(snap.category!),
              visualDensity: VisualDensity.compact,
            ),
          Text(
            '${mb.toStringAsFixed(0)} MB',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
