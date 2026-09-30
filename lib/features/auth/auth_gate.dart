import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/models/app_user.dart';
import '../../core/models/marketplace_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/cloudinary_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/marketplace_service.dart';
import '../../core/services/push_notifications.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/geo.dart';
import '../customer/customer_marketplace_screen.dart';
import '../location/base_location_field.dart';
import '../notifications/notification_host.dart';
import '../profile/edit_profile_screen.dart';
import '../provider/provider_home_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  final MarketplaceRepository _marketplace = FirestoreMarketplaceRepository();
  final ImageUploader _imageUploader = CloudinaryService();
  late final PushNotifications _push = FirebasePushNotifications();

  /// Removes this device's push token while still signed in (the rules need
  /// the user), then signs out.
  Future<void> _signOut(String uid) async {
    await _push.unregisterDevice(uid);
    await _authService.signOut();
  }

  late final Stream<User?> _authStateChanges = _authService.authStateChanges();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AuthStatusScreen(
            title: 'Authentication unavailable',
            message:
                'We could not check your sign-in status. Please try again.',
            actionLabel: 'Sign out',
            onAction: _authService.signOut,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final user = snapshot.data;
        if (user == null) {
          return LoginScreen(authService: _authService);
        }

        return StreamBuilder<AppUser?>(
          stream: _authService.userProfileChanges(user.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.hasError) {
              return _AuthStatusScreen(
                title: 'Profile unavailable',
                message: 'We could not load your account profile.',
                actionLabel: 'Sign out',
                onAction: _authService.signOut,
              );
            }
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }

            final profile = profileSnapshot.data;
            if (profile == null) {
              // Sign-up failed after the login was created. Rebuild the
              // profile; the stream above then shows the normal home.
              return _ProfileRecovery(
                user: user,
                authService: _authService,
                onSignOut: _authService.signOut,
              );
            }

            Future<void> saveProfile({
              required String name,
              String? phone,
              String? photoUrl,
            }) => _authService.updateProfile(
              uid: profile.id,
              name: name,
              phone: phone,
              photoUrl: photoUrl,
              isProvider: profile.role == UserRole.provider,
            );

            final account = AccountControls(
              emailVerified: _authService.isEmailVerified,
              sendVerificationEmail: _authService.sendEmailVerification,
              deleteAccount: (password) => _authService.deleteAccount(
                profile: profile,
                password: password,
                // Still signed in here, so the rules allow removing it.
                beforeDelete: () => _push.unregisterDevice(profile.id),
              ),
            );

            final home = switch (profile.role) {
              UserRole.customer => CustomerMarketplaceScreen(
                customerUid: profile.id,
                customerName: profile.name,
                repository: _marketplace,
                onSignOut: () => _signOut(profile.id),
                profile: profile,
                imageUploader: _imageUploader,
                push: _push,
                onSaveProfile: saveProfile,
                account: account,
              ),
              UserRole.provider => ProviderHomeScreen(
                providerUid: profile.id,
                providerName: profile.name,
                repository: _marketplace,
                onSignOut: () => _signOut(profile.id),
                push: _push,
                profile: profile,
                imageUploader: _imageUploader,
                onSaveProfile: saveProfile,
                account: account,
              ),
            };
            return NotificationHost(
              // A new user gets a fresh host (and token registration).
              key: ValueKey(profile.id),
              push: _push,
              repository: _marketplace,
              uid: profile.id,
              name: profile.name,
              role: profile.role,
              child: home,
            );
          },
        );
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.authService,
    this.location = const GeolocatorLocationService(),
  });

  final AuthService? authService;

  /// Device location, for a provider's optional base location at sign-up.
  final LocationService location;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serviceAreaController = TextEditingController();
  final _startingPriceController = TextEditingController();
  bool _isRegistering = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  UserRole _role = UserRole.customer;
  String _serviceCategory = serviceCategories.first;
  LatLngPoint? _baseLocation;
  double _serviceRadiusKm = defaultServiceRadiusKm;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _serviceAreaController.dispose();
    _startingPriceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final auth = widget.authService ?? AuthService();
      if (_isRegistering) {
        await auth.registerWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim(),
          role: _role,
          serviceCategory: _role == UserRole.provider ? _serviceCategory : null,
          serviceArea: _role == UserRole.provider
              ? _serviceAreaController.text.trim()
              : null,
          startingPrice: _role == UserRole.provider
              ? int.tryParse(_startingPriceController.text.trim())
              : null,
          baseLocation: _role == UserRole.provider ? _baseLocation : null,
          serviceRadiusKm: _serviceRadiusKm,
        );
        // Best effort: the account works either way; the profile screen
        // offers to resend.
        try {
          await auth.sendEmailVerification();
        } catch (_) {}
      } else {
        await auth.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      debugPrint('Firebase authentication failed (${error.code}).');
      if (mounted) {
        setState(() => _errorMessage = _authErrorMessage(error.code));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Unable to complete sign-in. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.handyman_rounded,
                      size: 40,
                      color: AppTheme.ink,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'FixNear',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegistering
                          ? 'Create your FixNear account'
                          : 'Find help nearby. Book with confidence.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppTheme.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (_isRegistering) ...[
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter your name'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<UserRole>(
                        initialValue: _role,
                        isExpanded: true,
                        elevation: 0,
                        dropdownColor: AppTheme.tint,
                        borderRadius: BorderRadius.circular(12),
                        decoration: const InputDecoration(
                          labelText: 'Account type',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: UserRole.customer,
                            child: Text('Customer'),
                          ),
                          DropdownMenuItem(
                            value: UserRole.provider,
                            child: Text('Service provider'),
                          ),
                        ],
                        onChanged: (role) {
                          if (role != null) setState(() => _role = role);
                        },
                      ),
                      const SizedBox(height: 14),
                      if (_role == UserRole.provider) ...[
                        DropdownButtonFormField<String>(
                          initialValue: _serviceCategory,
                          isExpanded: true,
                          elevation: 0,
                          dropdownColor: AppTheme.tint,
                          borderRadius: BorderRadius.circular(12),
                          decoration: const InputDecoration(
                            labelText: 'Main service',
                          ),
                          items: serviceCategories
                              .map(
                                (category) => DropdownMenuItem(
                                  value: category,
                                  child: Text(category),
                                ),
                              )
                              .toList(),
                          onChanged: (category) {
                            if (category != null) {
                              setState(() => _serviceCategory = category);
                            }
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _serviceAreaController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Service area',
                            hintText: 'City or neighborhood',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter your service area'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _startingPriceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Starting price (PHP)',
                          ),
                          validator: (value) {
                            final price = int.tryParse(value?.trim() ?? '');
                            return price == null || price < 0
                                ? 'Enter a valid starting price'
                                : null;
                          },
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Where you start from (optional)',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Nearby jobs show first and you get notified about '
                          'jobs within your radius. You can change this later '
                          'on the Service tab.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        BaseLocationField(
                          base: _baseLocation,
                          radiusKm: _serviceRadiusKm,
                          location: widget.location,
                          enabled: !_isSubmitting,
                          onBaseChanged: (point) =>
                              setState(() => _baseLocation = point),
                          onRadiusChanged: (km) =>
                              setState(() => _serviceRadiusKm = km),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return email.contains('@')
                            ? null
                            : 'Enter a valid email';
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Show password'
                              : 'Hide password',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => (value?.length ?? 0) >= 6
                          ? null
                          : 'Password must be at least 6 characters',
                    ),
                    if (!_isRegistering)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isSubmitting ? null : _forgotPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isRegistering ? 'Create account' : 'Sign in'),
                    ),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => setState(() {
                              _isRegistering = !_isRegistering;
                              _errorMessage = null;
                            }),
                      child: Text(
                        _isRegistering
                            ? 'Already have an account? Sign in'
                            : 'Create an account',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (context) =>
          _ForgotPasswordDialog(initialEmail: _emailController.text.trim()),
    );
    if (email == null || !mounted) return;
    final auth = widget.authService ?? AuthService();
    try {
      await auth.sendPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'If an account exists for $email, a reset link is on its way.',
          ),
        ),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_authErrorMessage(error.code))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send the reset link. Try again.'),
        ),
      );
    }
  }

  String _authErrorMessage(String code) {
    return switch (code) {
      'invalid-email' => 'Enter a valid email address.',
      'email-already-in-use' => 'An account already exists for this email.',
      'weak-password' => 'Choose a stronger password.',
      'operation-not-allowed' => 'Email and password sign-up is disabled. Enable Email/Password in Firebase Console under Authentication > Sign-in method.',
      'too-many-requests' => 'Too many attempts. Wait a moment and try again.',
      'invalid-api-key' => 'Firebase rejected this app configuration. Check the Firebase API key and app settings.',
      'configuration-not-found' =>
        'Firebase Authentication is not configured for this project.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' => 'Email or password is incorrect.',
      'network-request-failed' =>
        'Check your internet connection and try again.',
      _ => 'Authentication failed. Please try again.',
    };
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});

  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controller = TextEditingController(text: widget.initialEmail);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset your password'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('We will email you a link to choose a new password.'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) => (value?.trim() ?? '').contains('@')
                  ? null
                  : 'Enter a valid email',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, _controller.text.trim());
            }
          },
          child: const Text('Send link'),
        ),
      ],
    );
  }
}

