import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'bookmarks_screen.dart';
import 'highlight_screen.dart';
import 'khatma_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _idx = 3;
  final _screens = const [
    HighlightsScreen(),
    BookmarksScreen(),
    KhatmaScreen(),
    HomeScreen()
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkIn(context);
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                  width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _idx,
          onTap: (i) => setState(() => _idx = i),
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.highlight_rounded), label: 'التمييزات'),
            BottomNavigationBarItem(
                icon: Icon(Icons.bookmark_border_rounded),
                activeIcon: Icon(Icons.bookmark_rounded),
                label: 'الفواصل'),
            BottomNavigationBarItem(
                icon: Icon(Icons.check_circle_outline_rounded),
                activeIcon: Icon(Icons.check_circle_rounded),
                label: 'الختمة'),
            BottomNavigationBarItem(
                icon: Icon(Icons.menu_book_outlined),
                activeIcon: Icon(Icons.menu_book_rounded),
                label: 'الفهرس'),
          ],
        ),
      ),
    );
  }
}
