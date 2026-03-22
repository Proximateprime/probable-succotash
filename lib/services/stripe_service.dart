import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/plan_model.dart';

class StripePaymentService {
  final Logger _logger = Logger();

  /// Calls the Supabase Edge Function to create a Stripe Checkout Session and
  /// opens the resulting URL in the device browser.
  ///
  /// Returns true if the URL was launched successfully.
  /// In beta mode (enableFreeBetaPlanActivation = true) this is bypassed.
  Future<bool> initiateCheckout({
    required PlanType planType,
    required BillingPeriod billingPeriod,
    required String userEmail,
    required String userId,
  }) async {
    final plan = Plan.getPlanByType(planType);
    if (plan == null) {
      _logger.e('Invalid plan type: $planType');
      return false;
    }

    final price = plan.getPrice(billingPeriod);
    if (price <= 0) {
      _logger.e('Invalid price for plan: $planType, period: $billingPeriod');
      return false;
    }

    _logger.i(
      'Initiating Stripe checkout: ${plan.name} - \$$price ($billingPeriod)',
    );

    try {
      final client = Supabase.instance.client;

      final response = await client.functions.invoke(
        'create-checkout-session',
        body: {
          'tier': _tierFromPlanType(planType),
          'billing_period': billingPeriod == BillingPeriod.monthly
              ? 'monthly'
              : 'lifetime',
          'user_email': userEmail,
          'user_id': userId,
        },
      );

      if (response.status != 200) {
        final errorData = response.data;
        final errorMsg = errorData is Map ? errorData['error'] : '$errorData';
        _logger.e('Checkout session creation failed: $errorMsg');
        return false;
      }

      final data = response.data as Map<String, dynamic>;
      final url = data['url'] as String?;

      if (url == null || url.isEmpty) {
        _logger.e('No checkout URL returned from Edge Function');
        return false;
      }

      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _logger.e('Could not launch Stripe checkout URL: $url');
        return false;
      }

      _logger.i('Stripe checkout opened in browser');
      return true;
    } catch (e) {
      _logger.e('Stripe checkout error: $e');
      return false;
    }
  }

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
}
