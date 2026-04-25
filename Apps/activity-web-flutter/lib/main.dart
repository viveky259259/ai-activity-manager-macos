import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'api/api_client.dart';
import 'shell.dart';
import 'theme.dart';
import 'views/audit_view.dart';
import 'views/overview_view.dart';
import 'views/processes_view.dart';
import 'views/rules_view.dart';
import 'views/timeline_view.dart';

void main() {
  runApp(const ActivityWebApp());
}

class ActivityWebApp extends StatelessWidget {
  const ActivityWebApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiClient();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (ctx, state, child) => AppShell(
            location: state.uri.path,
            child: child,
          ),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, __) => OverviewView(api: api),
            ),
            GoRoute(
              path: '/audit',
              builder: (_, __) => AuditView(api: api),
            ),
            GoRoute(
              path: '/timeline',
              builder: (_, __) => TimelineView(api: api),
            ),
            GoRoute(
              path: '/processes',
              builder: (_, __) => ProcessesView(api: api),
            ),
            GoRoute(
              path: '/rules',
              builder: (_, __) => RulesView(api: api),
            ),
          ],
        ),
      ],
    );
    return MaterialApp.router(
      title: 'Activity Manager',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
