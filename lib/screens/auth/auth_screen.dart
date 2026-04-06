import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/supabase_config.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _stayLoggedIn = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStayLoggedInPreference();
  }

  Future<void> _loadStayLoggedInPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final v = prefs.getBool('stayLoggedIn') ?? true;
    // Undgå unødvendig setState (genskaber widget-træet og kan slå tastatur/fokus fra under indtastning).
    if (v != _stayLoggedIn) {
      setState(() => _stayLoggedIn = v);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      if (_isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Tjek din email for at bekræfte kontoen')),
          );
        }
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('stayLoggedIn', _stayLoggedIn);
        if (mounted) setState(() => _isLoading = false);
      }
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorMessage = 'Indtast din email');
      return;
    }
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: SupabaseConfig.authEmailRedirectTo,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tjek din email for nulstilling')),
        );
      }
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
      });
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600;
    final bgAsset =
        isTablet ? 'assets/loginipad.svg' : 'assets/loginiphone.svg';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: SvgPicture.asset(
                bgAsset,
                fit: BoxFit.cover,
                allowDrawingOutsideViewBox: true,
                errorBuilder: (context, error, stackTrace) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFF5A1A0D),
                        Color(0xFFE85A4A),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Fylder hele området så hit-testing ikke falder igennem til underliggende lag.
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                // Design-størrelse tilpasset iPad vs iPhone
                final designWidth = isTablet ? 450.0 : 360.0;
                final textSize = isTablet ? 16.0 : 14.0;
                final smallTextSize = isTablet ? 14.0 : 13.0;
                final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
                final keyboardOpen = bottomInset > 0;
                // Scaffold med resizeToAvoidBottomInset giver allerede mindre højde — træk
                // ikke bottomInset fra igen (det pressede formularen væk véd tastaturet).
                final availableH = constraints.maxHeight;
                final topSpacing = isTablet
                    ? (keyboardOpen ? 56.0 : 280.0)
                    : keyboardOpen
                        ? 8.0
                        : (availableH < 560
                            ? (availableH * 0.1).clamp(32.0, 100.0)
                            : (availableH < 680 ? 140.0 : 200.0));
                return Align(
                  alignment:
                      keyboardOpen ? Alignment.topCenter : Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      clipBehavior: Clip.none,
                      child: SizedBox(
                        width: designWidth,
                        child: Form(
                          key: _formKey,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: isTablet ? 48 : 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(height: topSpacing),
                      if (_errorMessage != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Color(0xFFD4A853),
                                width: 1),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      // Email-felt
                      SizedBox(
                        width: designWidth * 0.65,
                        child: TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        scrollPadding: const EdgeInsets.fromLTRB(0, 80, 0, 140),
                        onFieldSubmitted: (_) => FocusScope.of(context)
                            .requestFocus(_passwordFocus),
                        style: const TextStyle(color: Color(0xFFE8DCC8)),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: const TextStyle(color: Color(0xFFB8A88A)),
                          hintText: 'Indtast din email',
                          hintStyle: TextStyle(color: Color(0xFFB8A88A)
                              .withValues(alpha: 0.6)),
                          filled: true,
                          fillColor: const Color(0xFF4A4035),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFF8B7355), width: 1),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFF8B7355), width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFFD4A853), width: 1),
                          ),
                        ),
                      ),
                    ),
                      const SizedBox(height: 12),
                      // Adgangskode-felt
                      SizedBox(
                        width: designWidth * 0.65,
                        child: TextFormField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        scrollPadding: const EdgeInsets.fromLTRB(0, 80, 0, 140),
                        onFieldSubmitted: (_) {
                          if (!_isLoading) _submit();
                        },
                        style: const TextStyle(color: Color(0xFFE8DCC8)),
                        decoration: InputDecoration(
                          labelText: 'Adgangskode',
                          labelStyle: const TextStyle(color: Color(0xFFB8A88A)),
                          hintText: 'Indtast din adgangskode',
                          hintStyle: TextStyle(color: Color(0xFFB8A88A)
                              .withValues(alpha: 0.6)                          ),
                          filled: true,
                          fillColor: const Color(0xFF4A4035),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFF8B7355), width: 1),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFF8B7355), width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: Color(0xFFD4A853), width: 1),
                          ),
                        ),
                      ),
                    ),
                      const SizedBox(height: 16),
                      // Forbliv logget ind
                      if (!_isSignUp)
                        SizedBox(
                          width: designWidth * 0.65,
                          child: CheckboxListTile(
                            value: _stayLoggedIn,
                            onChanged: _isLoading
                                ? null
                                : (v) => setState(() => _stayLoggedIn = v ?? true),
                            title: Text(
                              'Forbliv logget ind',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: textSize,
                              ),
                            ),
                            activeColor: const Color(0xFFD4A853),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      const SizedBox(height: 16),
                      // Log ind-knap
                      SizedBox(
                        width: designWidth * 0.65,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B7355),
                            foregroundColor: const Color(0xFFE8DCC8),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFFE8DCC8),
                                  ),
                                )
                              : Text(
                                  _isSignUp ? 'Opret konto' : 'Log ind',
                                  style: TextStyle(fontSize: textSize),
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() => _isSignUp = !_isSignUp),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          _isSignUp
                              ? 'Har du allerede en konto? Log ind'
                              : 'Har du ikke en konto? Opret',
                          style: TextStyle(fontSize: textSize),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if (!_isSignUp)
                        TextButton(
                          onPressed: _isLoading ? null : _resetPassword,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            'Glemt adgangskode?',
                            style: TextStyle(fontSize: smallTextSize),
                          ),
                        ),
                      SizedBox(height: keyboardOpen ? 40 : 12),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
