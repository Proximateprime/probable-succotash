import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/analytics_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import '../services/supabase_service.dart';
import '../widgets/app_ui.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({Key? key}) : super(key: key);

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  static const double _defaultSwathWidthMeters = 15 * 0.3048;

  UserProfile? _currentUser;
  bool _isLoading = true;
  DateRange _selectedRange = DateRange.last30Days;
  DateTimeRange? _customRange;

  List<TrackingSession> _sessions = [];
  List<WorkerStats> _workerStats = [];
  SessionStats _summary = SessionStats.empty();

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);

    try {
      final supabase = context.read<SupabaseService>();
      final profile = await supabase.fetchCurrentUserProfile();

      if (!mounted) return;
      if (profile == null || supabase.currentUserId == null) {
        setState(() {
          _currentUser = null;
          _sessions = [];
          _workerStats = [];
          _summary = SessionStats.empty();
          _isLoading = false;
        });
        return;
      }

      final range = _effectiveRange();
      final dateFrom =
          DateTime(range.start.year, range.start.month, range.start.day);
      final dateTo =
          DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59);

      if (profile.role == 'corporate_admin') {
        final teamSessions = await supabase.fetchTeamSessions(
          supabase.currentUserId!,
          dateFrom: dateFrom,
          dateTo: dateTo,
        );
        final workers =
            await supabase.fetchTeamWorkers(supabase.currentUserId!);

        final mergedSessions = <TrackingSession>[];
        for (final sessions in teamSessions.values) {
          mergedSessions.addAll(sessions);
        }

        final workerStats = workers
            .map((worker) =>
                _buildWorkerStats(worker, teamSessions[worker.id] ?? []))
            .toList()
          ..sort((a, b) =>
              b.averageCoveragePercent.compareTo(a.averageCoveragePercent));

        setState(() {
          _currentUser = profile;
          _sessions = mergedSessions
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
          _workerStats = workerStats;
          _summary = _buildSessionStats(
            sessions: mergedSessions,
            dateFrom: dateFrom,
            dateTo: dateTo,
          );
          _isLoading = false;
        });
      } else {
        final sessions = await supabase.fetchUserSessions(
          supabase.currentUserId!,
          dateFrom: dateFrom,
          dateTo: dateTo,
        );

        setState(() {
          _currentUser = profile;
          _sessions = sessions
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
          _workerStats = [];
          _summary = _buildSessionStats(
            sessions: sessions,
            dateFrom: dateFrom,
            dateTo: dateTo,
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar.error('Failed to load analytics: $e'),
      );
    }
  }

  DateTimeRange _effectiveRange() {
    if (_customRange != null) return _customRange!;
    return DateTimeRange(
      start: _selectedRange.getStartDate(),
      end: _selectedRange.getEndDate(),
    );
  }

  Future<void> _pickCustomDateRange() async {
    final currentRange = _effectiveRange();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: currentRange,
    );

    if (picked == null) return;

    setState(() {
      _customRange = picked;
    });
    await _loadAnalytics();
  }

  String _csvEscape(String value) {
    final sanitized = value.replaceAll('"', '""');
    return '"$sanitized"';
  }

  String _buildCsvContent() {
    final buffer = StringBuffer();
    buffer.writeln(
      'session_id,property_id,user_id,start_time,end_time,coverage_percent,path_points,swath_width_feet,overlap_percent,overlap_savings_estimate,partial_completion_reason',
    );

    for (final session in _sessions) {
      buffer.writeln([
        _csvEscape(session.id),
        _csvEscape(session.propertyId),
        _csvEscape(session.userId),
        _csvEscape(session.startTime.toIso8601String()),
        _csvEscape(session.endTime?.toIso8601String() ?? ''),
        session.coveragePercent?.toStringAsFixed(2) ?? '',
        session.paths.length.toString(),
        session.swathWidthFeet?.toStringAsFixed(2) ?? '',
        session.overlapPercent?.toStringAsFixed(2) ?? '',
        session.overlapSavingsEstimate?.toStringAsFixed(2) ?? '',
        _csvEscape(session.partialCompletionReason ?? ''),
      ].join(','));
    }

    return buffer.toString();
  }

  Future<void> _exportCsv() async {
    final csv = _buildCsvContent();
    final fileName =
        'analytics_export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv';

    try {
      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: csv));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          AppSnackBar.info('CSV copied to clipboard (web fallback).'),
        );
        return;
      }

      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save analytics CSV',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
      );

      if (savePath == null || savePath.trim().isEmpty) {
        return;
      }

      final file = File(savePath);
      await file.writeAsString(csv, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar.success('CSV exported to $savePath'),
      );
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        AppSnackBar.warning('Could not save file. CSV copied to clipboard.'),
      );
    }
  }

  SessionStats _buildSessionStats({
    required List<TrackingSession> sessions,
    required DateTime dateFrom,
    required DateTime dateTo,
  }) {
    if (sessions.isEmpty) {
      return SessionStats(
        totalSessions: 0,
        totalTrackedMinutes: 0,
        averageSessionMinutes: 0,
        totalAcresCovered: 0,
        averageCoveragePercent: 0,
        dateFrom: dateFrom,
        dateTo: dateTo,
      );
    }

    double totalMinutes = 0;
    double totalAcres = 0;
    double coverageSum = 0;
    int coverageCount = 0;

    for (final session in sessions) {
      totalMinutes += _sessionMinutes(session);
      totalAcres += _sessionAcres(session);
      if (session.coveragePercent != null) {
        coverageSum += session.coveragePercent!;
        coverageCount++;
      }
    }

    return SessionStats(
      totalSessions: sessions.length,
      totalTrackedMinutes: totalMinutes,
      averageSessionMinutes: totalMinutes / sessions.length,
      totalAcresCovered: totalAcres,
      averageCoveragePercent:
          coverageCount == 0 ? 0 : coverageSum / coverageCount,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
  }

  WorkerStats _buildWorkerStats(
      UserProfile worker, List<TrackingSession> sessions) {
    if (sessions.isEmpty) {
      return WorkerStats.empty(worker.id, worker.email);
    }

    double totalMinutes = 0;
    double totalAcres = 0;
    double coverageSum = 0;
    int coverageCount = 0;

    for (final session in sessions) {
      totalMinutes += _sessionMinutes(session);
      totalAcres += _sessionAcres(session);
      if (session.coveragePercent != null) {
        coverageSum += session.coveragePercent!;
        coverageCount++;
      }
    }

    return WorkerStats(
      workerId: worker.id,
      workerEmail: worker.email,
      sessionCount: sessions.length,
      totalTrackedMinutes: totalMinutes,
      averageSessionMinutes: totalMinutes / sessions.length,
      totalAcresCovered: totalAcres,
      averageCoveragePercent:
          coverageCount == 0 ? 0 : coverageSum / coverageCount,
    );
  }

  double _sessionMinutes(TrackingSession session) {
    if (session.endTime != null) {
      return session.endTime!.difference(session.startTime).inSeconds / 60;
    }

    if (session.paths.length >= 2) {
      return session.paths.last.timestamp
              .difference(session.paths.first.timestamp)
              .inSeconds /
          60;
    }

    return 0;
  }

  double _sessionAcres(TrackingSession session) {
    final distanceKm = _pathDistanceMiles(session.paths) * 1.60934;
    final coverage = session.coveragePercent ?? 0;

    return SessionStats.calculateAcres(
      distanceKm: distanceKm,
      swathWidthMeters: _defaultSwathWidthMeters,
      coveragePercent: coverage,
    );
  }

  double _pathDistanceMiles(List<TrackingPath> paths) {
    if (paths.length < 2) return 0;

    double totalMeters = 0;
    for (var index = 0; index < paths.length - 1; index++) {
      final current = paths[index];
      final next = paths[index + 1];
      final latDiff = current.latitude - next.latitude;
      final lonDiff = current.longitude - next.longitude;
      totalMeters +=
          ((latDiff * latDiff) + (lonDiff * lonDiff)).sqrtApprox() * 111139;
    }

    return totalMeters / 1609.34;
  }

  List<FlSpot> _buildAcresSpots() {
    final daily = <DateTime, double>{};
    for (final session in _sessions) {
      final day = DateTime(session.startTime.year, session.startTime.month,
          session.startTime.day);
      daily.update(day, (value) => value + _sessionAcres(session),
          ifAbsent: () => _sessionAcres(session));
    }

    final sortedDays = daily.keys.toList()..sort();
    return List.generate(
      sortedDays.length,
      (index) => FlSpot(index.toDouble(), daily[sortedDays[index]] ?? 0),
    );
  }

  List<String> _acresLabels() {
    final days = <DateTime>[];
    final unique = <DateTime, bool>{};

    for (final session in _sessions) {
      final day = DateTime(session.startTime.year, session.startTime.month,
          session.startTime.day);
      if (unique[day] != true) {
        unique[day] = true;
        days.add(day);
      }
    }

    days.sort();
    final formatter = DateFormat.Md();
    return days.map(formatter.format).toList();
  }

  Widget _buildDateRangePicker() {
    final range = _effectiveRange();
    final rangeLabel =
        '${DateFormat.yMMMd().format(range.start)} - ${DateFormat.yMMMd().format(range.end)}';

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<DateRange>(
              initialValue: _selectedRange,
              decoration: const InputDecoration(
                labelText: 'Date Range',
                border: InputBorder.none,
              ),
              items: DateRange.values
                  .map(
                    (range) => DropdownMenuItem<DateRange>(
                      value: range,
                      child: Text(range.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                setState(() {
                  _selectedRange = value;
                  _customRange = null;
                });
                await _loadAnalytics();
              },
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _pickCustomDateRange,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(rangeLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        _buildStatCard(
          label: 'Total Acres',
          value: _summary.totalAcresCovered.toStringAsFixed(1),
          icon: Icons.landscape_outlined,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          label: 'Average Coverage',
          value: '${_summary.averageCoveragePercent.toStringAsFixed(1)}%',
          icon: Icons.track_changes,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          label: 'Total Time',
          value: _formatMinutes(_summary.totalTrackedMinutes),
          icon: Icons.schedule,
        ),
      ],
    );
  }

  String _formatMinutes(double minutes) {
    final duration = Duration(minutes: minutes.round());
    final hours = duration.inHours;
    final mins = duration.inMinutes.remainder(60);
    if (hours == 0) return '${mins}m';
    return '${hours}h ${mins}m';
  }

  Widget _buildLineChart() {
    final spots = _buildAcresSpots();
    final labels = _acresLabels();
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Acres Over Time',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Daily covered acreage across the selected date range.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 240,
            child: spots.isEmpty
                ? _buildEmptyState(
                    'No session data available for the selected range.')
                : LineChart(
                    LineChartData(
                      minY: 0,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 1,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.4),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) => Text(
                              value.toStringAsFixed(0),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= labels.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  labels[index],
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          barWidth: 3,
                          color: colorScheme.primary,
                          belowBarData: BarAreaData(
                            show: true,
                            color: colorScheme.primary.withValues(alpha: 0.16),
                          ),
                          dotData: FlDotData(
                            show: true,
                            getDotPainter: (_, __, ___, ____) =>
                                FlDotCirclePainter(
                              radius: 3.5,
                              color: colorScheme.primary,
                              strokeWidth: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerBarChart() {
    if (_currentUser?.role != 'corporate_admin') {
      return const SizedBox.shrink();
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Worker Average Coverage',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Comparison of average completion by worker.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 240,
            child: _workerStats.isEmpty
                ? _buildEmptyState('No worker analytics available yet.')
                : BarChart(
                    BarChartData(
                      minY: 0,
                      maxY: 100,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 20,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.4),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 34,
                            getTitlesWidget: (value, meta) => Text(
                              '${value.toInt()}%',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 42,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= _workerStats.length) {
                                return const SizedBox.shrink();
                              }
                              final label = _workerStats[index]
                                  .workerEmail
                                  .split('@')
                                  .first;
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  label,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: List.generate(
                        _workerStats.length,
                        (index) => BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: _workerStats[index].averageCoveragePercent,
                              color: Theme.of(context).colorScheme.primary,
                              width: 20,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerTable() {
    if (_currentUser?.role != 'corporate_admin') {
      return const SizedBox.shrink();
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Worker Breakdown',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          if (_workerStats.isEmpty)
            _buildEmptyState('No worker sessions found in this range.')
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                ),
                columns: const [
                  DataColumn(label: Text('Worker')),
                  DataColumn(label: Text('Sessions')),
                  DataColumn(label: Text('Avg %')),
                  DataColumn(label: Text('Acres')),
                  DataColumn(label: Text('Time')),
                ],
                rows: List.generate(
                  _workerStats.length,
                  (index) {
                    final stat = _workerStats[index];
                    return DataRow(
                      color: WidgetStatePropertyAll(
                        index.isEven
                            ? Theme.of(context)
                                .colorScheme
                                .surfaceContainerLowest
                            : Theme.of(context).colorScheme.surface,
                      ),
                      cells: [
                        DataCell(Text(stat.workerEmail)),
                        DataCell(Text(stat.sessionCount.toString())),
                        DataCell(Text(
                            '${stat.averageCoveragePercent.toStringAsFixed(1)}%')),
                        DataCell(
                            Text(stat.totalAcresCovered.toStringAsFixed(1))),
                        DataCell(
                            Text(_formatMinutes(stat.totalTrackedMinutes))),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            onPressed: _sessions.isEmpty ? null : _exportCsv,
            icon: const Icon(Icons.download_outlined),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildDateRangePicker(),
                  const SizedBox(height: 16),
                  _buildSummaryCards(),
                  const SizedBox(height: 16),
                  _buildLineChart(),
                  if (_currentUser?.role == 'corporate_admin') ...[
                    const SizedBox(height: 16),
                    _buildWorkerBarChart(),
                    const SizedBox(height: 16),
                    _buildWorkerTable(),
                  ],
                ],
              ),
            ),
    );
  }
}

extension on num {
  double sqrtApprox() {
    final value = toDouble();
    if (value <= 0) return 0;

    var guess = value;
    for (var i = 0; i < 8; i++) {
      guess = 0.5 * (guess + value / guess);
    }
    return guess;
  }
}
