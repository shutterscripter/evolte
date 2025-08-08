import 'package:evolt_controller/app/activities/activities_screen.dart';
import 'package:evolt_controller/app/favourites/favourites_screen.dart';
import 'package:evolt_controller/app/devices/scan_view.dart';
import 'package:evolt_controller/app/settings/settings_screen.dart';
import 'package:flutter/material.dart';

class NavigationExample extends StatefulWidget {
  const NavigationExample({super.key});

  @override
  State<NavigationExample> createState() => _NavigationExampleState();
}

class _NavigationExampleState extends State<NavigationExample> {
  int currentPageIndex = 1;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      bottomNavigationBar: NavigationBar(
        indicatorColor: Theme.of(context).primaryColor,
        backgroundColor: theme.colorScheme.surface,
        overlayColor: WidgetStateProperty.all(
          theme.colorScheme.surface.withValues(alpha: 0.5),
        ),
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        selectedIndex: currentPageIndex,
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.favorite_outlined),
            icon: Icon(Icons.favorite_border_rounded),

            label: 'Favorites',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.ev_station),
            icon: Icon(Icons.ev_station_outlined),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_rounded),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'Activities',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
      body: <Widget>[
        const FavouritesScreen(),
        const ScanPage(),
        const ActivitiesScreen(),
        const SettingsScreen(),
      ][currentPageIndex],
    );
  }
}
