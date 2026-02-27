import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_colors.dart';
import '../components/glass_container.dart';
import 'workspace_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          // Ambient Background Light
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.appleYellow.withOpacity(0.05),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
             .blur(begin: const Offset(80, 80), end: const Offset(120, 120), duration: 4.seconds),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  // Header
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AR Studio',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                          fontSize: 42,
                          letterSpacing: -1,
                        ),
                      ).animate().fadeIn(duration: 800.ms).slideX(begin: -0.1),
                      const SizedBox(height: 8),
                      Text(
                        'FOR ARTISTS',
                        style: TextStyle(
                          color: AppColors.appleYellow.withOpacity(0.8),
                          letterSpacing: 4,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ).animate().fadeIn(delay: 400.ms),
                    ],
                  ),

                  const Spacer(),

                  // Main Action
                  Center(
                    child: GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const WorkspaceScreen()),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.appleYellow.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: AppColors.appleYellow,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.appleYellow.withOpacity(0.3),
                                      blurRadius: 30,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.add_rounded,
                                  size: 40,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ).animate(onPlay: (c) => c.repeat(reverse: true))
                           .scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05), duration: 2.seconds, curve: Curves.easeInOut),
                          const SizedBox(height: 24),
                          const Text(
                            'Enter Studio',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ).animate().fadeIn(delay: 600.ms),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Inspiration Preview
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Featured Inspiration',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ).animate().fadeIn(delay: 800.ms),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 140,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _buildInspirationCard('assets/library/anime.png'),
                            _buildInspirationCard('assets/library/architecture.png'),
                            _buildInspirationCard('assets/library/nature.png'),
                            _buildInspirationCard('assets/library/portrait.png'),
                          ],
                        ),
                      ).animate().fadeIn(delay: 1.seconds).slideY(begin: 0.1),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          
          // Settings Icon
          Positioned(
            top: 60,
            right: 30,
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white70),
              onPressed: () {},
            ).animate().fadeIn(delay: 1200.ms),
          ),
        ],
      ),
    );
  }

  Widget _buildInspirationCard(String imagePath) {
    return Container(
      width: 100,
      margin: const EdgeInsets.only(right: 16),
      child: GlassContainer(
        padding: EdgeInsets.zero,
        borderRadius: 15,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Image.asset(
            imagePath,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
