import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/features/account/account.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class XboardGate extends ConsumerWidget {
  const XboardGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(xboardSessionControllerProvider);
    return switch (state.status) {
      XboardSessionStatus.authenticated => child,
      XboardSessionStatus.unauthenticated ||
      XboardSessionStatus.authenticating => const XboardLoginView(),
      XboardSessionStatus.unavailable => const _UnavailableView(),
      XboardSessionStatus.loading => const _GateLoadingView(),
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        child: Image.asset(
                          'assets/images/icon.png',
                          width: 76,
                          height: 76,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        appName,
                        textAlign: TextAlign.center,
                        style: context.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.signInToContinue,
                        textAlign: TextAlign.center,
                        style: context.textTheme.bodyMedium?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _emailController,
                        enabled: !busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: l10n.emailAddress,
                          prefixIcon: const Icon(Icons.alternate_email),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          return email.contains('@') ? null : l10n.emailAddress;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        enabled: !busy,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: l10n.password,
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          return (value?.isNotEmpty ?? false)
                              ? null
                              : l10n.password;
                        },
                      ),
                      if (state.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          l10n.serviceUnavailable,
                          style: TextStyle(color: context.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: busy ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.signIn),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GateLoadingView extends StatelessWidget {
  const _GateLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _UnavailableView extends ConsumerWidget {
  const _UnavailableView();

  Future<void> _retry(WidgetRef ref) async {
    final authenticated = await ref
        .read(xboardSessionControllerProvider.notifier)
        .restore();
    if (authenticated) {
      try {
        await globalState.startAuthenticatedRuntime();
      } catch (_) {
        await ref.read(xboardSessionControllerProvider.notifier).logout();
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 56,
                  color: context.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 20),
                Text(
                  l10n.serviceUnavailable,
                  textAlign: TextAlign.center,
                  style: context.textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _retry(ref),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.retry),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(xboardSessionControllerProvider.notifier)
                      .logout(),
                  child: Text(l10n.useAnotherAccount),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
