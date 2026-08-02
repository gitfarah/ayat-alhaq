import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';
import '../services/khatma_service.dart';
import '../services/library_events.dart';
import '../services/settings_service.dart';
import '../theme.dart';

class KhatmaScreen extends StatefulWidget {
  const KhatmaScreen({super.key});
  @override
  State<KhatmaScreen> createState() => _KhatmaScreenState();
}

class _KhatmaScreenState extends State<KhatmaScreen> {
  List<bool> _done = List.filled(30, false);
  DateTime? _start;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh when a juz gets auto-completed while reading (this
    // screen lives in MainScreen's IndexedStack and is never
    // re-created on tab switches).
    LibraryEvents.khatma.addListener(_load);
  }

  @override
  void dispose() {
    LibraryEvents.khatma.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('khatma');
    if (raw != null) {
      final m = jsonDecode(raw);
      setState(() {
        _done = (m['done'] as List).map((e) => e as bool).toList();
        final d = m['start'] as String?;
        _start = d != null ? DateTime.tryParse(d) : null;
      });
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('khatma',
        jsonEncode({'done': _done, 'start': _start?.toIso8601String()}));
  }

  void _toggle(int i) {
    setState(() {
      if (_done.every((e) => !e) && !_done[i]) _start = DateTime.now();
      _done[i] = !_done[i];
    });
    _save();
    if (_done.every((e) => e)) _showCongrats();
  }

  void _reset() {
    final l = L10n.of(context);
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              title: Text(l('resetKhatmaTitle')),
              content: Text(l('resetKhatmaBody')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l('cancel'))),
                ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _done = List.filled(30, false);
                        _start = null;
                      });
                      _save();
                      // Also clear the auto-tracking page record, so
                      // previously read pages don't instantly re-tick
                      // ajza' in the fresh khatma.
                      KhatmaService.resetReadPages();
                    },
                    child: Text(l('reset'),
                        style: const TextStyle(color: Colors.white))),
              ],
            ));
  }

  void _showCongrats() {
    final l = L10n.of(context);
    showDialog(
        context: context,
        builder: (_) => AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 8),
                const Text('🎉', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                Text(l('khatmaCongrats'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        fontFamily: '.SF Pro Text')),
                const SizedBox(height: 8),
                Text(l('khatmaAccept'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontFamily: '.SF Pro Text')),
                const SizedBox(height: 24),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    onPressed: () => Navigator.pop(context),
                    child: Text(l('khatmaThanks'),
                        style: const TextStyle(
                            color: Colors.white, fontFamily: '.SF Pro Text'))),
              ]),
            ));
  }

  String _ar(int n) {
    const d = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return n.toString().split('').map((c) => d[int.parse(c)]).join();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<SettingsService>().isDarkIn(context);
    final l = L10n.of(context);
    final completed = _done.where((e) => e).length;
    final progress = completed / 30;

    return Scaffold(
      appBar: AppBar(
        title: Text(l('tabKhatma')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _reset)
        ],
      ),
      body: Column(children: [
        // Header card
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5))
            ],
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${(progress * 100).toInt()}%',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.bold)),
                Text('${l.number(completed)} ${l('ofThirtyJuz')}',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontFamily: '.SF Pro Text')),
              ]),
              SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(children: [
                    CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white)),
                    Center(
                        child: Text(_ar(completed),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 22))),
                  ])),
            ]),
            const SizedBox(height: 14),
            ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.white))),
            if (_start != null) ...[
              const SizedBox(height: 8),
              Text('${l('startedOn')}: ${_start!.day}/${_start!.month}/${_start!.year}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: 12)),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            l('khatmaAutoInfo'),
            textDirection:
                l.isArabic ? TextDirection.rtl : TextDirection.ltr,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: '.SF Pro Text',
                fontSize: 11,
                height: 1.6,
                color: isDark
                    ? AppColors.darkTextSec
                    : AppColors.textSecondary),
          ),
        ),
        // Juz grid
        Expanded(
            child: GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1),
          itemCount: 30,
          itemBuilder: (_, i) {
            final done = _done[i];
            return GestureDetector(
              onTap: () => _toggle(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.primary
                      : (isDark ? AppColors.darkSurface : Colors.white),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: done
                          ? AppColors.primary
                          : (isDark ? AppColors.darkBorder : AppColors.border),
                      width: 1.5),
                  boxShadow: done
                      ? [
                          BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3))
                        ]
                      : null,
                ),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      done
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 22)
                          : Text(_ar(i + 1),
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark
                                      ? AppColors.darkText
                                      : AppColors.textPrimary,
                                  fontFamily: '.SF Pro Text')),
                      Text(l('juzWord'),
                          style: TextStyle(
                              fontSize: 10,
                              fontFamily: '.SF Pro Text',
                              color:
                                  done ? Colors.white70 : AppColors.textLight)),
                    ]),
              ),
            );
          },
        )),
      ]),
    );
  }
}