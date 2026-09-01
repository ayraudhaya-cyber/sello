import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/services/session/session_provider.dart';

class DevAccount {
  const DevAccount({
    required this.id,
    required this.label,
    required this.email,
    required this.password,
  });

  final String id;
  final String label;
  final String email;
  final String password;
}

class DevExperienceConfig {
  const DevExperienceConfig({
    required this.accounts,
    required this.defaultAccountId,
    required this.initialAutoLogin,
  });

  final List<DevAccount> accounts;
  final String? defaultAccountId;
  final bool initialAutoLogin;

  DevAccount? accountById(String? id) {
    if (id == null) return null;
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  static DevExperienceConfig fromEnv() {
    if (kReleaseMode) {
      return const DevExperienceConfig(
        accounts: [],
        defaultAccountId: null,
        initialAutoLogin: false,
      );
    }

    const definitions = [
      ('owner', 'Owner', 'DX_OWNER_EMAIL', 'DX_OWNER_PASSWORD'),
      ('manager', 'Manager', 'DX_MANAGER_EMAIL', 'DX_MANAGER_PASSWORD'),
      (
        'sales_representative',
        'Sales Representative',
        'DX_SALES_EMAIL',
        'DX_SALES_PASSWORD',
      ),
    ];

    final accounts = <DevAccount>[];
    for (final definition in definitions) {
      final email = _maybeEnv(definition.$3);
      final password = _maybeEnv(definition.$4);
      if (email.isEmpty || password.isEmpty) continue;
      accounts.add(
        DevAccount(
          id: definition.$1,
          label: definition.$2,
          email: email,
          password: password,
        ),
      );
    }

    final configuredDefault = _maybeEnv('DX_DEFAULT_USER');
    final hasAutoLogin = _envBool('DX_AUTO_LOGIN', fallback: false);
    final defaultAccountId = accounts.any((a) => a.id == configuredDefault)
        ? configuredDefault
        : accounts.isNotEmpty
            ? accounts.first.id
            : null;

    return DevExperienceConfig(
      accounts: accounts,
      defaultAccountId: defaultAccountId,
      initialAutoLogin: hasAutoLogin,
    );
  }

  static bool _envBool(String key, {required bool fallback}) {
    final value = _maybeEnv(key).toLowerCase();
    if (value.isEmpty) return fallback;
    return value == '1' || value == 'true' || value == 'yes' || value == 'on';
  }

  static String _maybeEnv(String key) {
    if (kReleaseMode) return '';
    return switch (key) {
      'DX_OWNER_EMAIL' => const String.fromEnvironment('DX_OWNER_EMAIL'),
      'DX_OWNER_PASSWORD' => const String.fromEnvironment('DX_OWNER_PASSWORD'),
      'DX_MANAGER_EMAIL' => const String.fromEnvironment('DX_MANAGER_EMAIL'),
      'DX_MANAGER_PASSWORD' =>
        const String.fromEnvironment('DX_MANAGER_PASSWORD'),
      'DX_SALES_EMAIL' => const String.fromEnvironment('DX_SALES_EMAIL'),
      'DX_SALES_PASSWORD' => const String.fromEnvironment('DX_SALES_PASSWORD'),
      'DX_DEFAULT_USER' => const String.fromEnvironment('DX_DEFAULT_USER'),
      'DX_AUTO_LOGIN' => const String.fromEnvironment('DX_AUTO_LOGIN'),
      _ => '',
    }.trim();
  }
}

class DevExperienceState {
  const DevExperienceState({
    required this.config,
    required this.selectedAccountId,
    required this.autoLoginEnabled,
    this.isBusy = false,
    this.lastMessage,
  });

  final DevExperienceConfig config;
  final String? selectedAccountId;
  final bool autoLoginEnabled;
  final bool isBusy;
  final String? lastMessage;

  List<DevAccount> get accounts => config.accounts;

  DevAccount? get selectedAccount => config.accountById(selectedAccountId);

  bool get hasAccounts => accounts.isNotEmpty;

