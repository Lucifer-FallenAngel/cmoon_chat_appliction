import 'package:flutter/material.dart';
import 'get_started.dart';

class FirstScreen extends StatefulWidget {
  const FirstScreen({super.key});

  @override
  State<FirstScreen> createState() => _FirstScreenState();
}

class _FirstScreenState extends State<FirstScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToGetStarted();
  }

  void _navigateToGetStarted() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const GetStarted()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF6),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Spacer(flex: 3),

            // Center chat logo
            Center(
              child: Image.asset('images/first/chat_logo.png', height: 120),
            ),

            const SizedBox(height: 20),

            const Text(
              'Chat Us',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4CAF50),
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Flutter Developer Task',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),

            const Spacer(flex: 4),

            const Text(
              'POWERED BY',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black45,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.only(right: 40),
              child: Image.asset('images/first/Cmoonlogo.png', height: 60),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
