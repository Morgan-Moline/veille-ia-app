
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:xml/xml.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

void main() {
  runApp(const VeilleIAApp());
}

class VeilleIAApp extends StatelessWidget {
  const VeilleIAApp({super.key});

@override
Widget build(BuildContext context) {
  
    
  

  // Garde ici le reste de ton code existant
    return MaterialApp(
      title: 'Veille IA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2457C5),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6FA),
      ),
      home: const VeilleHomePage(),
    );
  }
}

class VeilleCategory {
  final String name;
  final String description;
  final IconData icon;
  final String query;

  const VeilleCategory({
    required this.name,
    required this.description,
    required this.icon,
    required this.query,
  });
}

const categories = <VeilleCategory>[
  VeilleCategory(
    name: 'Comptabilité & fiscalité',
    description: 'TVA, fiscalité et actualités comptables',
    icon: Icons.calculate_outlined,
    query: 'comptabilité OR fiscalité OR TVA France',
  ),
  VeilleCategory(
    name: 'BTS Comptabilité-Gestion',
    description: 'Études, examens et ressources BTS CG',
    icon: Icons.school_outlined,
    query: '"BTS Comptabilité Gestion" OR "BTS CG"',
  ),
  VeilleCategory(
    name: 'Secteur professionnel',
    description: 'Matériel agricole, concessionnaires et location',
    icon: Icons.agriculture_outlined,
    query: '"matériel agricole" OR "location matériel agricole" '
        'OR concessionnaire agricole France',
  ),
];


class VeilleArticle {
  final String title;
  final String link;
  final String description;
  final String source;
  final DateTime? publishedAt;
  final String category;
  final String summary;

  const VeilleArticle({
    required this.title,
    required this.link,
    required this.description,
    required this.source,
    required this.publishedAt,
    required this.category,
    this.summary = '',
  });
}

class VeilleService {
  
  static Future<DateTime> fetchCloudUpdatedAt() async {
    final response = await http
        .get(
          
Uri.parse(
  'https://raw.githubusercontent.com/Morgan-Moline/veille-ia-data/main/data.json?refresh=${DateTime.now().millisecondsSinceEpoch}',
),

        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        'Impossible de lire la date de la veille : ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Format JSON invalide.');
    }

    final updatedAt = DateTime.tryParse(
      decoded['updated_at']?.toString() ?? '',
    );

    if (updatedAt == null) {
      throw const FormatException(
        'Date de mise à jour absente ou invalide.',
      );
    }

    return updatedAt.toUtc();
  }

  

static Future<List<VeilleArticle>> fetchCloudArticles() async {
  final response = await http
      .get(
        
Uri.parse(
  'https://raw.githubusercontent.com/Morgan-Moline/veille-ia-data/main/data.json?refresh=${DateTime.now().millisecondsSinceEpoch}',
),

      )
      .timeout(const Duration(seconds: 20));

  if (response.statusCode != 200) {
    throw Exception(
      'Impossible de récupérer la veille : ${response.statusCode}',
    );
  }

  final decoded = jsonDecode(response.body);

  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Format JSON invalide.');
  }

  final rawItems = decoded['articles'];

  if (rawItems is! List) {
    throw const FormatException(
      'La liste des articles est absente.',
    );
  }

  final articles = <VeilleArticle>[];

  for (final item in rawItems) {
    if (item is! Map) continue;

    final article = Map<String, dynamic>.from(item);
    final link = article['link']?.toString().trim() ?? '';

    // On ignore les articles sans lien exploitable.
    if (link.isEmpty) continue;

    articles.add(
      VeilleArticle(
        title: article['title']?.toString() ?? '',
        link: link,
        description: article['description']?.toString() ?? '',
        source: article['source']?.toString() ?? 'Google Actualités',
        publishedAt: DateTime.tryParse(
          article['published_at']?.toString() ?? '',
        ),
        category: article['category']?.toString() ?? '',
        summary: article['summary']?.toString() ?? '',
      ),
    );
  }

  return articles;
}


  static Future<List<VeilleArticle>> fetchCategory(
    VeilleCategory category,
  ) async {
    final uri = Uri.https(
      'news.google.com',
      '/rss/search',
      {
        'q': category.query,
        'hl': 'fr',
        'gl': 'FR',
        'ceid': 'FR:fr',
      },
    );

    final response = await http
        .get(
          uri,
          headers: {'User-Agent': 'VeilleIA/1.0'},
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Le flux a répondu ${response.statusCode}.');
    }

    final document = XmlDocument.parse(response.body);
    final items = document.findAllElements('item');
    final articles = <VeilleArticle>[];

    for (final item in items) {
      final title = _text(item, 'title');
      final link = _text(item, 'link');

      if (title.isEmpty || link.isEmpty) continue;

      final rawDate = _text(item, 'pubDate');
      final rawDescription = _text(item, 'description');
      final source = _text(item, 'source');

      articles.add(
        VeilleArticle(
          title: _cleanHtml(title),
          link: link,
          description: _cleanHtml(rawDescription),
          source: source.isEmpty ? 'Google Actualités' : source,
          publishedAt: DateTime.tryParse(rawDate) ??
              _tryParseDate(rawDate),
          category: category.name,
        ),
      );
    }

    return articles;
  }

  static String _text(XmlElement element, String tag) {
    final found = element.findElements(tag);
    return found.isEmpty ? '' : found.first.innerText.trim();
  }

  static DateTime? _tryParseDate(String value) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      try {
        // Certains flux utilisent le format de date RSS.
        final parts = value.split(' ');
        if (parts.length >= 5) {
          const months = {
            'Jan': '01',
            'Feb': '02',
            'Mar': '03',
            'Apr': '04',
            'May': '05',
            'Jun': '06',
            'Jul': '07',
            'Aug': '08',
            'Sep': '09',
            'Oct': '10',
            'Nov': '11',
            'Dec': '12',
          };

          final month = months[parts[2]];
          if (month != null) {
            final date = '${parts[3]}-$month-${parts[1]}';
            return DateTime.tryParse(date);
          }
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String _cleanHtml(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class VeilleHomePage extends StatefulWidget {
  const VeilleHomePage({super.key});
 
  @override
  State<VeilleHomePage> createState() => _VeilleHomePageState();
}


class _VeilleHomePageState extends State<VeilleHomePage> {
  
  
Widget _buildCategoryBackgroundImage() {
  Widget buildResponsiveImage(String asset) {
    return SizedBox.expand(
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
      ),
    );
  }

  if (_selectedCategory == 'Toutes') {
    return Row(
      children: [
        for (final asset in [
          'assets/images/comptabilite.jpg',
          'assets/images/etudes.jpg',
          'assets/images/secteur_pro.jpg',
        ])
          Expanded(
            child: ClipRect(
              child: buildResponsiveImage(asset),
            ),
          ),
      ],
    );
  }

  switch (_selectedCategory) {
    case 'Comptabilité & fiscalité':
      return buildResponsiveImage(
        'assets/images/comptabilite.jpg',
      );

    case 'BTS Comptabilité-Gestion':
      return buildResponsiveImage(
        'assets/images/etudes.jpg',
      );

    case 'Secteur professionnel':
      return buildResponsiveImage(
        'assets/images/secteur_pro.jpg',
      );

    default:
      return const SizedBox.shrink();
  }
}

  

  List<VeilleArticle> _articles = [];
  String _selectedCategory = 'Toutes';
  String _selectedFilter = 'Tous';

  final Set<String> _favoriteLinks = {};
  final Set<String> _readLinks = {};
  bool _preferencesLoaded = false;

  bool _loading = false;
  String? _error;
  DateTime? _lastRefresh;

  final Map<String, String> _summaries = {};
  final Set<String> _summarizingLinks = {};
  
String _displayCategoryName(String name) {
  switch (name) {
    case 'Comptabilité & fiscalité':
      return 'Comptabilité';
    case 'BTS Comptabilité-Gestion':
      return 'Études';
    case 'Secteur professionnel':
      return 'Secteur pro';
    default:
      return name;
  }
}

Color get _accentColor {
  switch (_selectedCategory) {
    case 'Comptabilité & fiscalité':
      return const Color(0xFF2468B4);
    case 'BTS Comptabilité-Gestion':
      return const Color(0xFF174A91);
    case 'Secteur professionnel':
      return const Color(0xFFC62828);
    default:
      return const Color(0xFF176B5B);
  }
}

Color get _secondaryColor {
  switch (_selectedCategory) {
    case 'Comptabilité & fiscalité':
      return const Color(0xFFF28C28);
    case 'BTS Comptabilité-Gestion':
      return const Color(0xFF55A6E8);
    case 'Secteur professionnel':
      return const Color(0xFFEF5350);
    default:
      return const Color(0xFF2468B4);
  }
}

Color _categoryAccentColor(String category) {
  switch (category) {
    case 'Comptabilité & fiscalité':
      return const Color(0xFF2468B4);
    case 'BTS Comptabilité-Gestion':
      return const Color(0xFF174A91);
    case 'Secteur professionnel':
      return const Color(0xFFC62828);
    default:
      return const Color(0xFF176B5B);
  }
}

Color _categorySecondaryColor(String category) {
  switch (category) {
    case 'Comptabilité & fiscalité':
      return const Color(0xFFF28C28);
    case 'BTS Comptabilité-Gestion':
      return const Color(0xFF55A6E8);
    case 'Secteur professionnel':
      return const Color(0xFFEF5350);
    default:
      return const Color(0xFF2468B4);
  }
}


IconData get _categoryBackgroundIcon {
  switch (_selectedCategory) {
    case 'Comptabilité & fiscalité':
      return Icons.calculate_outlined;
    case 'BTS Comptabilité-Gestion':
      return Icons.school_outlined;
    case 'Secteur professionnel':
      return Icons.agriculture_outlined;
    default:
      return Icons.dashboard_customize_outlined;
  }
}

String get _categoryBackgroundLabel {
  switch (_selectedCategory) {
    case 'Comptabilité & fiscalité':
      return 'COMPTABILITÉ • FISCALITÉ';
    case 'BTS Comptabilité-Gestion':
      return 'CCI CAMPUS CENTRE';
    case 'Secteur professionnel':
      return 'CLOUÉ • CASE IH';
    default:
      return 'COMPTABILITÉ • ÉTUDES • CLOUÉ';
  }
}


  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _favoriteLinks
        ..clear()
        ..addAll(prefs.getStringList('favoriteLinks') ?? []);

      _readLinks
        ..clear()
        ..addAll(prefs.getStringList('readLinks') ?? []);

      _preferencesLoaded = true;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      'favoriteLinks',
      _favoriteLinks.toList(),
    );

    await prefs.setStringList(
      'readLinks',
      _readLinks.toList(),
    );
  }

  Future<void> _toggleFavorite(String link) async {
    setState(() {
      if (!_favoriteLinks.add(link)) {
        _favoriteLinks.remove(link);
      }
    });

    await _savePreferences();
  }

  Future<void> _toggleRead(String link) async {
    setState(() {
      if (!_readLinks.add(link)) {
        _readLinks.remove(link);
      }
    });

    await _savePreferences();
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _refresh();
  }

  



  
  Future<void> _launchNewVeille() async {
    final controller = TextEditingController();

    try {
      final secret = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Lancer une nouvelle veille'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Secret d’accès',
              hintText: 'APP_SECRET',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Lancer'),
            ),
          ],
        ),
      );

      if (secret == null || secret.isEmpty) return;

      DateTime previousUpdatedAt;

      try {
        previousUpdatedAt = await VeilleService.fetchCloudUpdatedAt();
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Impossible de vérifier la date de la veille. Réessaie.',
            ),
          ),
        );
        return;
      }

      final response = await http
          .post(
            Uri.parse(
              'https://veille-ia-trigger.themomo450.workers.dev/',
            ),
            headers: {
              'Authorization': 'Bearer $secret',
              'Content-Type': 'application/json',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (response.statusCode == 401) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Secret incorrect.')),
        );
        return;
      }

      if (response.statusCode != 202) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Échec du lancement (${response.statusCode}) : ${response.body}',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Veille lancée ! Vérification de la nouvelle génération…',
          ),
          duration: Duration(seconds: 10),
        ),
      );

     
      var updated = false;
      final deadline = DateTime.now().add(
        const Duration(minutes: 8),
      );

      while (DateTime.now().isBefore(deadline)) {
        final remaining = deadline.difference(DateTime.now());
        await Future.delayed(
          remaining < const Duration(seconds: 10)
              ? remaining
              : const Duration(seconds: 10),
        );

        if (!mounted) return;

        try {
          final currentUpdatedAt =
              await VeilleService.fetchCloudUpdatedAt();

          if (currentUpdatedAt.isAfter(previousUpdatedAt)) {
            updated = true;
            break;
          }
        } catch (_) {
          // Une erreur temporaire n'arrête pas les vérifications.
        }
      }

      if (!mounted) return;

      if (updated) {
        await _refresh();

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nouvelle veille récupérée !'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La veille n’est pas encore à jour après 8 minutes. '
              'Tu pourras réessayer plus tard.',
            ),
            duration: Duration(seconds: 10),
          ),
        );
      }

    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors du lancement : $e'),
          duration: const Duration(seconds: 10),
        ),
      );
    } finally {
      controller.dispose();
    }
  }


  
  Future<void> _refresh({bool showMessage = false}) async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final articles = await VeilleService.fetchCloudArticles();

      final unique = <String, VeilleArticle>{};
      for (final article in articles) {
        unique.putIfAbsent(article.link, () => article);
      }

      final sorted = unique.values.toList()
        ..sort((a, b) {
          if (a.publishedAt == null) return 1;
          if (b.publishedAt == null) return -1;
          return b.publishedAt!.compareTo(a.publishedAt!);
        });

      if (!mounted) return;

      setState(() {
        _articles = sorted;
        _lastRefresh = DateTime.now();
      });

      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Actualisation terminée : ${sorted.length} articles.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Impossible de récupérer les actualités depuis GitHub. '
            'Vérifie ta connexion Internet puis réessaie.';
      });

      if (showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Échec de l’actualisation : $e'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }





  
List<VeilleArticle> get _visibleArticles {
  return _articles.where((article) {
    final matchesCategory = _selectedCategory == 'Toutes' ||
        article.category == _selectedCategory;

    final matchesFilter = switch (_selectedFilter) {
      'Favoris' => _favoriteLinks.contains(article.link),
      'Non lus' => !_readLinks.contains(article.link),
      'Lus' => _readLinks.contains(article.link),
      _ => true,
    };

    return matchesCategory && matchesFilter;
  }).toList();
}


  String _formatDate(DateTime? date) {
    if (date == null) return 'Date non disponible';
    final local = date.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    return '$d/$m/${local.year}';
  }

  
  Future<void> _openArticle(String link) async {
    final uri = Uri.tryParse(link);

    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty) {
      _showMessage('Lien d’article invalide.');
      return;
    }

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;

      if (opened) {
        if (!_readLinks.contains(link)) {
          await _toggleRead(link);
        }
      } else {
        _showMessage('Impossible d’ouvrir ce lien.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('Impossible d’ouvrir ce lien.');
      }
    }
  }


