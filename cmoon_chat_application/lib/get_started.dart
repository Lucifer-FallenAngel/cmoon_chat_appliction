import 'dart:async';
import 'package:flutter/material.dart';
import 'signup.dart';

class GetStarted extends StatefulWidget {
  const GetStarted({super.key});

  @override
  State<GetStarted> createState() => _GetStartedState();
}

class _GetStartedState extends State<GetStarted> {
  late PageController _pageController;
  Timer? _timer;

  int _currentPage = 1;

  final List<String> images = [
    'images/get_started/1.png',
    'images/get_started/2.png',
    'images/get_started/3.png',
    'images/get_started/4.png',
  ];

  final List<String> titles = [
    'Enjoy the Joy of Chatting with Friends',
    'Stay Connected with Friends',
    'Private and Secure Conversations',
    'Fast and Reliable Messaging',
  ];

  final List<String> subtitles = [
    'The Best Chatting App that contains whole Privacy, Protection to your Chats',
    'Chat anytime and anywhere with your loved ones',
    'Your chats are protected with full privacy',
    'Experience smooth and instant messaging',
  ];

  late List<int> pageMap;

  @override
  void initState() {
    super.initState();

    // Create fake infinite pages
    pageMap = [images.length - 1, ...List.generate(images.length, (i) => i), 0];

    _pageController = PageController(initialPage: 1);
    _startAutoSlide();
  }

  void _startAutoSlide() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_pageController.hasClients) return;

      _pageController.nextPage(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    });
  }

  void _onPageChanged(int index) {
    _currentPage = index;

    // Jump without animation for infinite effect
    if (index == 0) {
      Future.microtask(() {
        _pageController.jumpToPage(images.length);
      });
    } else if (index == images.length + 1) {
      Future.microtask(() {
        _pageController.jumpToPage(1);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF6),
      body: SafeArea(
        child: Column(
          children: [
            // 🔹 SLIDER AREA
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pageMap.length,
                onPageChanged: _onPageChanged,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  final realIndex = pageMap[index];

                  return Column(
                    children: [
                      const SizedBox(height: 40),

                      // IMAGE (TOP-HEAVY LIKE DESIGN)
                      Image.asset(
                        images[realIndex],
                        height: MediaQuery.of(context).size.height * 0.6,
                        fit: BoxFit.contain,
                      ),

                      const SizedBox(height: 30),

                      // TITLE (DYNAMIC + GREEN LAST WORDS)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            children: [
                              TextSpan(
                                text:
                                    titles[realIndex]
                                        .split(' ')
                                        .take(
                                          titles[realIndex].split(' ').length -
                                              3,
                                        )
                                        .join(' ') +
                                    ' ',
                              ),
                              TextSpan(
                                text: titles[realIndex]
                                    .split(' ')
                                    .skip(
                                      titles[realIndex].split(' ').length - 3,
                                    )
                                    .join(' '),
                                style: const TextStyle(color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // SUBTITLE
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          subtitles[realIndex],
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // 🔹 BUTTON
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SignupPage(),
                      ),
                    );
                  },
                  child: const Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
