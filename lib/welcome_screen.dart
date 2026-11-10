import 'package:flutter/material.dart';

import 'widgets.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onStart;
  const WelcomeScreen({super.key, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(),
                const AppLogo(size: 110),
                const SizedBox(height: 22),
                const Text(
                  'Vexo',
                  style: TextStyle(fontSize: 42, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Chat. Connect. Share.',
                  style: TextStyle(fontSize: 16, color: Colors.white70),
                ),
                const SizedBox(height: 44),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.chat_bubble_rounded, size: 110, color: const Color(0xFF3B82F6).withValues(alpha: 0.9)),
                    Transform.translate(
                      offset: const Offset(70, 30),
                      child: Icon(Icons.chat_bubble_rounded, size: 80, color: Colors.white.withValues(alpha: 0.35)),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F7BFF),
                      shape: const StadiumBorder(),
                    ),
                    child: const Text('Get Started  →', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onStart,
                  child: const Text('Sign In', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
