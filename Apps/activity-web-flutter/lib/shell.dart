import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Outer shell: a NavigationRail on the left + the active route on the
/// right. One destination per surface: Overview, Audit Trail, Timeline,
/// Processes, Rules.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  static const _destinations = [
    _Dest(path: '/', icon: Icons.dashboard_outlined, label: 'Overview'),
    _Dest(path: '/audit', icon: Icons.receipt_long_outlined, label: 'Audit'),
    _Dest(path: '/timeline', icon: Icons.timeline_outlined, label: 'Timeline'),
    _Dest(
        path: '/processes',
        icon: Icons.memory_outlined,
        label: 'Processes'),
    _Dest(path: '/rules', icon: Icons.rule_outlined, label: 'Rules'),
  ];

  int _selectedIndex() {
    for (var i = 0; i < _destinations.length; i++) {
      final d = _destinations[i];
      if (d.path == '/' && location == '/') return 0;
      if (d.path != '/' && location.startsWith(d.path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex(),
            onDestinationSelected: (i) =>
                context.go(_destinations[i].path),
            destinations: _destinations
                .map((d) => NavigationRailDestination(
                      icon: Icon(d.icon),
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Dest {
  final String path;
  final IconData icon;
  final String label;
  const _Dest({required this.path, required this.icon, required this.label});
}
