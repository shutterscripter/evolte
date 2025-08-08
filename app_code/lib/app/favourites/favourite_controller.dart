import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavouriteController extends GetxController {
  final RxSet<String> _favourites = <String>{}.obs;

  RxSet<String> get favourites => _favourites;

  @override
  void onInit() {
    super.onInit();
    _loadFavourites();
  }

  void _loadFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    final favList = prefs.getStringList('favourites') ?? [];
    _favourites.addAll(favList);
  }

  void _saveFavourites() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favourites', _favourites.toList());
  }

  bool isFavorite(String deviceId) {
    return _favourites.contains(deviceId);
  }

  void toggleFavorite(String deviceId) {
    if (_favourites.contains(deviceId)) {
      _favourites.remove(deviceId);
    } else {
      _favourites.add(deviceId);
    }
    _saveFavourites();
  }
}
