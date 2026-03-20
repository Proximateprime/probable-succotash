import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/property_model.dart';
import '../models/user_model.dart';
import '../services/supabase_service.dart';
import 'property_detail_screen.dart';

class TeamOverviewScreen extends StatefulWidget {
  const TeamOverviewScreen({Key? key}) : super(key: key);

  @override
  State<TeamOverviewScreen> createState() => _TeamOverviewScreenState();
}

class _TeamOverviewScreenState extends State<TeamOverviewScreen> {
  List<Property> _properties = [];
  List<UserProfile> _allWorkers = [];
  Map<String, UserProfile> _workerMap =
      {}; // id -> UserProfile for quick lookup
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _openPropertyDetail(Property property) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PropertyDetailScreen(property: property),
      ),
    ).then((_) => _loadData());
  }

  String _workerDisplayName(UserProfile worker) {
    final local = worker.email.split('@').first.trim();
    if (local.isEmpty) return worker.email;
    final normalized = local.replaceAll(RegExp(r'[._-]+'), ' ');
    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) =>
            '${part[0].toUpperCase()}${part.length > 1 ? part.substring(1) : ''}')
        .join(' ');
  }

  List<UserProfile> _assignedWorkersFor(Property property) {
    if (property.assignedTo.isEmpty) return const [];
    return property.assignedTo
        .map((wid) => _workerMap[wid])
        .whereType<UserProfile>()
        .toList();
  }

  Future<void> _loadData() async {
    try {
      final supabase = context.read<SupabaseService>();
      if (supabase.currentUserId == null) return;

      final profile = await supabase.fetchCurrentUserProfile();
      final role = (profile?.role ?? '').toLowerCase();
      final tier = UserProfile.normalizeTierValue(profile?.tier ?? '');
      final isCorporateAdmin = role == 'corporate_admin' ||
          (tier == 'corporate' && role != 'worker');

      if (!isCorporateAdmin) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Team Overview is for corporate admins.')),
          );
        }
        return;
      }

      // Fetch all properties owned by this admin
      final properties = await supabase.fetchUserProperties(
        supabase.currentUserId!,
        userRole: 'corporate_admin',
      );

      // Fetch assignable workers (workers + solo professionals)
      final workersList = await supabase.fetchAssignableWorkers();

      // Build lookup map
      final workerMap = <String, UserProfile>{};
      for (final worker in workersList) {
        workerMap[worker.id] = worker;
      }

      if (mounted) {
        setState(() {
          _properties = properties;
          _allWorkers = workersList;
          _workerMap = workerMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading team data: $e')),
        );
      }
    }
  }

  Future<void> _updateAssignments(
    String propertyId,
    List<String> newAssignments,
  ) async {
    try {
      setState(() => _isSaving = true);
      final supabase = context.read<SupabaseService>();

      await supabase.updatePropertyAssignments(
        propertyId: propertyId,
        assignedTo: newAssignments,
      );

      // Update local state
      final idx = _properties.indexWhere((p) => p.id == propertyId);
      if (idx >= 0) {
        final updatedProperty = Property(
          id: _properties[idx].id,
          name: _properties[idx].name,
          address: _properties[idx].address,
          notes: _properties[idx].notes,
          ownerId: _properties[idx].ownerId,
          assignedTo: newAssignments,
          mapGeojson: _properties[idx].mapGeojson,
          orthomosaicUrl: _properties[idx].orthomosaicUrl,
          exclusionZones: _properties[idx].exclusionZones,
          specialZones: _properties[idx].specialZones,
          treatmentType: _properties[idx].treatmentType,
          lastApplication: _properties[idx].lastApplication,
          frequencyDays: _properties[idx].frequencyDays,
          nextDue: _properties[idx].nextDue,
          applicationRatePerAcre: _properties[idx].applicationRatePerAcre,
          applicationRateUnit: _properties[idx].applicationRateUnit,
          chemicalCostPerUnit: _properties[idx].chemicalCostPerUnit,
          defaultTankCapacityGallons:
              _properties[idx].defaultTankCapacityGallons,
          createdAt: _properties[idx].createdAt,
        );

        setState(() {
          _properties[idx] = updatedProperty;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Assignments updated'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating assignments: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showAssignmentDialog(Property property) {
    List<String> selectedWorkers = List.from(property.assignedTo);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Assign Workers'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Property: ${property.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                if (_allWorkers.isEmpty)
                  const Text('No workers available',
                      style: TextStyle(color: Colors.grey))
                else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _allWorkers.map((worker) {
                      final isSelected = selectedWorkers.contains(worker.id);
                      return FilterChip(
                        label: Text(worker.email),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              selectedWorkers.add(worker.id);
                            } else {
                              selectedWorkers.remove(worker.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _isSaving
                  ? null
                  : () {
                      _updateAssignments(property.id, selectedWorkers);
                      Navigator.pop(context);
                    },
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Overview'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _properties.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 48, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No properties yet'),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary stats
                      _buildSummaryCards(),
                      const SizedBox(height: 24),
                      // Properties with assignments
                      Text(
                        'All Properties',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _properties.length,
                        itemBuilder: (context, index) {
                          final property = _properties[index];
                          final assignedWorkers = _assignedWorkersFor(property);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _openPropertyDetail(property),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                property.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium,
                                              ),
                                              if (property.address != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 4),
                                                  child: Text(
                                                    property.address!,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                        const Icon(Icons.chevron_right),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.group,
                                          size: 18,
                                          color: Colors.blue,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Assigned Workers (${assignedWorkers.length})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    if (assignedWorkers.isEmpty)
                                      const Text(
                                        'No workers assigned',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      )
                                    else
                                      ...assignedWorkers.map(
                                        (worker) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 6),
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 12,
                                                child: Text(
                                                  worker.email.isNotEmpty
                                                      ? worker.email[0]
                                                          .toUpperCase()
                                                      : 'W',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  '${_workerDisplayName(worker)}  (${worker.email})',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _isSaving
                                            ? null
                                            : () =>
                                                _showAssignmentDialog(property),
                                        icon: const Icon(Icons.edit),
                                        label: const Text('Manage Workers'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSummaryCards() {
    final int totalWorkers = _allWorkers.length;
    final int propertiesWithWorkers =
        _properties.where((p) => p.assignedTo.isNotEmpty).length;
    final int activeWorkers = _allWorkers
        .where(
          (w) => _properties.any((p) => p.assignedTo.contains(w.id)),
        )
        .length;

    return Row(
      children: [
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Properties',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    '${_properties.length}',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assignable Workers',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    '$totalWorkers',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Assigned Properties',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    '$propertiesWithWorkers',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active Workers',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  Text(
                    '$activeWorkers',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
