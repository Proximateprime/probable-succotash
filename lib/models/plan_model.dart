enum PlanType {
  hobbyist,
  soloProfessional,
  premiumSolo,
  largeIndividual,
  corporate,
}

enum BillingPeriod { monthly, lifetime }

class Plan {
  final PlanType type;
  final String name;
  final String description;
  final Map<BillingPeriod, double> pricing;
  final int maxMaps;
  final int maxUsers;
  final List<String> features;
  final bool hasARVoiceAnalytics;

  Plan({
    required this.type,
    required this.name,
    required this.description,
    required this.pricing,
    required this.maxMaps,
    required this.maxUsers,
    required this.features,
    this.hasARVoiceAnalytics = false,
  });

  double getPrice(BillingPeriod period) => pricing[period] ?? 0;

  static List<Plan> getAllPlans() => [
        Plan(
          type: PlanType.hobbyist,
          name: 'Hobbyist',
          description: 'Perfect for trying SprayMap',
          pricing: {BillingPeriod.lifetime: 59},
          maxMaps: 1,
          maxUsers: 1,
          features: [
            '1 map lifetime',
            'Basic GPS tracking',
            'PDF proofs',
            'Email support',
          ],
        ),
        Plan(
          type: PlanType.soloProfessional,
          name: 'Solo Professional',
          description: 'For independent operators',
          pricing: {
            BillingPeriod.monthly: 19,
            BillingPeriod.lifetime: 229,
          },
          maxMaps: 999,
          maxUsers: 1,
          features: [
            'Unlimited standard maps',
            'Real-time GPS tracking',
            'Advanced PDF reports',
            'Cloud storage (1 GB)',
            'Priority email support',
          ],
        ),
        Plan(
          type: PlanType.premiumSolo,
          name: 'Premium Solo',
          description: 'With AR, voice, analytics',
          pricing: {
            BillingPeriod.monthly: 29,
            BillingPeriod.lifetime: 349,
          },
          maxMaps: 999,
          maxUsers: 1,
          features: [
            'Unlimited maps',
            'AR zone visualization',
            'Voice navigation',
            'Advanced analytics dashboard',
            'Cloud storage (5 GB)',
            'Priority support',
          ],
          hasARVoiceAnalytics: true,
        ),
        Plan(
          type: PlanType.largeIndividual,
          name: 'Large Land Individual',
          description: 'For massive properties',
          pricing: {
            BillingPeriod.monthly: 39,
            BillingPeriod.lifetime: 549,
          },
          maxMaps: 1,
          maxUsers: 1,
          features: [
            '1 very large map (up to 10,000 acres)',
            'Ultra-high resolution orthomosaics',
            'Custom boundary imports',
            'Cloud storage (20 GB)',
            'Dedicated support',
          ],
        ),
        Plan(
          type: PlanType.corporate,
          name: 'Corporate',
          description: 'For teams and fleets',
          pricing: {
            BillingPeriod.monthly: 149, // Base for up to 5 users
          },
          maxMaps: 999,
          maxUsers: 5,
          features: [
            'Unlimited maps & users',
            'Team collaboration',
            'AR + voice + analytics',
            'Custom branding',
            'API access',
            'Dedicated account manager',
            'Cloud storage (100 GB)',
          ],
          hasARVoiceAnalytics: true,
        ),
      ];

  static Plan? getPlanByType(PlanType type) {
    try {
      return getAllPlans().firstWhere((p) => p.type == type);
    } catch (e) {
      return null;
    }
  }
}