/// Shown while repairing an account that has a login but no profile.
class _ProfileRecovery extends StatefulWidget {
  const _ProfileRecovery({
    required this.user,
    required this.authService,
    required this.onSignOut,
  });

  final User user;
  final AuthService authService;
  final Future<void> Function() onSignOut;

  @override
  State<_ProfileRecovery> createState() => _ProfileRecoveryState();
}

class _ProfileRecoveryState extends State<_ProfileRecovery> {
  late Future<AppUser> _recovery = _recover();

  Future<AppUser> _recover() =>
      widget.authService.ensureUserProfileExists(widget.user);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser>(
      future: _recovery,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _AuthStatusScreen(
            title: 'Could not finish setting up your account',
            message: 'Check your connection and try again.',
            actionLabel: 'Try again',
            onAction: () async => setState(() => _recovery = _recover()),
            secondaryLabel: 'Sign out',
            onSecondary: widget.onSignOut,
          );
        }
        // On success the profile stream replaces this screen.
        return const _LoadingScreen();
      },
    );
  }
}

class _AuthStatusScreen extends StatelessWidget {
  const _AuthStatusScreen({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String message;
  final String actionLabel;
  final Future<void> Function() onAction;
  final String? secondaryLabel;
  final Future<void> Function()? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
              if (secondaryLabel != null && onSecondary != null)
                TextButton(
                  onPressed: onSecondary,
                  child: Text(secondaryLabel!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
