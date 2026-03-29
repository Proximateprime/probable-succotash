import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum BugCategory {
  uiBug,
  dataIssue,
  performance,
  featureRequest,
  other,
}

extension BugCategoryLabel on BugCategory {
  String get label {
    switch (this) {
      case BugCategory.uiBug:
        return 'UI Bug';
      case BugCategory.dataIssue:
        return 'Data Issue';
      case BugCategory.performance:
        return 'Performance';
      case BugCategory.featureRequest:
        return 'Feature Request';
      case BugCategory.other:
        return 'Other';
    }
  }

  String get value {
    switch (this) {
      case BugCategory.uiBug:
        return 'ui_bug';
      case BugCategory.dataIssue:
        return 'data_issue';
      case BugCategory.performance:
        return 'performance';
      case BugCategory.featureRequest:
        return 'feature_request';
      case BugCategory.other:
        return 'other';
    }
  }
}

class BugReportService {
  final Logger _logger = Logger();

  Future<void> submit({
    required String title,
    required String description,
    required BugCategory category,
    String? userEmail,
  }) async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    final email = userEmail ?? client.auth.currentUser?.email;

    try {
      await client.from('bug_reports').insert({
        'user_id': userId,
        'user_email': email,
        'category': category.value,
        'title': title.trim(),
        'description': description.trim(),
        'platform': 'web',
      });
      _logger.i('Bug report submitted: $title');
    } catch (e) {
      _logger.e('Bug report submission failed: $e');
      rethrow;
    }
  }
}
