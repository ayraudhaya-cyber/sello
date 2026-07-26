import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/services/session/session_provider.dart';

/// Bridges Riverpod auth changes into GoRouter refresh.
class RouterRefresh extends ChangeNotifier {
  RouterRefresh(this.ref) {
    _subscription = ref.listen<AuthSessionState>(
      authSessionProvider,
      (_, _) => notifyListeners(),
    );
  }

  final Ref ref;
  late final ProviderSubscription<AuthSessionState> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}
