import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() => runApp(const MovieApp());

class MovieApp extends StatelessWidget {
  const MovieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Movie Hub',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFF121212),
        brightness: Brightness.dark,
      ),
      home: const MovieScreen(),
    );
  }
}

// ==========================================
// 1. МОДЕЛЬ ДАННЫХ ФИЛЬМА
// ==========================================
class Movie {
  final int id;
  final String title;
  final String overview;
  final String posterPath;
  final double rating;

  Movie({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterPath,
    required this.rating,
  });

  factory Movie.fromJson(Map<String, dynamic> json) {
    return Movie(
      id: json['id'] ?? 0,
      title: json['title'] ?? 'Без названия',
      overview: json['overview'] ?? 'Описание отсутствует...',
      posterPath: json['poster_path'] != null
          ? 'https://image.tmdb.org/t/p/w500${json['poster_path']}'
          : 'https://via.placeholder.com/500x750?text=No+Image',
      rating: (json['vote_average'] ?? 0.0).toDouble(),
    );
  }
}

// ==========================================
// 2. БАЗА ДАННЫХ SQLite ДЛЯ ИЗБРАННОГО
// ==========================================
class FavoritesDatabase {
  static final FavoritesDatabase instance = FavoritesDatabase._init();
  static Database? _database;

  FavoritesDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('favorites.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE favorites (
            id INTEGER PRIMARY KEY,
            title TEXT,
            overview TEXT,
            posterPath TEXT,
            rating REAL
          )
        ''');
      },
    );
  }

  Future<void> addFavorite(Movie movie) async {
    final db = await database;
    await db.insert(
      'favorites',
      {
        'id': movie.id,
        'title': movie.title,
        'overview': movie.overview,
        'posterPath': movie.posterPath,
        'rating': movie.rating,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeFavorite(int id) async {
    final db = await database;
    await db.delete('favorites', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Movie>> getFavorites() async {
    final db = await database;
    final result = await db.query('favorites');
    return result.map((json) => Movie(
      id: json['id'] as int,
      title: json['title'] as String,
      overview: json['overview'] as String,
      posterPath: json['posterPath'] as String,
      rating: json['rating'] as double,
    )).toList();
  }

  Future<bool> isFavorite(int id) async {
    final db = await database;
    final result = await db.query('favorites', where: 'id = ?', whereArgs: [id]);
    return result.isNotEmpty;
  }
}

// ==========================================
// 3. ЭКРАН ПРИЛОЖЕНИЯ
// ==========================================
class MovieScreen extends StatefulWidget {
  const MovieScreen({super.key});

  @override
  State<MovieScreen> createState() => _MovieScreenState();
}

class _MovieScreenState extends State<MovieScreen> {
  List<Movie> _movies = [];
  List<Movie> _favorites = [];
  bool _isLoading = true;
  int _currentIndex = 0; // 0 - Каталог, 1 - Избранное

  @override
  void initState() {
    super.initState();
    _fetchMovies();
    _loadFavorites();
  }

  // Сетевой запрос к открытому API демо-фильмов
  Future<void> _fetchMovies() async {
    const url = 'https://api.themoviedb.org/3/movie/popular?api_key=3326d7b4202a5e31536b359c47e85741&language=ru-RU';
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;
        setState(() {
          _movies = results.map((json) => Movie.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFavorites() async {
    final favs = await FavoritesDatabase.instance.getFavorites();
    setState(() {
      _favorites = favs;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? '🎬 Популярные фильмы' : '⭐ Избранное'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentIndex == 0
              ? _buildMovieList(_movies)
              : _buildMovieList(_favorites, isFavoriteTab: true),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.indigoAccent,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            if (index == 1) _loadFavorites(); // Обновляем избранное при переходе
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.movie), label: 'Каталог'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Избранное'),
        ],
      ),
    );
  }

  Widget _buildMovieList(List<Movie> movies, {bool isFavoriteTab = false}) {
    if (movies.isEmpty) {
      return Center(
        child: Text(
          isFavoriteTab ? 'В избранном пока ничего нет' : 'Список пуст',
          style: const TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: movies.length,
      itemBuilder: (context, index) {
        final movie = movies[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF1E1E1E),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                movie.posterPath,
                width: 50,
                height: 75,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image, size: 50),
              ),
            ),
            title: Text(movie.title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('⭐ Рейтинг: ${movie.rating}', style: const TextStyle(color: Colors.amber)),
                const SizedBox(height: 2),
                Text(movie.overview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
              ],
            ),
            trailing: IconButton(
              icon: Icon(
                isFavoriteTab ? Icons.delete : Icons.favorite_border,
                color: isFavoriteTab ? Colors.red : Colors.pinkAccent,
              ),
              onPressed: () async {
                if (isFavoriteTab) {
                  await FavoritesDatabase.instance.removeFavorite(movie.id);
                  _loadFavorites();
                } else {
                  await FavoritesDatabase.instance.addFavorite(movie);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('"${movie.title}" добавлено в избранное!'), duration: const Duration(seconds: 1)),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }
}