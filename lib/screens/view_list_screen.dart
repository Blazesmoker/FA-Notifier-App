import 'package:flutter/material.dart';
import 'package:html/parser.dart';
import '../model/user_link.dart';
import '../widgets/PulsatingLoadingIndicator.dart';
import 'user_profile_screen.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ViewListScreen extends StatefulWidget {
  final String title;
  final String sanitizedUsername;

  const ViewListScreen({
    Key? key,
    required this.title,
    required this.sanitizedUsername,
  }) : super(key: key);

  @override
  _ViewListScreenState createState() => _ViewListScreenState();
}

class _ViewListScreenState extends State<ViewListScreen> {
  final _secureStorage = FlutterSecureStorage();
  List<UserLink> users = [];
  List<UserLink> filteredUsers = [];
  int currentPage = 1;
  bool isLoading = true;
  bool allPagesLoaded = false;
  String errorMessage = '';
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchAllUsers();
  }

  Future<void> _fetchAllUsers() async {
    String? cookieA = await _secureStorage.read(key: 'fa_cookie_a');
    String? cookieB = await _secureStorage.read(key: 'fa_cookie_b');

    if (cookieA == null || cookieB == null) {
      setState(() {
        errorMessage = 'No cookies found. User might not be logged in.';
        isLoading = false;
      });
      print("No cookies found.");
      return;
    }

    while (!allPagesLoaded) {
      final url = widget.title == "Recent Watchers"
          ? 'https://www.furaffinity.net/watchlist/to/${widget.sanitizedUsername}/$currentPage/'
          : 'https://www.furaffinity.net/watchlist/by/${widget.sanitizedUsername}/$currentPage/';

      try {
        final response = await http.get(
          Uri.parse(url),
          headers: {
            'Cookie': 'a=$cookieA; b=$cookieB',
            'User-Agent': 'Mozilla/5.0 (compatible; YourApp/1.0)',
          },
        );

        if (response.statusCode == 200) {
          final document = parse(response.body);
          final elements = document.querySelectorAll('.watch-list-items a, span.c-usernameBlockSimple.username-underlined a');


          List<UserLink> newUsers = elements.map((element) {
            final rawUsername = element.text;
            final url = 'https://www.furaffinity.net${element.attributes['href']}';
            return UserLink(rawUsername: rawUsername, url: url);
          }).toList();

          setState(() {
            users.addAll(newUsers);
            filteredUsers = users;
            currentPage++;
            if (newUsers.isEmpty) {
              allPagesLoaded = true;
              isLoading = false;
            }
          });
        } else {
          setState(() {
            errorMessage = 'Failed to load data: ${response.statusCode}';
            isLoading = false;
          });
          print("Failed to fetch data. Status code: ${response.statusCode}");
          break;
        }
      } catch (e) {
        setState(() {
          errorMessage = 'An error occurred: $e';
          isLoading = false;
        });
        print("An error occurred while fetching data: $e");
        break;
      }
    }
  }

  void _filterUsers(String query) {
    setState(() {
      searchQuery = query;
      filteredUsers = users
          .where((user) => user.cleanUsername.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: isLoading && !allPagesLoaded
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const PulsatingLoadingIndicator(size: 78.0, assetPath: 'assets/icons/fathemed.png'),
            const SizedBox(height: 20),
            const Text(
              "Loading all users for searching, please wait a moment...",
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      )
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              onChanged: _filterUsers,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by username',
                hintStyle: TextStyle(color: Colors.grey),
                filled: true,
                fillColor: Color(0xFF353535),
                prefixIcon: Icon(Icons.search, color: Colors.black),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide.none,
                ),
              ),
            )

          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredUsers.length,
              itemBuilder: (context, index) {
                final user = filteredUsers[index];
                return Column(
                  children: [
                    ListTile(
                      title: Text(
                        user.cleanUsername,
                        style: const TextStyle(color: Color(0xFFE09321)),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(
                              nickname: user.nickname,
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(
                      height: 1.0,
                      color: Colors.grey,
                      thickness: 0.3,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
