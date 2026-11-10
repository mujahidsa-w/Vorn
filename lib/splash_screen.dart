import 'package:flutter/material.dart';

import 'widgets.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppLogo(size: 120),
                const SizedBox(height: 28),
                const Text(
                  'Vexo',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                const SizedBox(height: 44),
                SizedBox(
                  width: 220,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _controller.value,
                        minHeight: 6,
                        backgroundColor: Colors.white12,
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Loading...', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
