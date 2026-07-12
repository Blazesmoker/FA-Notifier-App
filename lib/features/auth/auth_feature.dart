import 'package:FANotifier/features/auth/data/cloudflare_check_gateway_impl.dart';
import 'package:FANotifier/features/auth/data/startup_cloudflare_check_service.dart';
import 'package:FANotifier/features/auth/domain/cloudflare_check_gateway.dart';
import 'package:FANotifier/features/auth/domain/startup_cloudflare_checker.dart';

class AuthFeature {
  const AuthFeature._();

  static StartupCloudflareChecker createStartupCloudflareChecker() {
    return const StartupCloudflareCheckService();
  }

  static CloudflareCheckGateway createCloudflareCheckGateway() {
    return const CloudflareCheckGatewayImpl();
  }
}
