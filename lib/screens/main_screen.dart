import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_strings.dart';
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
    final t = L10n.of(context);
    return Scaffold(
      body: IndexedStack(index: _idx, children: _screens),
      // The tab ORDER is fixed (only the labels follow the language) —
      // pin the bar to LTR so switching to Arabic doesn't reverse the
      // tabs. The screens inside the IndexedStack still follow the
      // app-language direction for their own content.
      bottomNavigationBar: Directionality(
        textDirection: TextDirection.ltr,
        child: Container(
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                  width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _idx,
          onTap: (i) => setState(() => _idx = i),
          items: [
            BottomNavigationBarItem(
                icon: const Icon(Icons.highlight_rounded),
                label: t('tabHighlights')),
            BottomNavigationBarItem(
                icon: const Icon(Icons.bookmark_border_rounded),
                activeIcon: const Icon(Icons.bookmark_rounded),
                label: t('tabBookmarks')),
            BottomNavigationBarItem(
                icon: const Icon(Icons.check_circle_outline_rounded),
                activeIcon: const Icon(Icons.check_circle_rounded),
                label: t('tabKhatma')),
            BottomNavigationBarItem(
                icon: const Icon(Icons.menu_book_outlined),
                activeIcon: const Icon(Icons.menu_book_rounded),
                label: t('tabIndex')),
          ],
        ),
      ),
      ),
    );
  }
}
