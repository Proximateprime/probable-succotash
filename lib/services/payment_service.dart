import 'package:logger/logger.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();

  factory PaymentService() {
    return _instance;
  }

  PaymentService._internal();

  final Logger _logger = Logger();

  void initialize(String publishableKey) {
    _logger.i('Payment service initialized with key: ${publishableKey.substring(0, 10)}...');
  }

  static const Map<String, ProductInfo> products = {
    'hobbyist': ProductInfo(
      name: 'Hobbyist',
      priceUsd: 9900,
      description: 'Lifetime access, 1 active map',
      tier: 'hobbyist',
    ),
    'individual': ProductInfo(
      name: 'Individual',
      priceUsd: 29900,
      description: 'Lifetime access, 3 active maps',
      tier: 'individual',
    ),
    'corporate_monthly': ProductInfo(
      name: 'Corporate',
      priceUsd: 14900,
      description: 'Monthly subscription, unlimited maps',
      tier: 'corporate_admin',
    ),
  };

  Future<void> createCustomer({required String email}) async {
    _logger.i('Creating customer: $email');
  }

  Future<void> createSubscription({required String customerId}) async {
    _logger.i('Creating subscription for: $customerId');
  }

  Future<void> cancelSubscription({required String subscriptionId}) async {
    _logger.i('Cancelling subscription: $subscriptionId');
  }
}

class ProductInfo {
  final String name;
  final int priceUsd;
  final String description;
  final String tier;

  const ProductInfo({
    required this.name,
    required this.priceUsd,
    required this.description,
    required this.tier,
  });

  String get displayPrice => '\$${priceUsd / 100}';
}
