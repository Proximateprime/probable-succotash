import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_constants.dart';
import '../models/plan_model.dart';
import '../services/stripe_service.dart';
import '../services/supabase_service.dart';
import '../utils/app_theme.dart';

class PlanSelectionScreen extends StatefulWidget {
  final VoidCallback onPlanSelected;

  const PlanSelectionScreen({
    Key? key,
    required this.onPlanSelected,
  }) : super(key: key);

  @override
  State<PlanSelectionScreen> createState() => _PlanSelectionScreenState();
}

class _PlanSelectionScreenState extends State<PlanSelectionScreen> {
  BillingPeriod _selectedPeriod = BillingPeriod.lifetime;
  bool _isProcessing = false;
  PlanType? _selectedPlan;

  String _tierFromPlanType(PlanType planType) {
    switch (planType) {
      case PlanType.hobbyist:
        return 'hobbyist';
      case PlanType.soloProfessional:
        return 'solo_professional';
      case PlanType.premiumSolo:
        return 'premium_solo';
      case PlanType.largeIndividual:
        return 'individual_large_land';
      case PlanType.corporate:
        return 'corporate';
    }
  }

  String _roleFromPlanType(PlanType planType) {
    if (planType == PlanType.corporate) return 'corporate_admin';
    return 'hobbyist';
  }

  Future<void> _selectPlan(PlanType planType) async {
    setState(() {
      _isProcessing = true;
      _selectedPlan = planType;
    });

    try {
      final supabase = context.read<SupabaseService>();
      final stripeService = StripePaymentService();

      if (supabase.currentUser == null) {
        throw Exception('User not authenticated');
      }

      final bool success;
      if (AppConstants.enableFreeBetaPlanActivation) {
        // Beta mode: activate selected tier directly without charging.
        success = true;
      } else {
        // Initiate Stripe checkout
        success = await stripeService.initiateCheckout(
          planType: planType,
          billingPeriod: _selectedPeriod,
          userEmail: supabase.currentUser!.email ?? '',
          userId: supabase.currentUserId ?? '',
        );
      }

      if (!success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment initiation failed. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Persist selected tier so caps/dashboard update immediately in-app.
      final selectedTier = _tierFromPlanType(planType);
      final selectedRole = _roleFromPlanType(planType);
      await supabase.updateCurrentUserTier(
        selectedTier,
        role: selectedRole,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppConstants.enableFreeBetaPlanActivation
                  ? '✓ Beta activation: ${Plan.getPlanByType(planType)?.name} enabled (no charge)'
                  : '✓ Plan activated: ${Plan.getPlanByType(planType)?.name} (tier updated)',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            widget.onPlanSelected();
            Navigator.pop(context);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _selectedPlan = null;
        });
      }
    }
  }

  Widget _buildPlanCard(Plan plan) {
    final isSelected = _selectedPlan == plan.type;
    final isProcessing = _isProcessing && isSelected;

    return Card(
      elevation: isSelected ? 8 : 2,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Plan name
              Text(
                plan.name,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                plan.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
              const SizedBox(height: 12),

              // Pricing
              if (plan.getPrice(_selectedPeriod) > 0)
                Text(
                  _selectedPeriod == BillingPeriod.lifetime
                      ? '\$${plan.getPrice(_selectedPeriod).toStringAsFixed(0)} lifetime'
                      : '\$${plan.getPrice(_selectedPeriod).toStringAsFixed(0)}/month',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              const SizedBox(height: 12),

              // Features list
              ...plan.features.map((feature) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),

              const SizedBox(height: 12),

              // Select button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing && !isSelected
                      ? null
                      : () => _selectPlan(plan.type),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isSelected
                        ? AppTheme.primaryColor
                        : Colors.grey[300],
                  ),
                  child: isProcessing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          isSelected ? 'Selected' : 'Choose Plan',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plans = Plan.getAllPlans();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Your Plan'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text(
              'Choose the perfect plan for your needs',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Switch or upgrade anytime. No long-term contracts.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 24),

            // Billing period toggle
            Center(
              child: SegmentedButton<BillingPeriod>(
                segments: const <ButtonSegment<BillingPeriod>>[
                  ButtonSegment<BillingPeriod>(
                    value: BillingPeriod.monthly,
                    label: Text('Monthly'),
                  ),
                  ButtonSegment<BillingPeriod>(
                    value: BillingPeriod.lifetime,
                    label: Text('Lifetime'),
                  ),
                ],
                selected: <BillingPeriod>{_selectedPeriod},
                onSelectionChanged: _isProcessing
                    ? null
                    : (newSelection) {
                        setState(() {
                          _selectedPeriod = newSelection.first;
                        });
                      },
              ),
            ),
            const SizedBox(height: 24),

            // Plans grid
            ...plans.map((plan) {
              // Only show plans that have a price for the selected billing period.
              if (plan.getPrice(_selectedPeriod) <= 0) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildPlanCard(plan),
              );
            }).toList(),

            // Footer message
            Container(
              margin: const EdgeInsets.only(top: 24),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Text(
                'All plans include email support. Corporate plans include a dedicated account manager.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