  DevExperienceState copyWith({
    String? selectedAccountId,
    bool? autoLoginEnabled,
    bool? isBusy,
    String? lastMessage,
    bool clearMessage = false,
  }) {
    return DevExperienceState(
      config: config,
      selectedAccountId: selectedAccountId ?? this.selectedAccountId,
      autoLoginEnabled: autoLoginEnabled ?? this.autoLoginEnabled,
      isBusy: isBusy ?? this.isBusy,
      lastMessage: clearMessage ? null : (lastMessage ?? this.lastMessage),
    );
  }
}

final devExperienceProvider =
    NotifierProvider<DevExperienceNotifier, DevExperienceState>(
  DevExperienceNotifier.new,
);

class DevExperienceNotifier extends Notifier<DevExperienceState> {
  bool _autoLoginAttempted = false;
  bool _autoLoginSuspended = false;

  @override
  DevExperienceState build() {
    final config = DevExperienceConfig.fromEnv();
    return DevExperienceState(
      config: config,
      selectedAccountId: config.defaultAccountId,
      autoLoginEnabled: config.initialAutoLogin,
    );
  }

  void setAutoLoginEnabled(bool value) {
    _autoLoginAttempted = false;
    _autoLoginSuspended = !value;
    state = state.copyWith(
      autoLoginEnabled: value,
      lastMessage: value
          ? 'Auto Login enabled for this run.'
          : 'Auto Login disabled for this run.',
    );
    if (value) {
      Future.microtask(() => maybeAutoLogin(ref.read(authSessionProvider)));
    }
  }

  void selectAccount(String accountId) {
    _autoLoginAttempted = false;
    state = state.copyWith(
      selectedAccountId: accountId,
      lastMessage: 'Selected ${state.config.accountById(accountId)?.label ?? accountId}.',
    );
  }

  Future<void> maybeAutoLogin(AuthSessionState auth) async {
    if (_autoLoginAttempted ||
        _autoLoginSuspended ||
        !state.autoLoginEnabled ||
        !state.hasAccounts ||
        auth.isBootstrapping ||
        auth.isAuthenticating ||
        auth.isAuthenticated ||
        auth.awaitingEmailConfirmation ||
        auth.isPasswordRecovery) {
      return;
    }

    final account = state.selectedAccount;
    if (account == null) return;

    _autoLoginAttempted = true;
    await _signInWithAccount(
      account,
      message: 'Auto-login as ${account.label}',
    );
  }

  Future<void> signInAs(String accountId) async {
    final account = state.config.accountById(accountId);
    if (account == null) return;
    _autoLoginSuspended = true;
    _autoLoginAttempted = true;
    state = state.copyWith(selectedAccountId: accountId);
    await _signInWithAccount(
      account,
      message: 'Signed in as ${account.label}.',
    );
  }

  Future<void> logout() async {
    _autoLoginSuspended = true;
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      await ref.read(authSessionProvider.notifier).signOut();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Signed out.',
      );
    } catch (_) {
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Sign out failed.',
      );
    }
  }

  Future<void> reloadSession() async {
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      await ref.read(authSessionProvider.notifier).reloadSession();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Session reloaded from the current auth user.',
      );
    } catch (_) {
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Session reload failed.',
      );
    }
  }

  Future<void> clearLocalCache() async {
    state = state.copyWith(isBusy: true, clearMessage: true);
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Flutter image cache cleared.',
      );
    } catch (_) {
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Unable to clear the local image cache.',
      );
    }
  }

  Future<void> _signInWithAccount(
    DevAccount account, {
    required String message,
  }) async {
    state = state.copyWith(isBusy: true, clearMessage: true);
    final authNotifier = ref.read(authSessionProvider.notifier);
    final authState = ref.read(authSessionProvider);

    try {
      if (authState.isAuthenticated || authState.isAuthenticating) {
        await authNotifier.signOut();
      }
      await authNotifier.signIn(
        email: account.email,
        password: account.password,
      );
      final latest = ref.read(authSessionProvider);
      state = state.copyWith(
        isBusy: false,
        lastMessage: latest.errorMessage ?? message,
      );
    } catch (_) {
      state = state.copyWith(
        isBusy: false,
        lastMessage: 'Unable to sign in as ${account.label}.',
      );
    }
  }
}
