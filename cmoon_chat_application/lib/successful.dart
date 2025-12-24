import 'dart:async';
import 'package:flutter/material.dart';
import 'login.dart';

class SuccessfulPage extends StatefulWidget {
  final bool isSuccess;

  const SuccessfulPage({super.key, required this.isSuccess});

  @override
  State<SuccessfulPage> createState() => _SuccessfulPageState();
}

class _SuccessfulPageState extends State<SuccessfulPage> {
  @override
  void initState() {
    super.initState();

    if (widget.isSuccess) {
      Timer(const Duration(seconds: 4), () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.isSuccess ? Icons.check_circle : Icons.error,
              color: widget.isSuccess ? Colors.green : Colors.red,
              size: 80,
            ),
            const SizedBox(height: 20),
            Text(
              widget.isSuccess
                  ? 'Account is successfully created'
                  : 'Failed to create the account',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            if (widget.isSuccess)
              const Text(
                'Redirecting to login...',
                style: TextStyle(color: Colors.black54),
              ),
          ],
        ),
      ),
    );
  }
}
