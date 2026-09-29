import 'package:flutter/material.dart';

import 'app.dart' as app;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const app.FixNearApp());
}

class FixNearApp extends StatelessWidget {
  const FixNearApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const app.FixNearApp();
  }
}

class FixNearHomeScreen extends StatelessWidget {
  const FixNearHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = <Map<String, dynamic>>[
      {'icon': Icons.electrical_services_rounded, 'label': 'Electrical'},
      {'icon': Icons.plumbing_rounded, 'label': 'Plumbing'},
      {'icon': Icons.cleaning_services_rounded, 'label': 'Cleaning'},
      {'icon': Icons.build_rounded, 'label': 'Repair'},
      {'icon': Icons.local_shipping_rounded, 'label': 'Moving'},
      {'icon': Icons.directions_car_rounded, 'label': 'Automotive'},
      {'icon': Icons.computer_rounded, 'label': 'Computer'},
      {'icon': Icons.handyman_rounded, 'label': 'Handyman'},
    ];

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F1FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.location_on_rounded,
                      size: 18,
                      color: Color(0xFF1E7AF9),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6E7B8B),
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Davao City',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF132238),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFB6C5D8).withValues(alpha: 0.18),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.notifications_none_rounded,
                      color: Color(0xFF132238),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const Text(
                'FixNear',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: Color(0xFF12314D),
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'What can we help you with?',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF132238),
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF9BB8DB).withValues(alpha: 0.15),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: Color(0xFF6E7B8B),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Search for a service or provider',
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF8390A5),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.mic_none_rounded,
                      size: 20,
                      color: Color(0xFF1E7AF9),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 112,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final item = categories[index];
                    final icon = item['icon'] as IconData;
                    final label = item['label'] as String;

                    return SizedBox(
                      width: 82,
                      child: Column(
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(icon, color: const Color(0xFF1E7AF9)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            label,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF4F5F74),
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Available near you',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF132238),
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  TextButton(onPressed: () {}, child: const Text('See all')),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 290,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 2,
                  separatorBuilder: (_, _) => const SizedBox(width: 16),
                  itemBuilder: (_, index) {
                    final provider = index == 0
                        ? {
                            'name': 'Juan Santos',
                            'role': 'Electrician',
                            'distance': '1.2 km away',
                            'price': '₱500',
                            'rating': '4.9',
                            'reviews': '128 reviews',
                            'availability': 'Available now',
                          }
                        : {
                            'name': 'Maria Cruz',
                            'role': 'Plumber',
                            'distance': '2.4 km away',
                            'price': '₱650',
                            'rating': '4.8',
                            'reviews': '96 reviews',
                            'availability': 'Responds in 8 min',
                          };

                    return SizedBox(
                      width: 286,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFB9CBE1).withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFB9D8FF),
                                          Color(0xFFE0F0FF),
                                        ],
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.person_rounded,
                                      size: 32,
                                      color: Color(0xFF1A3E65),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE8FFF2),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'Available now',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1D8D63),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Text(
                                    provider['name'] as String,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF132238),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.verified_rounded,
                                    size: 17,
                                    color: Color(0xFF1E7AF9),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                provider['role'] as String,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF5F6F85),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.star_rounded,
                                    size: 16,
                                    color: Color(0xFFF6B445),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    provider['rating'] as String,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF132238),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    provider['reviews'] as String,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF66748A),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                    color: Color(0xFF6E7B8B),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    provider['distance'] as String,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF5E6D81),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Text(
                                    'From',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF66748A),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    provider['price'] as String,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF132238),
                                    ),
                                  ),
                                  const Spacer(),
                                  ElevatedButton(
                                    onPressed: () {},
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1E7AF9),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 10,
                                      ),
                                    ),
                                    child: const Text('View'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Popular services',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF132238),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _ServiceBadge(label: 'Emergency plumbing'),
                  _ServiceBadge(label: 'Aircon repair'),
                  _ServiceBadge(label: 'Deep cleaning'),
                  _ServiceBadge(label: 'Computer setup'),
                  _ServiceBadge(label: 'General repairs'),
                  _ServiceBadge(label: 'Furniture assembly'),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        elevation: 0,
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Explore',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Requests',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Messages',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _ServiceBadge extends StatelessWidget {
  const _ServiceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF214A7F),
        ),
      ),
    );
  }
}