Future<void> _summarizeArticle(VeilleArticle article) async {
  setState(() {
    _summarizingLinks.add(article.link);
  });

  try {
    final prompt = '''
Tu es un assistant pédagogique français spécialisé en BTS Comptabilité-Gestion.

Analyse uniquement les informations fournies ci-dessous.
Ne fabrique aucun fait. Si les informations sont insuffisantes,
signale-le clairement.

Titre : ${article.title}
Source : ${article.source}
Date : ${_formatDate(article.publishedAt)}
Extrait disponible : ${article.description}

Rédige en français :
1. Résumé simple en 3 phrases maximum.
2. Trois points essentiels à retenir.
3. Intérêt pour le BTS CG ou le travail en entreprise.
4. Les éléments qui restent à vérifier dans l'article original.

Précise que ton analyse repose sur le titre et l'extrait fourni,
et non nécessairement sur l'article intégral.
''';

    final response = await http
        .post(
          Uri.parse('http://127.0.0.1:11434/api/generate'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': 'qwen2.5:7b',
            'prompt': prompt,
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != 200) {
      throw Exception('Ollama a répondu : ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final summary = data['response'] as String?;

    if (summary == null || summary.trim().isEmpty) {
      throw Exception('Le modèle n’a retourné aucun résumé.');
    }

    if (!mounted) return;
    setState(() {
      _summaries[article.link] = summary.trim();
    });
  } catch (e) {
    if (mounted) {
      _showMessage(
        'Résumé impossible. Vérifie qu’Ollama fonctionne sur ce PC.',
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        _summarizingLinks.remove(article.link);
      });
    }
  }
}

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_preferencesLoaded) {
  return const Scaffold(
    body: Center(
      child: CircularProgressIndicator(),
    ),
  );
}
    final visible = _visibleArticles;

    
return Scaffold(
  appBar: AppBar(
    backgroundColor: _accentColor.withValues(alpha: 0.08),
    title: const Row(
      children: [
        Icon(Icons.auto_awesome),
        SizedBox(width: 10),
        Text(
          'Veille IA',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    ),

        
        actions: [
          
  IconButton(
    tooltip: 'Mode révision BTS CG',
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const RevisionModePage(),
        ),
      );
    },
    icon: const Icon(Icons.school_outlined),
  ),

       IconButton(
    tooltip: 'Actualiser les articles publiés',
    
onPressed: _loading
    ? null
    : () => _refresh(showMessage: true),

    icon: const Icon(Icons.refresh),
      ),
       IconButton(
    tooltip: 'Lancer une nouvelle veille sur GitHub',
    onPressed: _launchNewVeille,
    icon: const Icon(Icons.cloud_sync),
  ),
  const SizedBox(width: 8),
],

        
      ),
     
body: Stack(
  children: [
    Positioned.fill(
      child: _buildCategoryBackgroundImage(),
    ),
    Positioned.fill(
      child: Container(
        color: Colors.white.withValues(alpha: 0.82),
      ),
    ),
    RefreshIndicator(
      onRefresh: () => _refresh(showMessage: true),
      child: ListView(

          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _buildWelcomeCard(),
            const SizedBox(height: 20),
            const Text(
              'Mes thèmes de veille',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildCategorySelector(),
            const SizedBox(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Actualités récentes',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!_loading)
                  Text(
                    '${visible.length} article${visible.length > 1 ? 's' : ''}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
              ],
            ),
            if (_lastRefresh != null) ...[
              const SizedBox(height: 4),
              Text(
                'Dernière actualisation : ${_formatDate(_lastRefresh)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            if (_loading && _articles.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Recherche des actualités en cours…'),
                    ],
                  ),
                ),
              )
            else if (_error != null && _articles.isEmpty)
              _buildMessageCard(
                icon: Icons.wifi_off,
                title: 'Veille indisponible',
                message: _error!,
                action: 'Réessayer',
                onPressed: _refresh,
              )
            else if (visible.isEmpty)
              _buildMessageCard(
                icon: Icons.article_outlined,
                title: 'Aucun article trouvé',
                message: 'Essaie un autre thème ou actualise la veille.',
                action: 'Actualiser',
                onPressed: _refresh,
              )
            else
              ...visible.map(_buildArticleCard),
            if (_error != null && _articles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.orange.shade900),
                ),
              ),
            const SizedBox(height: 20),
            
          
            Text(
              'Les articles proviennent de flux Google Actualités. '
              'Vérifie les informations importantes auprès de la source '
              'originale. Cette version ne génère pas encore de résumés IA.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);
}

Widget _buildWelcomeCard() {

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _accentColor,
            Color.lerp(_accentColor, _secondaryColor, 0.45)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            
            
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      _accentColor.withValues(alpha: 0.98),
                      _accentColor.withValues(alpha: 0.88),
                      _accentColor.withValues(alpha: 0.40),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.35, 0.68, 1.0],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'BONJOUR MORGAN',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Ta veille, en un coup d’oeil.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Comptabilité, études et actualités de ton secteur professionnel.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Text(
                      _categoryBackgroundLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.sync),
                    label: const Text('Actualiser ma veille'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildCategorySelector() {
    final filters = ['Tous', 'Non lus', 'Favoris', 'Lus'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...filters.map(
  (filter) => ChoiceChip(
    label: Text(filter),
    selected: _selectedFilter == filter,
    onSelected: (_) => setState(() => _selectedFilter = filter),
  ),
),
        _categoryChip('Toutes', Icons.dashboard_outlined),
        ...categories.map(
          (category) => _categoryChip(category.name, category.icon),
        ),
      ],
    );
  }

  
Widget _categoryChip(String name, IconData icon) {
  final selected = _selectedCategory == name;

  return FilterChip(
    selectedColor: _accentColor.withValues(alpha: 0.15),
    checkmarkColor: _accentColor,
    selected: selected,
    avatar: Icon(icon, size: 18),
    label: Text(_displayCategoryName(name)),
    onSelected: (_) => setState(() => _selectedCategory = name),
  );
}


 
Widget _buildArticleCard(VeilleArticle article) {
  final categoryColor = _categoryAccentColor(article.category);
  final categorySecondary = _categorySecondaryColor(article.category);

  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 0,
    color: Colors.white.withValues(alpha: 0.82),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Colors.grey.shade200),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => _openArticle(article.link),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: categoryColor,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _displayCategoryName(article.category),
                    style: TextStyle(
                      fontSize: 12,
                      color: categoryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _formatDate(article.publishedAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              article.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                height: 1.3,
                color: Colors.black,
              ),
            ),
            if (article.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                article.description,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: _favoriteLinks.contains(article.link)
                      ? 'Retirer des favoris'
                      : 'Ajouter aux favoris',
                  onPressed: () => _toggleFavorite(article.link),
                  icon: Icon(
                    _favoriteLinks.contains(article.link)
                        ? Icons.star
                        : Icons.star_border,
                    color: _favoriteLinks.contains(article.link)
                        ? Colors.amber.shade700
                        : Colors.grey,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _toggleRead(article.link),
                  icon: Icon(
                    _readLinks.contains(article.link)
                        ? Icons.visibility
                        : Icons.visibility_outlined,
                  ),
                  label: Text(
                    _readLinks.contains(article.link) ? 'Lu' : 'Non lu',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (article.summary.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 12, bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color.lerp(
                        Colors.white,
                        categoryColor,
                        0.12,
                      )!,
                      Color.lerp(
                        Colors.white,
                        categorySecondary,
                        0.18,
                      )!,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: categoryColor.withValues(alpha: 0.20),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: categoryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Résumé IA',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: categoryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      article.summary,
                      style: const TextStyle(
                        height: 1.5,
                        color: Colors.black,
                      ),
                    ),
                  ],
                ),
              )
            else
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _summarizeArticle(article),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Générer un résumé IA'),
                ),
              ),

            Row(
              children: [
                const Icon(Icons.public, size: 15),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    article.source,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                Icon(Icons.open_in_new, size: 17, color: categoryColor),
                const SizedBox(width: 4),
                Text(
                  'Lire',
                  style: TextStyle(
                    color: categoryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}


  Widget _buildMessageCard({
    required IconData icon,
    required String title,
    required String message,
    required String action,
    required VoidCallback onPressed,
  }) {
    return Card(
  elevation: 0,
  color: Colors.white.withValues(alpha: 0.82),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onPressed,
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}


class RevisionQuestion {
  final String question;
  final List<String> answers;
  final int correctAnswer;
  final String explanation;

  const RevisionQuestion({
    required this.question,
    required this.answers,
    required this.correctAnswer,
    required this.explanation,
  });
}

class RevisionModePage extends StatefulWidget {
  const RevisionModePage({super.key});

  @override
  State<RevisionModePage> createState() => _RevisionModePageState();
}

class _RevisionModePageState extends State<RevisionModePage> {
  static const Map<String, List<RevisionQuestion>> _questionBank = {
    
'TVA': [
  RevisionQuestion(
    question: 'La TVA collectée correspond à…',
    answers: [
      'La TVA facturée aux clients',
      'La TVA payée aux fournisseurs',
      'Le total des achats',
      'Le résultat de l’entreprise',
    ],
    correctAnswer: 0,
    explanation: 'La TVA collectée est facturée aux clients. Elle est généralement due à l’État selon le régime applicable.',
  ),
  RevisionQuestion(
    question: 'Une TVA déductible sur achat est généralement…',
    answers: [
      'Une charge définitive',
      'Récupérable sous conditions',
      'Un produit',
      'Une dette envers le client',
    ],
    correctAnswer: 1,
    explanation: 'La TVA sur les achats peut être déduite si les conditions légales sont respectées.',
  ),
  RevisionQuestion(
    question: 'Quel compte enregistre généralement la TVA collectée ?',
    answers: ['401', '411', '44571', '512'],
    correctAnswer: 2,
    explanation: 'Le compte 44571 correspond à la TVA collectée.',
  ),
  RevisionQuestion(
    question: 'Quel est le taux normal de TVA en France métropolitaine ?',
    answers: ['5,5 %', '10 %', '20 %', '2,1 %'],
    correctAnswer: 2,
    explanation: 'Le taux normal est de 20 %. Certains biens et services bénéficient de taux réduits ou particuliers.',
  ),
  RevisionQuestion(
    question: 'Une vente de 100 € HT est soumise à 20 % de TVA. Quel est le montant TTC ?',
    answers: ['100 €', '120 €', '20 €', '80 €'],
    correctAnswer: 1,
    explanation: 'TVA = 100 × 20 % = 20 €. TTC = 100 + 20 = 120 €.',
  ),
  RevisionQuestion(
    question: 'Une facture d’achat s’élève à 240 € TTC avec une TVA à 20 %. Quel est le montant HT ?',
    answers: ['200 €', '192 €', '220 €', '240 €'],
    correctAnswer: 0,
    explanation: 'HT = 240 / 1,20 = 200 €. La TVA représente 40 €.',
  ),
  RevisionQuestion(
    question: 'Quel compte enregistre généralement la TVA déductible sur autres biens et services ?',
    answers: ['44562', '44566', '44571', '401'],
    correctAnswer: 1,
    explanation: 'Le compte 44566 est généralement utilisé pour la TVA déductible sur autres biens et services.',
  ),
  RevisionQuestion(
    question: 'Quel compte est généralement utilisé pour la TVA déductible sur immobilisations ?',
    answers: ['44562', '44566', '44551', '707'],
    correctAnswer: 0,
    explanation: 'Le compte 44562 correspond à la TVA déductible sur immobilisations.',
  ),
  RevisionQuestion(
    question: 'Une entreprise collecte 500 € de TVA et dispose de 300 € de TVA déductible. Hors autres éléments, elle doit…',
    answers: [
      '200 € à l’État',
      '300 € à l’État',
      '500 € à l’État',
      'Récupérer 800 €',
    ],
    correctAnswer: 0,
    explanation: 'TVA à décaisser = TVA collectée − TVA déductible, soit 500 − 300 = 200 €.',
  ),
  RevisionQuestion(
    question: 'Lorsque la TVA déductible est supérieure à la TVA collectée, on peut obtenir…',
    answers: [
      'Un crédit de TVA',
      'Un bénéfice automatique',
      'Une immobilisation',
      'Une TVA collectée négative dans tous les cas',
    ],
    correctAnswer: 0,
    explanation: 'Un excédent de TVA déductible peut constituer un crédit de TVA, selon la déclaration et les règles applicables.',
  ),
  RevisionQuestion(
    question: 'Quel compte est généralement utilisé pour la TVA à décaisser ?',
    answers: ['44551', '44566', '411', '606'],
    correctAnswer: 0,
    explanation: 'Le compte 44551 correspond à la TVA à décaisser.',
  ),
  RevisionQuestion(
    question: 'Dans le régime de TVA sur les débits, la TVA sur une vente est généralement exigible…',
    answers: [
      'À l’encaissement uniquement',
      'Au débit du compte client, selon les règles applicables',
      'À la clôture annuelle uniquement',
      'Quand le fournisseur est payé',
    ],
    correctAnswer: 1,
    explanation: 'Pour les prestations de services ayant opté pour les débits et les opérations concernées, l’exigibilité suit les règles du régime des débits. Les règles diffèrent selon la nature de l’opération.',
  ),
  RevisionQuestion(
    question: 'Pour une prestation de services relevant du régime habituel des encaissements, la TVA est généralement exigible…',
    answers: [
      'À l’encaissement des sommes',
      'À la création de l’entreprise',
      'À la réception de toute facture fournisseur',
      'Uniquement à la clôture',
    ],
    correctAnswer: 0,
    explanation: 'Pour les prestations de services, la TVA est généralement exigible à l’encaissement, sauf option ou règle particulière.',
  ),
  RevisionQuestion(
    question: 'Une entreprise vend un produit 500 € HT avec un taux de TVA de 10 %. Quel est le montant de TVA ?',
    answers: ['5 €', '50 €', '100 €', '550 €'],
    correctAnswer: 1,
    explanation: 'TVA = 500 × 10 % = 50 €.',
  ),
  RevisionQuestion(
    question: 'Quel document permet généralement de déclarer la TVA due par une entreprise au régime réel normal ?',
    answers: ['La déclaration CA3', 'Le bulletin de paie', 'Le relevé bancaire uniquement', 'Le livre d’inventaire uniquement'],
    correctAnswer: 0,
    explanation: 'La déclaration CA3 est utilisée pour déclarer la TVA dans le régime réel normal. Les obligations varient selon le régime fiscal.',
  ),
],

   
'Immobilisations': [
  RevisionQuestion(
    question: 'Une immobilisation est destinée à…',
    answers: ['Être revendue immédiatement', 'Servir durablement à l’activité', 'Être consommée dans la journée', 'Régler une dette'],
    correctAnswer: 1,
    explanation: 'Une immobilisation est destinée à servir durablement l’activité de l’entreprise.',
  ),
  RevisionQuestion(
    question: 'Une machine coûte 10 000 € HT et la TVA est récupérable. Quel montant constitue généralement sa base d’acquisition avant les autres coûts ?',
    answers: ['12 000 €', '10 000 €', '2 000 €', '8 000 €'],
    correctAnswer: 1,
    explanation: 'La TVA récupérable est exclue du coût d’acquisition.',
  ),
  RevisionQuestion(
    question: 'Quel compte correspond généralement aux installations techniques, matériel et outillage industriels ?',
    answers: ['213', '215', '2183', '401'],
    correctAnswer: 1,
    explanation: 'Le compte 215 concerne les installations techniques, matériel et outillage industriels.',
  ),
  RevisionQuestion(
    question: 'Quel compte correspond généralement au matériel de transport ?',
    answers: ['2182', '2183', '215', '606'],
    correctAnswer: 0,
    explanation: 'Le compte 2182 est utilisé pour le matériel de transport.',
  ),
  RevisionQuestion(
    question: 'Une immobilisation est généralement inscrite à l’actif…',
    answers: ['Pour son coût d’acquisition selon les règles comptables', 'Pour son prix de revente futur', 'Pour son coût TTC dans tous les cas', 'Pour zéro euro'],
    correctAnswer: 0,
    explanation: 'L’entrée à l’actif repose généralement sur le coût d’acquisition ou de production, selon les règles applicables.',
  ),
  RevisionQuestion(
    question: 'Une entreprise achète un ordinateur destiné à être utilisé plusieurs années. Il s’agit généralement…',
    answers: ['D’une charge de personnel', 'D’une immobilisation', 'D’une dette fiscale', 'D’un produit'],
    correctAnswer: 1,
    explanation: 'Un ordinateur utilisé durablement pour l’activité peut être comptabilisé en immobilisation selon les règles et seuils applicables.',
  ),
  RevisionQuestion(
    question: 'Quel document justifie généralement l’achat d’une immobilisation ?',
    answers: ['La facture du fournisseur', 'Le bulletin de paie', 'Le relevé des congés', 'Le devis seul, dans tous les cas'],
    correctAnswer: 0,
    explanation: 'La facture constitue une pièce justificative courante de l’acquisition.',
  ),
  RevisionQuestion(
    question: 'Une immobilisation est mise en service le 1er janvier. Sa durée d’utilisation prévue est de 5 ans. En linéaire, le taux annuel est de…',
    answers: ['5 %', '10 %', '20 %', '25 %'],
    correctAnswer: 2,
    explanation: 'Taux linéaire = 100 % / 5 ans = 20 % par an.',
  ),
  RevisionQuestion(
    question: 'Lors de la cession d’une immobilisation, il faut notamment…',
    answers: ['Ignorer sa valeur comptable', 'Comptabiliser la cession et traiter la sortie de l’actif', 'Supprimer toutes les dettes', 'Annuler le chiffre d’affaires de l’année'],
    correctAnswer: 1,
    explanation: 'La cession implique d’enregistrer l’opération et de sortir l’immobilisation ainsi que ses amortissements cumulés selon les règles applicables.',
  ),
  RevisionQuestion(
    question: 'Quel compte est généralement utilisé pour les amortissements du matériel de transport ?',
    answers: ['28182', '2182', '401', '44571'],
    correctAnswer: 0,
    explanation: 'Le compte 28182 correspond aux amortissements du matériel de transport.',
  ),
],
'SIG': [
  RevisionQuestion(
    question: 'La marge commerciale concerne principalement…',
    answers: ['Les entreprises commerciales', 'Uniquement les banques', 'Uniquement les associations', 'Les immobilisations financières'],
    correctAnswer: 0,
    explanation: 'La marge commerciale concerne l’activité d’achat et de revente de marchandises.',
  ),
  RevisionQuestion(
    question: 'La valeur ajoutée mesure principalement…',
    answers: ['Le chiffre d’affaires seul', 'La richesse créée par l’activité', 'Le montant des dettes', 'La trésorerie seule'],
    correctAnswer: 1,
    explanation: 'La valeur ajoutée mesure la richesse créée après déduction des consommations en provenance de tiers.',
  ),
  RevisionQuestion(
    question: 'L’EBE signifie…',
    answers: ['Excédent brut d’exploitation', 'Évaluation bancaire externe', 'État budgétaire estimé', 'Écriture de bilan exceptionnelle'],
    correctAnswer: 0,
    explanation: 'L’EBE est l’excédent brut d’exploitation.',
  ),
  RevisionQuestion(
    question: 'Une entreprise réalise 50 000 € de ventes de marchandises et un coût d’achat des marchandises vendues de 30 000 €. Quelle est sa marge commerciale ?',
    answers: ['80 000 €', '30 000 €', '20 000 €', '50 000 €'],
    correctAnswer: 2,
    explanation: 'Marge commerciale = ventes de marchandises − coût d’achat des marchandises vendues, soit 50 000 − 30 000 = 20 000 €.',
  ),
  RevisionQuestion(
    question: 'Quel élément intervient dans le calcul de la valeur ajoutée ?',
    answers: ['Les consommations en provenance de tiers', 'Uniquement les dividendes', 'Uniquement les emprunts', 'Le capital social seul'],
    correctAnswer: 0,
    explanation: 'La valeur ajoutée se calcule notamment à partir de la production et/ou de la marge commerciale, diminuées des consommations en provenance de tiers.',
  ),
  RevisionQuestion(
    question: 'Les charges de personnel interviennent notamment dans le calcul…',
    answers: ['De l’EBE', 'Du capital social', 'Du montant de TVA collectée', 'Du total des immobilisations brutes'],
    correctAnswer: 0,
    explanation: 'Les charges de personnel sont prises en compte dans le calcul de l’EBE.',
  ),
  RevisionQuestion(
    question: 'Une entreprise a une valeur ajoutée de 80 000 € et des charges de personnel de 45 000 €. En simplifiant et en ignorant les autres éléments du calcul, quel est le solde après ces charges ?',
    answers: ['125 000 €', '35 000 €', '45 000 €', '80 000 €'],
    correctAnswer: 1,
    explanation: '80 000 − 45 000 = 35 000 €. Le calcul complet de l’EBE peut nécessiter d’autres éléments.',
  ),
  RevisionQuestion(
    question: 'Le résultat d’exploitation tient notamment compte…',
    answers: ['Des produits et charges d’exploitation', 'Uniquement des apports des associés', 'Uniquement de la TVA', 'Uniquement des remboursements d’emprunts'],
    correctAnswer: 0,
    explanation: 'Le résultat d’exploitation mesure le résultat lié à l’activité d’exploitation.',
  ),
  RevisionQuestion(
    question: 'Le résultat financier comprend notamment…',
    answers: ['Les produits et charges financiers', 'Les ventes de marchandises uniquement', 'Les salaires uniquement', 'La TVA déductible uniquement'],
    correctAnswer: 0,
    explanation: 'Le résultat financier résulte des produits financiers diminués des charges financières.',
  ),
  RevisionQuestion(
    question: 'Un EBE positif signifie nécessairement que le résultat net est positif.',
    answers: ['Vrai dans tous les cas', 'Faux', 'Vrai seulement si la TVA est nulle', 'Impossible si l’entreprise vend des marchandises'],
    correctAnswer: 1,
    explanation: 'Le résultat net tient aussi compte notamment des amortissements, du résultat financier, des éléments exceptionnels et de l’impôt.',
  ),
],
'Opérations courantes': [
  RevisionQuestion(
    question: 'Quel compte est généralement utilisé pour les fournisseurs ?',
    answers: ['401', '411', '512', '707'],
    correctAnswer: 0,
    explanation: 'Le compte 401 enregistre généralement les dettes envers les fournisseurs.',
  ),
  RevisionQuestion(
    question: 'Quel compte est généralement utilisé pour les clients ?',
    answers: ['401', '411', '606', '44566'],
    correctAnswer: 1,
    explanation: 'Le compte 411 enregistre généralement les créances clients.',
  ),
  RevisionQuestion(
    question: 'Quel compte correspond aux achats de matières premières ?',
    answers: ['601', '701', '411', '512'],
    correctAnswer: 0,
    explanation: 'Le compte 601 est utilisé pour les achats stockés de matières premières et fournitures.',
  ),
  RevisionQuestion(
    question: 'Quel compte correspond généralement aux ventes de marchandises ?',
    answers: ['607', '707', '601', '401'],
    correctAnswer: 1,
    explanation: 'Le compte 707 enregistre les ventes de marchandises.',
  ),
  RevisionQuestion(
    question: 'Une facture fournisseur est reçue. La dette fournisseur est généralement enregistrée…',
    answers: ['Au débit du 401', 'Au crédit du 401', 'Au débit du 512 uniquement', 'Au crédit du 411'],
    correctAnswer: 1,
    explanation: 'À la réception d’une facture d’achat à crédit, le compte fournisseur 401 est généralement crédité.',
  ),
  RevisionQuestion(
    question: 'Un client règle sa facture par virement bancaire. Quel compte de trésorerie est généralement débité ?',
    answers: ['512', '401', '707', '44571'],
    correctAnswer: 0,
    explanation: 'Le compte 512 Banque est débité lorsque l’argent arrive sur le compte bancaire.',
  ),
  RevisionQuestion(
    question: 'Une facture d’achat de marchandises comporte un montant HT de 1 000 € et une TVA de 20 %. Quel est le TTC ?',
    answers: ['1 020 €', '1 200 €', '800 €', '200 €'],
    correctAnswer: 1,
    explanation: 'TVA = 1 000 × 20 % = 200 €. TTC = 1 200 €.',
  ),
  RevisionQuestion(
    question: 'Dans une écriture comptable équilibrée…',
    answers: ['Le total débit égale le total crédit', 'Le débit est toujours supérieur', 'Le crédit est toujours supérieur', 'Il n’y a jamais de compte de tiers'],
    correctAnswer: 0,
    explanation: 'Le total des débits doit être égal au total des crédits.',
  ),
  RevisionQuestion(
    question: 'Une facture d’avoir fournisseur peut notamment correspondre à…',
    answers: ['Un retour de marchandises ou une réduction accordée', 'Un nouveau prêt bancaire uniquement', 'Une fiche de paie', 'Une déclaration de congés'],
    correctAnswer: 0,
    explanation: 'Un avoir peut corriger une facture antérieure, par exemple après un retour ou une réduction.',
  ),
  RevisionQuestion(
    question: 'Quel document sert couramment de justificatif à un paiement bancaire ?',
    answers: ['Un relevé bancaire', 'Un organigramme', 'Un CV', 'Un devis non accepté uniquement'],
    correctAnswer: 0,
    explanation: 'Le relevé bancaire permet de contrôler les mouvements enregistrés sur le compte.',
  ),
],
'Rapprochement bancaire': [
  RevisionQuestion(
    question: 'Le rapprochement bancaire sert principalement à…',
    answers: ['Comparer le compte Banque de la comptabilité au relevé bancaire', 'Calculer les congés payés', 'Déterminer le capital social', 'Établir une facture client'],
    correctAnswer: 0,
    explanation: 'Il permet d’expliquer les différences entre les écritures comptables et les opérations figurant sur le relevé.',
  ),
  RevisionQuestion(
    question: 'Un chèque émis est comptabilisé mais n’apparaît pas encore sur le relevé bancaire. Il s’agit généralement…',
    answers: ['D’un décalage de rapprochement', 'D’une erreur obligatoirement définitive', 'D’un produit exceptionnel', 'D’une immobilisation'],
    correctAnswer: 0,
    explanation: 'Le bénéficiaire n’a peut-être pas encore présenté le chèque à l’encaissement.',
  ),
  RevisionQuestion(
    question: 'Des frais bancaires apparaissent sur le relevé mais pas en comptabilité. Il faut généralement…',
    answers: ['Les enregistrer en comptabilité après vérification', 'Les ignorer définitivement', 'Les enregistrer en ventes', 'Les ajouter au capital'],
    correctAnswer: 0,
    explanation: 'Les frais doivent être comptabilisés à partir du relevé et des justificatifs disponibles.',
  ),
  RevisionQuestion(
    question: 'Le solde du compte 512 en comptabilité doit toujours être identique au relevé à chaque instant.',
    answers: ['Vrai', 'Faux, des décalages peuvent exister', 'Vrai uniquement pour les chèques', 'Vrai uniquement en fin d’année'],
    correctAnswer: 1,
    explanation: 'Les opérations en transit et les écritures non encore enregistrées peuvent créer des différences temporaires.',
  ),
  RevisionQuestion(
    question: 'Un virement reçu apparaît sur le relevé mais n’est pas comptabilisé. Quelle est la bonne démarche ?',
    answers: ['Identifier l’origine et enregistrer l’opération', 'Supprimer le relevé', 'Le comptabiliser automatiquement en capital', 'Ne rien faire dans tous les cas'],
    correctAnswer: 0,
    explanation: 'Il faut identifier le paiement, puis le comptabiliser dans le compte approprié.',
  ),
  RevisionQuestion(
    question: 'Le rapprochement bancaire doit permettre…',
    answers: ['D’expliquer les écarts', 'De supprimer toutes les opérations en transit', 'De modifier le relevé bancaire', 'De remplacer le bilan'],
    correctAnswer: 0,
    explanation: 'L’objectif est de justifier les différences entre les deux soldes.',
  ),
  RevisionQuestion(
    question: 'Un prélèvement bancaire inconnu apparaît sur le relevé. Il faut d’abord…',
    answers: ['Vérifier son origine et les pièces justificatives', 'Le classer immédiatement en vente', 'Le supprimer du relevé', 'L’ajouter au capital social'],
    correctAnswer: 0,
    explanation: 'Il faut identifier l’opération et vérifier son caractère autorisé avant sa comptabilisation ou toute contestation.',
  ),
  RevisionQuestion(
    question: 'Une remise de chèques enregistrée en comptabilité n’apparaît pas encore à la banque. Cela peut être…',
    answers: ['Un décalage temporaire', 'Une preuve de bénéfice', 'Une immobilisation', 'Une TVA collectée'],
    correctAnswer: 0,
    explanation: 'Le traitement bancaire de la remise peut intervenir à une date différente de son enregistrement comptable.',
  ),
  RevisionQuestion(
    question: 'Quel compte est généralement utilisé pour enregistrer les frais bancaires ?',
    answers: ['627', '707', '215', '401'],
    correctAnswer: 0,
    explanation: 'Le compte 627 concerne généralement les services bancaires et assimilés.',
  ),
  RevisionQuestion(
    question: 'Une fois le rapprochement établi, les écarts doivent être…',
    answers: ['Justifiés et suivis', 'Masqués', 'Ajoutés automatiquement au chiffre d’affaires', 'Toujours passés en charges exceptionnelles'],
    correctAnswer: 0,
    explanation: 'Chaque écart doit être expliqué ; une écriture de régularisation est nécessaire si une opération manque en comptabilité.',
  ),
],
'Amortissements': [
  RevisionQuestion(
    question: 'L’amortissement comptable traduit généralement…',
    answers: ['La répartition du montant amortissable sur la durée d’utilisation', 'Le paiement d’une facture', 'La récupération de la TVA', 'Une hausse automatique de valeur'],
    correctAnswer: 0,
    explanation: 'Il répartit le montant amortissable selon la durée et le rythme de consommation des avantages économiques.',
  ),
  RevisionQuestion(
    question: 'Une machine amortissable sur 5 ans en linéaire a un taux annuel de…',
    answers: ['5 %', '10 %', '20 %', '50 %'],
    correctAnswer: 2,
    explanation: '100 % / 5 ans = 20 % par an.',
  ),
  RevisionQuestion(
    question: 'Un bien de 12 000 € est amorti en linéaire sur 4 ans, sans valeur résiduelle. Quelle est l’annuité pleine ?',
    answers: ['1 000 €', '2 000 €', '3 000 €', '4 000 €'],
    correctAnswer: 2,
    explanation: '12 000 / 4 = 3 000 € par année pleine.',
  ),
  RevisionQuestion(
    question: 'L’amortissement commence généralement…',
    answers: ['À la mise en service du bien', 'À la commande uniquement', 'À la création de l’entreprise', 'Au remboursement complet du fournisseur'],
    correctAnswer: 0,
    explanation: 'En règle générale, le point de départ est la mise en service, selon les règles comptables applicables.',
  ),
  RevisionQuestion(
    question: 'Quel compte est généralement utilisé pour la dotation aux amortissements d’exploitation ?',
    answers: ['6811', '2815', '401', '707'],
    correctAnswer: 0,
    explanation: 'Le compte 6811 correspond aux dotations aux amortissements sur immobilisations incorporelles et corporelles.',
  ),
  RevisionQuestion(
    question: 'Quel type de compte enregistre les amortissements cumulés d’une immobilisation corporelle ?',
    answers: ['Un compte de classe 28', 'Un compte de classe 40', 'Un compte de classe 70', 'Un compte de classe 60'],
    correctAnswer: 0,
    explanation: 'Les amortissements cumulés sont enregistrés dans des comptes de classe 28.',
  ),
  RevisionQuestion(
    question: 'Un bien de 6 000 € est amorti sur 3 ans en linéaire. Quel est le taux annuel ?',
    answers: ['10 %', '25 %', '33,33 % environ', '50 %'],
    correctAnswer: 2,
    explanation: '100 % / 3 = environ 33,33 % par an.',
  ),
  RevisionQuestion(
    question: 'Un bien de 10 000 € est amorti sur 5 ans en linéaire. Quelle est sa valeur nette comptable après 2 annuités pleines, sans valeur résiduelle ?',
    answers: ['10 000 €', '8 000 €', '6 000 €', '2 000 €'],
    correctAnswer: 2,
    explanation: 'Annuité = 2 000 €. Après deux ans, amortissements cumulés = 4 000 €, donc VNC = 6 000 €.',
  ),
  RevisionQuestion(
    question: 'La valeur nette comptable correspond généralement…',
    answers: ['À la valeur d’origine moins les amortissements et dépréciations cumulés', 'Au prix TTC de la facture', 'Au chiffre d’affaires', 'Au solde bancaire'],
    correctAnswer: 0,
    explanation: 'La VNC correspond à la valeur comptable restante après les amortissements et dépréciations cumulés.',
  ),
  RevisionQuestion(
    question: 'Une annuité d’amortissement est-elle nécessairement identique chaque année ?',
    answers: ['Oui, dans toutes les méthodes', 'Non, cela dépend notamment de la méthode et de la période', 'Oui, même en cas de mise en service en cours d’année', 'Non, elle est toujours nulle la première année'],
    correctAnswer: 1,
    explanation: 'En linéaire, l’annuité d’une année pleine est constante, mais le prorata temporis ou une autre méthode peut modifier les montants.',
  ),
],
'Provisions': [
  RevisionQuestion(
    question: 'Une provision pour risques et charges est constatée notamment lorsqu’il existe…',
    answers: ['Une obligation probable dont le montant ou l’échéance est incertain', 'Une vente certaine', 'Un apport en capital', 'Une facture toujours payée'],
    correctAnswer: 0,
    explanation: 'Une provision répond à des critères comptables, notamment une obligation envers un tiers et une sortie de ressources probable ou certaine à la clôture.',
  ),
  RevisionQuestion(
    question: 'Une provision pour litige peut être constituée lorsque…',
    answers: ['Un risque de perte probable est identifié et estimable', 'L’entreprise veut augmenter artificiellement ses bénéfices', 'Un client paie comptant', 'La banque verse un intérêt'],
    correctAnswer: 0,
    explanation: 'La provision doit être justifiée par la situation existant à la clôture et respecter les conditions comptables.',
  ),
  RevisionQuestion(
    question: 'Quel compte est généralement utilisé pour une provision pour litiges ?',
    answers: ['1511', '401', '707', '512'],
    correctAnswer: 0,
    explanation: 'Le compte 1511 correspond généralement aux provisions pour litiges.',
  ),
  RevisionQuestion(
    question: 'Quel compte enregistre généralement une dotation à une provision pour risques d’exploitation ?',
    answers: ['6815', '707', '411', '512'],
    correctAnswer: 0,
    explanation: 'Le compte 6815 est généralement utilisé pour les dotations aux provisions d’exploitation.',
  ),
  RevisionQuestion(
    question: 'Une provision doit-elle être réexaminée à chaque clôture ?',
    answers: ['Oui', 'Non, jamais', 'Seulement tous les dix ans', 'Uniquement si la banque le demande'],
    correctAnswer: 0,
    explanation: 'La provision doit être réévaluée selon les informations disponibles à la clôture.',
  ),
  RevisionQuestion(
    question: 'Si le risque provisionné disparaît, il faut généralement…',
    answers: ['Reprendre la provision devenue sans objet', 'La conserver éternellement', 'La transformer en capital automatiquement', 'L’enregistrer en vente'],
    correctAnswer: 0,
    explanation: 'Une provision qui n’a plus de justification doit être reprise selon les règles comptables.',
  ),
  RevisionQuestion(
    question: 'Une provision et un amortissement sont-ils la même chose ?',
    answers: ['Oui', 'Non, ils répondent à des objectifs différents', 'Oui uniquement pour les véhicules', 'Oui uniquement à la clôture'],
    correctAnswer: 1,
    explanation: 'L’amortissement répartit le montant amortissable d’un actif ; une provision couvre notamment un risque ou une charge répondant aux critères requis.',
  ),
  RevisionQuestion(
    question: 'Une provision pour dépréciation d’une créance client peut être envisagée lorsque…',
    answers: ['Le recouvrement de la créance est incertain', 'Le client a toujours payé à l’heure', 'La facture n’existe pas', 'La banque augmente le taux d’intérêt'],
    correctAnswer: 0,
    explanation: 'Une dépréciation peut être constatée si la valeur recouvrable de la créance est inférieure à sa valeur comptable.',
  ),
  RevisionQuestion(
    question: 'La provision pour risques est généralement présentée…',
    answers: ['Au passif du bilan', 'Dans le chiffre d’affaires', 'Dans les disponibilités', 'Dans les ventes de marchandises'],
    correctAnswer: 0,
    explanation: 'Les provisions pour risques et charges figurent généralement au passif du bilan.',
  ),
  RevisionQuestion(
    question: 'La constitution d’une provision peut avoir un effet sur le résultat de l’exercice.',
    answers: ['Oui, via une dotation', 'Non, jamais', 'Seulement sur le capital social', 'Seulement sur la TVA collectée'],
    correctAnswer: 0,
    explanation: 'Une dotation à une provision est généralement comptabilisée en charge et réduit le résultat de l’exercice.',
  ),
],
'Paie': [
  RevisionQuestion(
    question: 'Le salaire brut correspond généralement…',
    answers: ['À la rémunération avant déduction des cotisations salariales', 'Au salaire net payé', 'Au montant des ventes', 'Aux seules cotisations patronales'],
    correctAnswer: 0,
    explanation: 'Le salaire brut sert notamment de base au calcul de nombreuses cotisations.',
  ),
  RevisionQuestion(
    question: 'Le salaire net à payer est généralement inférieur au salaire brut notamment à cause…',
    answers: ['Des cotisations salariales et retenues applicables', 'De la TVA sur les ventes', 'Des amortissements', 'Des créances clients'],
    correctAnswer: 0,
    explanation: 'Le net à payer résulte du brut diminué des retenues applicables, avec les ajustements prévus sur le bulletin.',
  ),
  RevisionQuestion(
    question: 'Quel compte enregistre généralement les rémunérations dues au personnel ?',
    answers: ['421', '401', '411', '707'],
    correctAnswer: 0,
    explanation: 'Le compte 421 correspond au personnel, rémunérations dues.',
  ),
  RevisionQuestion(
    question: 'Quel compte est généralement utilisé pour les charges de sécurité sociale et de prévoyance ?',
    answers: ['431', '512', '607', '44571'],
    correctAnswer: 0,
    explanation: 'Le compte 431 est utilisé notamment pour la Sécurité sociale.',
  ),
  RevisionQuestion(
    question: 'Les cotisations patronales sont généralement…',
    answers: ['Des charges supportées par l’employeur', 'Des ventes de marchandises', 'Des créances clients', 'Des immobilisations'],
    correctAnswer: 0,
    explanation: 'Les cotisations patronales constituent des charges sociales supportées par l’employeur.',
  ),
  RevisionQuestion(
    question: 'Quel document détaille la rémunération et les retenues du salarié ?',
    answers: ['Le bulletin de paie', 'Le relevé bancaire du fournisseur', 'Le grand livre client uniquement', 'Le devis commercial'],
    correctAnswer: 0,
    explanation: 'Le bulletin de paie détaille les éléments de rémunération et les retenues applicables.',
  ),
  RevisionQuestion(
    question: 'Le paiement du salaire par virement entraîne généralement…',
    answers: ['Un crédit du compte 512', 'Un débit du compte 512', 'Un crédit du compte 707', 'Un débit du compte 401'],
    correctAnswer: 1,
    explanation: 'Le compte Banque est crédité lorsque l’argent sort du compte pour payer le salaire.',
  ),
  RevisionQuestion(
    question: 'Quel compte correspond généralement aux charges de sécurité sociale et de prévoyance patronales ?',
    answers: ['645', '641', '411', '2183'],
    correctAnswer: 0,
    explanation: 'Le compte 645 enregistre généralement les charges de sécurité sociale et de prévoyance.',
  ),
  RevisionQuestion(
    question: 'Quel compte enregistre généralement les rémunérations du personnel ?',
    answers: ['641', '645', '512', '44566'],
    correctAnswer: 0,
    explanation: 'Le compte 641 correspond aux rémunérations du personnel.',
  ),
  RevisionQuestion(
    question: 'Les congés payés acquis mais non encore pris peuvent nécessiter…',
    answers: ['La comptabilisation d’une charge et d’une dette à la clôture', 'Une vente de marchandises', 'Une augmentation automatique du capital', 'Une annulation du bulletin de paie'],
    correctAnswer: 0,
    explanation: 'Les droits acquis par les salariés peuvent nécessiter une provision ou une dette à la clôture selon les règles applicables.',
  ),
],
'Analyse financière': [
  RevisionQuestion(
    question: 'Le fonds de roulement net global se calcule généralement ainsi :',
    answers: ['Ressources stables − emplois stables', 'Chiffre d’affaires − TVA', 'Créances clients − ventes', 'Salaires − cotisations'],
    correctAnswer: 0,
    explanation: 'Le FRNG compare les ressources stables aux emplois stables.',
  ),
  RevisionQuestion(
    question: 'Le besoin en fonds de roulement dépend notamment…',
    answers: ['Des stocks, créances et dettes d’exploitation', 'Du seul capital social', 'Du seul résultat net', 'Uniquement de la TVA collectée'],
    correctAnswer: 0,
    explanation: 'Le BFR reflète notamment le décalage entre les encaissements et décaissements liés au cycle d’exploitation.',
  ),
  RevisionQuestion(
    question: 'La trésorerie nette peut se calculer par…',
    answers: ['FRNG − BFR', 'BFR − chiffre d’affaires', 'Capital + TVA', 'Ventes − salaires uniquement'],
    correctAnswer: 0,
    explanation: 'La trésorerie nette correspond au FRNG diminué du BFR.',
  ),
  RevisionQuestion(
    question: 'Une entreprise a un FRNG de 40 000 € et un BFR de 25 000 €. Sa trésorerie nette théorique est de…',
    answers: ['65 000 €', '15 000 €', '25 000 €', '-15 000 €'],
    correctAnswer: 1,
    explanation: 'Trésorerie nette = 40 000 − 25 000 = 15 000 €.',
  ),
  RevisionQuestion(
    question: 'Le ratio d’autonomie financière permet notamment d’apprécier…',
    answers: ['Le poids des capitaux propres dans le financement', 'Le taux de TVA', 'Le nombre de factures clients', 'Le taux d’amortissement d’un véhicule'],
    correctAnswer: 0,
    explanation: 'Il aide à apprécier l’importance des capitaux propres dans la structure de financement, selon la formule retenue.',
  ),
  RevisionQuestion(
    question: 'Le chiffre d’affaires correspond généralement…',
    answers: ['Aux ventes de biens et services de l’activité', 'Au bénéfice net', 'À la trésorerie disponible', 'Au total des capitaux propres'],
    correctAnswer: 0,
    explanation: 'Le chiffre d’affaires représente les ventes de biens et services réalisées dans le cadre de l’activité.',
  ),
  RevisionQuestion(
    question: 'Un ratio de liquidité vise principalement à apprécier…',
    answers: ['La capacité à faire face aux dettes à court terme', 'La rentabilité des immobilisations uniquement', 'Le taux de TVA', 'Le montant des salaires bruts'],
    correctAnswer: 0,
    explanation: 'Les ratios de liquidité évaluent la capacité à honorer les échéances à court terme à partir des actifs disponibles ou réalisables.',
  ),
  RevisionQuestion(
    question: 'Le résultat net est généralement obtenu après prise en compte…',
    answers: ['Des produits, charges et impôts concernés', 'Uniquement du chiffre d’affaires', 'Uniquement des créances clients', 'Uniquement du capital social'],
    correctAnswer: 0,
    explanation: 'Le résultat net tient compte des produits et charges de l’exercice ainsi que de l’impôt sur les bénéfices, selon les règles applicables.',
  ),
  RevisionQuestion(
    question: 'Une hausse des délais de paiement clients tend généralement à…',
    answers: ['Augmenter le BFR', 'Réduire automatiquement le chiffre d’affaires', 'Augmenter le capital social', 'Supprimer les dettes fournisseurs'],
    correctAnswer: 0,
    explanation: 'Les créances clients immobilisent davantage de ressources et tendent à augmenter le BFR.',
  ),
  RevisionQuestion(
    question: 'Une augmentation des délais de paiement fournisseurs, toutes choses égales par ailleurs, tend généralement à…',
    answers: ['Réduire le BFR', 'Augmenter toujours les stocks', 'Réduire le capital social', 'Augmenter automatiquement le résultat net'],
    correctAnswer: 0,
    explanation: 'Des dettes fournisseurs plus élevées financent temporairement le cycle d’exploitation et tendent à réduire le BFR.',
  ),
],
'Contrôle de gestion': [
  RevisionQuestion(
    question: 'Une charge fixe est une charge qui, dans une certaine plage d’activité…',
    answers: ['Reste globalement stable au total', 'Augmente toujours proportionnellement aux ventes', 'Est toujours nulle', 'Correspond uniquement à la TVA'],
    correctAnswer: 0,
    explanation: 'Une charge fixe reste globalement stable au total dans une plage d’activité donnée.',
  ),
  RevisionQuestion(
    question: 'Une charge variable évolue généralement…',
    answers: ['Avec le niveau d’activité', 'Uniquement avec le capital social', 'Uniquement avec le taux de TVA', 'Sans aucun lien avec les quantités produites'],
    correctAnswer: 0,
    explanation: 'Une charge variable dépend du niveau d’activité, par exemple des quantités produites ou vendues.',
  ),
  RevisionQuestion(
    question: 'La marge sur coût variable se calcule par…',
    answers: ['Chiffre d’affaires − coûts variables', 'Chiffre d’affaires − capitaux propres', 'TVA collectée − capital social', 'Immobilisations − dettes'],
    correctAnswer: 0,
    explanation: 'La marge sur coût variable est égale au chiffre d’affaires diminué des coûts variables.',
  ),
  RevisionQuestion(
    question: 'Le seuil de rentabilité correspond au niveau de chiffre d’affaires pour lequel…',
    answers: ['Le résultat est nul', 'La TVA est toujours nulle', 'Le capital social double', 'Les stocks sont nécessairement nuls'],
    correctAnswer: 0,
    explanation: 'Au seuil de rentabilité, la marge sur coûts variables couvre les charges fixes et le résultat est nul.',
  ),
  RevisionQuestion(
    question: 'Une entreprise a 20 000 € de charges fixes et un taux de marge sur coût variable de 40 %. Quel est son seuil de rentabilité en chiffre d’affaires ?',
    answers: ['8 000 €', '20 000 €', '50 000 €', '80 000 €'],
    correctAnswer: 2,
    explanation: 'Seuil de rentabilité = charges fixes / taux de marge sur coût variable = 20 000 / 0,40 = 50 000 €.',
  ),
  RevisionQuestion(
    question: 'Le coût complet comprend généralement…',
    answers: ['Les charges directes et indirectes imputées au coût', 'Uniquement la TVA', 'Uniquement les salaires', 'Uniquement les charges variables'],
    correctAnswer: 0,
    explanation: 'Le coût complet regroupe les charges directes et une quote-part des charges indirectes selon une méthode d’imputation.',
  ),
  RevisionQuestion(
    question: 'Une charge directe est une charge qui…',
    answers: ['Peut être affectée directement à un coût sans répartition préalable', 'Doit toujours être fixe', 'Est toujours financière', 'N’est jamais comptabilisée'],
    correctAnswer: 0,
    explanation: 'Une charge directe peut être rattachée directement à un objet de coût.',
  ),
  RevisionQuestion(
    question: 'Un budget prévisionnel sert notamment à…',
    answers: ['Prévoir et piloter l’activité et les ressources', 'Remplacer toutes les factures', 'Supprimer les contrôles', 'Éviter la comptabilité'],
    correctAnswer: 0,
    explanation: 'Le budget permet de planifier les ressources et de comparer ensuite les prévisions aux réalisations.',
  ),
  RevisionQuestion(
    question: 'Un écart budgétaire est généralement…',
    answers: ['La différence entre une réalisation et une prévision', 'Le total des immobilisations', 'Le taux de TVA', 'Le capital social'],
    correctAnswer: 0,
    explanation: 'L’écart mesure la différence entre le réel et le budget, selon une convention de calcul à préciser.',
  ),
  RevisionQuestion(
    question: 'Un coût spécifique peut inclure…',
    answers: ['Les charges variables et les charges fixes spécifiques', 'Uniquement les charges financières', 'Uniquement la TVA collectée', 'Uniquement les apports en capital'],
    correctAnswer: 0,
    explanation: 'Le coût spécifique associe les charges variables et les charges fixes propres à l’objet étudié.',
  ),
],




  };
String _topic = 'TVA';
int _questionIndex = 0;
int? _selectedAnswer;
bool _checked = false;
bool _finished = false;
int _score = 0;


static const int _sessionLength = 10;

List<Map<String, dynamic>> _scoreHistory = [];

Set<String> _wrongQuestionIds = {};
bool _reviewingErrors = false;

bool _resultSavedForSession = false;




late List<RevisionQuestion> _sessionQuestions;
late List<String> _sessionTopics;

List<RevisionQuestion> get _questions => _sessionQuestions;

RevisionQuestion get _currentQuestion =>
    _questions[_questionIndex];
    
Future<void> _loadWrongQuestionIds() async {
  final prefs = await SharedPreferences.getInstance();
  final savedIds = prefs.getStringList('revision_wrong_questions');

  if (!mounted || savedIds == null) return;

  setState(() {
    _wrongQuestionIds = savedIds.toSet();
  });
}

Future<void> _saveWrongQuestionIds() async {
  final prefs = await SharedPreferences.getInstance();

  await prefs.setStringList(
    'revision_wrong_questions',
    _wrongQuestionIds.toList(),
  );
}

Future<void> _loadScoreHistory() async {
  final prefs = await SharedPreferences.getInstance();
  final savedHistory = prefs.getString('revision_score_history');

  if (savedHistory == null) return;

  try {
    final decoded = jsonDecode(savedHistory) as List;
    final history = decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    if (!mounted) return;

    setState(() {
      _scoreHistory = history;
    });
  } catch (_) {
    // Si l'historique enregistré est invalide, on l'ignore.
  }
}


Future<void> _saveSessionResult() async {
  if (_resultSavedForSession) return;

  _resultSavedForSession = true;

  _scoreHistory.insert(0, {
    'topic': _topic,
    'score': _score,
    'total': _questions.length,
    'date': DateTime.now().toIso8601String(),
  });

  if (_scoreHistory.length > 100) {
    _scoreHistory = _scoreHistory.take(100).toList();
  }

  try {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'revision_score_history',
      jsonEncode(_scoreHistory),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Score enregistré !'),
      ),
    );
  } catch (e) {
    _resultSavedForSession = false;
    debugPrint('Erreur lors de la sauvegarde du score : $e');
  }
}



@override
void initState() {
  super.initState();
  _prepareSession();
  _loadScoreHistory();
  _loadWrongQuestionIds();
}



void _prepareSession() {
  final pool = List<RevisionQuestion>.from(
    _questionBank[_topic]!,
  );

  pool.shuffle(Random());

  _sessionQuestions = pool
      .take(min(_sessionLength, pool.length))
      .toList();

  _sessionTopics = List<String>.filled(
    _sessionQuestions.length,
    _topic,
  );
}

void _prepareErrorSession() {
  final questions = <RevisionQuestion>[];
  final topics = <String>[];

  for (final entry in _questionBank.entries) {
    for (final question in entry.value) {
      final id = '${entry.key}|${question.question}';

      if (_wrongQuestionIds.contains(id)) {
        questions.add(question);
        topics.add(entry.key);
      }
    }
  }

  _sessionQuestions = questions;
  _sessionTopics = topics;

  _questionIndex = 0;
  _selectedAnswer = null;
  _checked = false;
  _finished = false;
  _score = 0;
  _resultSavedForSession = false;
  _reviewingErrors = true;
}



void _startErrorReview() {
  if (_wrongQuestionIds.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Aucune erreur à réviser pour le moment !'),
      ),
    );
    return;
  }

  setState(() {
    _prepareErrorSession();
  });
}

  
void _checkAnswer() {
  if (_selectedAnswer == null || _checked) return;

  final questionTopic = _sessionTopics[_questionIndex];
final questionId = '$questionTopic|${_currentQuestion.question}';
  final isCorrect =
      _selectedAnswer == _currentQuestion.correctAnswer;

  setState(() {
    _checked = true;

    if (isCorrect) {
      _score++;
      _wrongQuestionIds.remove(questionId);
    } else {
      _wrongQuestionIds.add(questionId);
    }
  });

  _saveWrongQuestionIds();
}


  void _nextQuestion() {
    if (_questionIndex < _questions.length - 1) {
      setState(() {
        _questionIndex++;
        _selectedAnswer = null;
        _checked = false;
      });
    } else {
  setState(() {
    _finished = true;
  });
  _saveSessionResult();
}
  }

  

void _restart() {
  setState(() {
    _questionIndex = 0;
    _selectedAnswer = null;
    _checked = false;
    _finished = false;
    _score = 0;
    _resultSavedForSession = false;

    if (_reviewingErrors) {
      _prepareErrorSession();
      
      if (_sessionQuestions.isEmpty) {
        _reviewingErrors = false;
        _prepareSession();
      }
    } else {
      _prepareSession();
    }
  });
}



  
void _changeTopic(String? topic) {
  if (topic == null) return;

  setState(() {
    _topic = topic;
    _questionIndex = 0;
    _selectedAnswer = null;
    _checked = false;
    _finished = false;
    _score = 0;
    _resultSavedForSession = false;
        _reviewingErrors = false;
    _prepareSession();
  });
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Révisions BTS CG'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          
          
          if (_scoreHistory.isNotEmpty) ...[
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              leading: const Icon(Icons.assessment_outlined),
              title: const Text(
                'Historique des scores',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                '${_scoreHistory.length} série(s) enregistrée(s)',
              ),
              children: _scoreHistory.take(5).map((result) {
                final date = DateTime.tryParse(
                  result['date']?.toString() ?? '',
                );

                final dateText = date == null
                    ? 'Date inconnue'
                    : '${date.day.toString().padLeft(2, '0')}/'
                      '${date.month.toString().padLeft(2, '0')}/'
                      '${date.year} à '
                      '${date.hour.toString().padLeft(2, '0')}:'
                      '${date.minute.toString().padLeft(2, '0')}';

                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 16),
                  title: Text(
                    result['topic']?.toString() ?? 'Révision',
                  ),
                  subtitle: Text(dateText),
                  trailing: Text(
                    '${result['score']}/${result['total']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],


          const Text(
            'Entraîne-toi à ton rythme',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choisis un thème, réponds aux questions et '
            'découvre les explications.',
          ),
          const SizedBox(height: 24),
          
          

          DropdownButtonFormField<String>(
            value: _topic,
            decoration: const InputDecoration(
              labelText: 'Thème de révision',
              border: OutlineInputBorder(),
            ),
            items: _questionBank.keys.map((topic) {
              return DropdownMenuItem(
                value: topic,
                child: Text(topic),
              );
            }).toList(),
            onChanged: _changeTopic,
          ),
          const SizedBox(height: 24),
          if (_finished) ...[
            const Icon(
              Icons.emoji_events_outlined,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              'Résultat : $_score / ${_questions.length}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _score == _questions.length
                  ? 'Excellent, tout est juste !'
                  : 'Continue à t’entraîner pour progresser.',
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 20),
            if (!_reviewingErrors && _wrongQuestionIds.isNotEmpty) ...[
              FilledButton.icon(
                onPressed: _startErrorReview,
                icon: const Icon(Icons.replay),
                label: Text(
                  'Réviser mes erreurs (${_wrongQuestionIds.length})',
                ),
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _restart,
              icon: const Icon(Icons.refresh),
              label: const Text('Recommencer'),
            ),

          ] else ...[
            Text(
              'Question ${_questionIndex + 1} / ${_questions.length}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (_questionIndex + 1) / _questions.length,
            ),
            const SizedBox(height: 24),
            Text(
              _currentQuestion.question,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...List.generate(
              _currentQuestion.answers.length,
              (index) {
                final isCorrect =
                    index == _currentQuestion.correctAnswer;
                final isSelected = index == _selectedAnswer;

                Color? tileColor;
                if (_checked && isCorrect) {
                  tileColor = Colors.green.withValues(alpha: 0.12);
                } else if (_checked && isSelected && !isCorrect) {
                  tileColor = Colors.red.withValues(alpha: 0.12);
                }

                return Card(
                  color: tileColor,
                  child: RadioListTile<int>(
                    value: index,
                    groupValue: _selectedAnswer,
                    title: Text(_currentQuestion.answers[index]),
                    onChanged: _checked
                        ? null
                        : (value) {
                            setState(() {
                              _selectedAnswer = value;
                            });
                          },
                  ),
                );
              },
            ),
            if (_checked) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedAnswer ==
                                _currentQuestion.correctAnswer
                            ? 'Bonne réponse !'
                            : 'Pas tout à fait.',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_currentQuestion.explanation),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _checked
                  ? _nextQuestion
                  : _selectedAnswer == null
                      ? null
                      : _checkAnswer,
              child: Text(
                !_checked
                    ? 'Vérifier ma réponse'
                    : _questionIndex == _questions.length - 1
                        ? 'Voir mon résultat'
                        : 'Question suivante',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
