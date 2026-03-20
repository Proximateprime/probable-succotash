import '../models/plan_model.dart';

class TierUtils {
  /// Get max maps allowed for a given plan type
  static int getMaxMapsForPlan(PlanType planType) {
    final plan = Plan.getPlanByType(planType);
    return plan?.maxMaps ?? 0;
  }

  /// Get max users allowed for a given plan type
  static int getMaxUsersForPlan(PlanType planType) {
    final plan = Plan.getPlanByType(planType);
    return plan?.maxUsers ?? 1;
  }

  /// Check if user can add a new map based on their tier
  static bool canAddMap(PlanType planType, int currentMapCount) {
    final maxMaps = getMaxMapsForPlan(planType);
    return currentMapCount < maxMaps;
  }

  /// Get upgrade message based on current tier and what they need
  static String getUpgradeMessage(PlanType currentTier, int currentMapCount) {
    final plan = Plan.getPlanByType(currentTier);
    if (plan == null) return 'Please select a plan.';

    if (currentMapCount >= plan.maxMaps) {
      if (currentTier == PlanType.hobbyist) {
        return 'Hobbyist limit: 1 map. Upgrade to Solo Professional (\$19/mo) for unlimited maps.';
      } else if (currentTier == PlanType.largeIndividual) {
        return 'Large Land tier: 1 map maximum. For unlimited maps, upgrade to Solo Professional or Premium Solo.';
      } else if (currentTier == PlanType.soloProfessional) {
        return 'Already on unlimited tier! You should not see this message.';
      } else if (currentTier == PlanType.premiumSolo) {
        return 'Already on unlimited tier! You should not see this message.';
      }
    }

    return 'Please upgrade your plan to add more maps.';
  }

  /// Get plan description with pricing
  static String getPlanDescription(PlanType planType, {bool withPrice = true}) {
    final plan = Plan.getPlanByType(planType);
    if (plan == null) return 'Unknown Plan';

    String desc = plan.name;
    if (withPrice) {
      final lifetimePrice = plan.getPrice(BillingPeriod.lifetime);
      final monthlyPrice = plan.getPrice(BillingPeriod.monthly);

      if (lifetimePrice > 0 && monthlyPrice > 0) {
        desc += ' (\$$monthlyPrice/mo or \$$lifetimePrice lifetime)';
      } else if (lifetimePrice > 0) {
        desc += ' (\$$lifetimePrice lifetime)';
      } else if (monthlyPrice > 0) {
        desc += ' (\$$monthlyPrice/mo)';
      }
    }

    return desc;
  }
}
