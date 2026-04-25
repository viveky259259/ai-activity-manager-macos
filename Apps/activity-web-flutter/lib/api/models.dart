/// DTOs that mirror the Swift `ActivityIPC` types over the wire. Field names
/// follow the Codable encoding (`camelCase` after Swift's default strategy).
class StatusResponse {
  final List<String> sources;
  final int capturedEventCount;
  final bool actionsEnabled;
  final Map<String, String> permissions;

  StatusResponse({
    required this.sources,
    required this.capturedEventCount,
    required this.actionsEnabled,
    required this.permissions,
  });

  factory StatusResponse.fromJson(Map<String, dynamic> json) => StatusResponse(
        sources: List<String>.from(json['sources'] as List<dynamic>),
        capturedEventCount: json['capturedEventCount'] as int,
        actionsEnabled: json['actionsEnabled'] as bool,
        permissions: Map<String, String>.from(
          (json['permissions'] as Map<dynamic, dynamic>).map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ),
        ),
      );
}

class ProcessSnapshot {
  final int pid;
  final String? bundleID;
  final String name;
  final String? user;
  final int memoryBytes;
  final double cpuPercent;
  final int threads;
  final bool isFrontmost;
  final bool isRestricted;
  final String? category;

  ProcessSnapshot({
    required this.pid,
    required this.bundleID,
    required this.name,
    required this.user,
    required this.memoryBytes,
    required this.cpuPercent,
    required this.threads,
    required this.isFrontmost,
    required this.isRestricted,
    required this.category,
  });

  factory ProcessSnapshot.fromJson(Map<String, dynamic> json) =>
      ProcessSnapshot(
        pid: json['pid'] as int,
        bundleID: json['bundleID'] as String?,
        name: json['name'] as String,
        user: json['user'] as String?,
        memoryBytes: json['memoryBytes'] as int,
        cpuPercent: (json['cpuPercent'] as num?)?.toDouble() ?? 0,
        threads: json['threads'] as int,
        isFrontmost: json['isFrontmost'] as bool? ?? false,
        isRestricted: json['isRestricted'] as bool? ?? false,
        category: json['category'] as String?,
      );
}

class ProcessesPage {
  final List<ProcessSnapshot> processes;
  final int? systemMemoryUsedBytes;
  final int? systemMemoryTotalBytes;
  final DateTime? sampledAt;

  ProcessesPage({
    required this.processes,
    this.systemMemoryUsedBytes,
    this.systemMemoryTotalBytes,
    this.sampledAt,
  });

  factory ProcessesPage.fromJson(Map<String, dynamic> json) => ProcessesPage(
        processes: (json['processes'] as List<dynamic>)
            .map((p) => ProcessSnapshot.fromJson(p as Map<String, dynamic>))
            .toList(),
        systemMemoryUsedBytes: json['systemMemoryUsedBytes'] as int?,
        systemMemoryTotalBytes: json['systemMemoryTotalBytes'] as int?,
        sampledAt: json['sampledAt'] != null
            ? DateTime.tryParse(json['sampledAt'] as String)
            : null,
      );
}

class AuditRecord {
  final String tool;
  final dynamic params;
  final String outcome;
  final DateTime timestamp;

  AuditRecord({
    required this.tool,
    required this.params,
    required this.outcome,
    required this.timestamp,
  });

  factory AuditRecord.fromJson(Map<String, dynamic> json) => AuditRecord(
        tool: json['tool'] as String,
        params: json['params'],
        outcome: json['outcome'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

class TimelineSession {
  final DateTime start;
  final DateTime end;
  final String label;

  TimelineSession({
    required this.start,
    required this.end,
    required this.label,
  });

  factory TimelineSession.fromJson(Map<String, dynamic> json) {
    final subject = json['subject'] as Map<String, dynamic>?;
    String label = 'unknown';
    if (subject != null && subject['app'] != null) {
      final app = subject['app'] as Map<String, dynamic>;
      label = (app['name'] as String?) ?? (app['bundleID'] as String? ?? 'app');
    } else if (subject != null && subject['idle'] != null) {
      label = 'idle';
    }
    return TimelineSession(
      start: DateTime.parse(json['start'] as String),
      end: DateTime.parse(json['end'] as String),
      label: label,
    );
  }
}
