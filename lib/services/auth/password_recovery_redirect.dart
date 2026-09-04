/// Detects Supabase password-recovery / invite redirects from the browser URL.
///
/// Recovery links may carry `type=recovery` in the query string (implicit flow)
/// or in the hash fragment. PKCE redirects often only include `code=` — those
/// are identified via [AuthChangeEvent.passwordRecovery], not this helper.
abstract final class PasswordRecoveryRedirect {
  static bool isIndicatedBy(Uri uri) {
    if (uri.queryParameters['type'] == 'recovery') return true;

    final fragment = uri.fragment;
    if (fragment.isEmpty || !fragment.contains('=')) return false;

    final params = Uri.splitQueryString(fragment);
    return params['type'] == 'recovery';
  }
}
