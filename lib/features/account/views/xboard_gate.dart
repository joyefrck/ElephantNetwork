import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/account/account.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_entry_shell.dart';

class XboardGate extends ConsumerWidget {
  const XboardGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(xboardSessionControllerProvider);
    return switch (state.status) {
      XboardSessionStatus.authenticated => child,
      XboardSessionStatus.unauthenticated ||
      XboardSessionStatus.authenticating ||
      XboardSessionStatus.unavailable ||
      XboardSessionStatus.loading => const XboardLoginView(),
    };
  }
}

class XboardLoginView extends ConsumerStatefulWidget {
  const XboardLoginView({super.key});

  @override
  ConsumerState<XboardLoginView> createState() => _XboardLoginViewState();
}

class _XboardLoginViewState extends ConsumerState<XboardLoginView> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final authenticated = await ref
        .read(xboardSessionControllerProvider.notifier)
        .login(_emailController.text, _passwordController.text);
    if (authenticated) {
      try {
        await globalState.startAuthenticatedRuntime();
      } catch (_) {
        await ref.read(xboardSessionControllerProvider.notifier).logout();
        if (mounted) {
          context.showNotifier(context.appLocalizations.serviceUnavailable);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final state = ref.watch(xboardSessionControllerProvider);
    final busy = state.status == XboardSessionStatus.authenticating;
    final restoring = state.status == XboardSessionStatus.loading;
    final errorText = _errorText(context, state.error);
    return XboardEntryShell(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.fromLTRB(32, 30, 32, 32),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE1E9E4)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x17203F30),
                      blurRadius: 42,
                      offset: Offset(0, 18),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          child: Image.asset(
                            'assets/images/icon.png',
                            width: 84,
                            height: 84,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          appName,
                          textAlign: TextAlign.center,
                          style: context.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.signInToContinue,
                          textAlign: TextAlign.center,
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 30),
                        TextFormField(
                          controller: _emailController,
                          enabled: !busy && !restoring,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: l10n.emailAddress,
                            prefixIcon: const Icon(Icons.alternate_email),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            return email.contains('@')
                                ? null
                                : l10n.emailAddress;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          enabled: !busy && !restoring,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            labelText: l10n.password,
                            prefixIcon: const Icon(Icons.lock_outline),
                          ),
                          validator: (value) {
                            return (value?.isNotEmpty ?? false)
                                ? null
                                : l10n.password;
                          },
                        ),
                        if (errorText != null) ...[
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 18,
                                color: context.colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorText,
                                  style: TextStyle(
                                    color: context.colorScheme.error,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: busy || restoring ? null : _submit,
                          child: busy || restoring
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.signIn),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _errorText(BuildContext context, Object? error) {
    if (error == null) return null;
    final l10n = context.appLocalizations;
    if (error is XboardApiException &&
        const {400, 401, 403}.contains(error.statusCode)) {
      return l10n.invalidCredentials;
    }
    return l10n.serviceUnavailable;
  }
}
