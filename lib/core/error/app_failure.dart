/// Shared failure type for future data/application layers.
sealed class AppFailure {
  const AppFailure(this.message);
  final String message;
}

final class NetworkFailure extends AppFailure {
  const NetworkFailure([super.message = 'Network error. Please try again.']);
}

final class AuthFailure extends AppFailure {
  const AuthFailure([super.message = 'Authentication failed.']);
}

final class UnexpectedFailure extends AppFailure {
  const UnexpectedFailure([super.message = 'Something went wrong.']);
}
