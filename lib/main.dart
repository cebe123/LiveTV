import 'dart:convert'; // For encoding and decoding JSON data
import 'package:flutter/foundation.dart'; // For kDebugMode to check if the app is running in debug mode
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

void main() {
  // Ensure bindings are initialized for InAppWebView platform setup.
  // This is necessary to use platform-specific features of the InAppWebView plugin.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp()); // Run the main application widget
}

class Channel {
  final String name;
  final String url;

  Channel({required this.name, required this.url});

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory Channel.fromJson(Map<String, dynamic> json) =>
      Channel(name: json['name'], url: json['url']);
}

// The root widget of the application
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const LiveTVScreen(),
    );
  }
}

// The main screen of the application, displaying the live TV player and channel list
class LiveTVScreen extends StatefulWidget {
  const LiveTVScreen({super.key});

  @override
  State<LiveTVScreen> createState() => _LiveTVScreenState();
}

// The state class for the LiveTVScreen widget, managing its dynamic content
class _LiveTVScreenState extends State<LiveTVScreen> {
  final List<Channel> _defaultChannels = [
    Channel(
      name: 'MetroTurk',
      url: 'https://metroturk.castpin.com/hls/metroturk/index.m3u8',
    ),
    Channel(
      name: 'BBC Radio 1 (Audio)',
      url:
          'http://as-hls-ww-live.akamaized.net/pool_01505109/live/ww/bbc_radio_one/bbc_radio_one.isml/bbc_radio_one-audio%3d96000.norewind.m3u8',
    ),
  ];

  List<Channel> channels = [];
  Channel? selectedChannel;
  late SharedPreferences prefs;

  // Key for forcing InAppWebView rebuild when the URL of the selected channel changes
  Key? _webViewKey;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  final FocusNode _nameFocusNode =
      FocusNode(); // Focus node for the channel name input field
  bool _isDialogVisible = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
    });
    try {
      prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('channels');
      List<Channel> loadedChannels = [];
      if (saved != null && saved.isNotEmpty) {
        try {
          final List decoded = json.decode(saved);
          loadedChannels = decoded.map((e) => Channel.fromJson(e)).toList();
        } catch (e) {
          if (kDebugMode) {
            print("Error decoding saved channels: $e");
          }
          loadedChannels = List.from(_defaultChannels);
          await _clearSavedChannels();
        }
      }

      setState(() {
        channels =
            loadedChannels.isNotEmpty
                ? loadedChannels
                : List.from(_defaultChannels);
        if (channels.isNotEmpty) {
          selectedChannel = channels[0];
          _updateWebViewKey();
        } else {
          selectedChannel = null;
          _webViewKey = null;
        }
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        print("Error loading SharedPreferences: $e");
      }
      setState(() {
        channels = List.from(_defaultChannels);
        if (channels.isNotEmpty) {
          selectedChannel = channels[0];
          _updateWebViewKey();
        }
        _isLoading = false;
      });
    }
  }

  // Helper function to update the WebView key based on the currently selected channel's URL
  void _updateWebViewKey() {
    if (selectedChannel != null) {
      // Using ValueKey ensures that Flutter recognizes a change in the URL and rebuilds the widget
      _webViewKey = ValueKey(selectedChannel!.url);
    } else {
      _webViewKey = null;
    }
  }

  Future<void> _clearSavedChannels() async {
    try {
      await prefs.remove('channels');
    } catch (e) {
      if (kDebugMode) {
        print("Error clearing saved channels: $e");
      }
    }
  }

  // Asynchronously saves the current list of channels to SharedPreferences
  Future<void> _saveChannels() async {
    final jsonList = channels.map((c) => c.toJson()).toList();
    await prefs.setString('channels', json.encode(jsonList));
  }

  // Adds a new channel to the list of channels
  void _addChannel() {
    if (_nameController.text.isNotEmpty && _urlController.text.isNotEmpty) {
      // Basic URL validation to check if it's a valid URL
      if (Uri.tryParse(_urlController.text)?.hasAbsolutePath ?? false) {
        final newChannel = Channel(
          name: _nameController.text,
          url: _urlController.text,
        );
        setState(() {
          channels.add(newChannel);
          _saveChannels();
          _updateWebViewKey();
        });
        _nameController.clear();
        _urlController.clear();
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lütfen geçerli bir URL girin.')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kanal adı ve URL boş bırakılamaz.')),
      );
    }
  }

  // Removes a channel from the list of channels
  void _removeChannel(Channel channel) {
    final bool wasSelected = selectedChannel == channel;
    setState(() {
      _isDialogVisible = true;
    });
    showDialog(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Kanalı Sil'),
          content: Text(
            '"${channel.name}" kanalını silmek istediğinizden emin misiniz?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(), // Close the dialog
              child: const Text('İptal'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() {
                  channels.remove(channel);
                  _saveChannels();
                  if (wasSelected) {
                    if (channels.isNotEmpty) {
                      selectedChannel = channels[0];
                    } else {
                      selectedChannel = null;
                    }
                    _updateWebViewKey();
                  }
                  _isDialogVisible = false;
                });
              },
              child: const Text(
                'Sil',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      setState(() {
        _isDialogVisible = false;
      });
    });
  }

  // Edits an existing channel in the list of channels
  void _editChannel(Channel channel) {
    _nameController.text = channel.name;
    _urlController.text = channel.url;

    setState(() {
      _isDialogVisible = true;
    });

    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Kanalı Düzenle'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Kanal Adı',
                    hintText: 'Örn: TRT 1',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'M3U8 Linki',
                    hintText: 'https://.../stream.m3u8',
                  ),
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (_nameController.text.isNotEmpty &&
                      _urlController.text.isNotEmpty) {
                    if (Uri.tryParse(_urlController.text)?.hasAbsolutePath ??
                        false) {
                      final index = channels.indexOf(channel);
                      if (index != -1) {
                        setState(() {
                          channels[index] = Channel(
                            name: _nameController.text,
                            url: _urlController.text,
                          );
                          _saveChannels();
                          if (selectedChannel == channel) {
                            selectedChannel = channels[index];
                            _updateWebViewKey();
                          }
                        });
                        _nameController.clear();
                        _urlController.clear();
                        Navigator.pop(dialogContext);
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lütfen geçerli bir URL girin.'),
                        ),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Kanal adı ve URL boş bırakılamaz.'),
                      ),
                    );
                  }
                },
                child: const Text('Kaydet'),
              ),
            ],
          ),
    ).then((_) {
      setState(() {
        _isDialogVisible = false;
      });
    });
  }

  Widget _buildWebViewPlayer(String url) {
    // HTML content for the video player using Video.js library
    final htmlContent = '''
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
      <link href="https://vjs.zencdn.net/8.10.0/video-js.css" rel="stylesheet" />
      <style>
        body, html { margin: 0; padding: 0; height: 100%; overflow: hidden; background-color: black; }
        /* Ensure the video player fills the container */
        #player_wrapper { width: 100%; height: 100%; }
        .video-js { width: 100%; height: 100%; }
      </style>
    </head>
    <body>
      <div id="player_wrapper">
        <video id="player" class="video-js vjs-default-skin vjs-big-play-centered" controls autoplay playsinline preload="auto">
          <source src="$url" type="application/x-mpegURL">
          Tarayıcınız video etiketini desteklemiyor veya M3U8 oynatılamıyor.
        </video>
      </div>
      <script src="https://vjs.zencdn.net/8.10.0/video.min.js"></script>
      <script>
        var player = videojs('player', {
          autoplay: true,
          controls: true,
          responsive: true,
          html5: {
            hls: {
              overrideNative: true
            },
            nativeAudioTracks: false,
            nativeVideoTracks: false
          }
        });

        // Error Handling for the video player
        player.on('error', function() {
          var error = player.error();
          console.error('Video.js Error:', error);
          document.getElementById('player_wrapper').innerHTML = '<p style="color: white; text-align: center;">Video Yüklenemedi: ' + (error ? error.message : 'Bilinmeyen Hata') + '</p>';
        });

        // Player resizes to fill the window
        function resizePlayer() {
          var video = document.getElementById('player');
          var newWidth = window.innerWidth;
          var newHeight = window.innerHeight;

          video.style.width = newWidth + 'px';
          video.style.height = newHeight + 'px';
          player.width(newWidth);
          player.height(newHeight);
        }
        
        // Call resize function on page load
        resizePlayer();
        
        // Call resize function when window size changes
        window.addEventListener('resize', resizePlayer);
        
        // Handle fullscreen change events
        document.addEventListener('fullscreenchange', resizePlayer);
        document.addEventListener('webkitfullscreenchange', resizePlayer);
        document.addEventListener('mozfullscreenchange', resizePlayer);
        document.addEventListener('MSFullscreenChange', resizePlayer);
      </script>
    </body>
    </html>
    ''';

    return InAppWebView(
      key: _webViewKey,
      initialData: InAppWebViewInitialData(
        data: htmlContent,
        mimeType: "text/html",
        encoding: "utf-8",
      ),
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        useShouldOverrideUrlLoading: true,
        useHybridComposition: true,
        javaScriptEnabled: true,
        supportZoom: false,
        transparentBackground: true,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        allowsLinkPreview: true,
        javaScriptCanOpenWindowsAutomatically: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
      ),
      onWebViewCreated: (controller) {
        if (kDebugMode) {
          print("WebView created for URL: $url");
        }
      },
      onReceivedError: (controller, request, error) {
        if (kDebugMode) {
          print(
            "WebView error: code $error, message: ${error.description}, url: ${request.url}",
          );
        }
        setState(() {
          _loadChannels();
        });
      },
      onReceivedHttpError: (controller, request, errorResponse) {
        if (kDebugMode) {
          print(
            "WebView HTTP error: status ${errorResponse.statusCode}, message: $errorResponse, url: ${request.url}",
          );
        }
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        var uri = navigationAction.request.url;
        if (uri != null && !uri.toString().startsWith('data:text/html')) {
          if (kDebugMode) {
            print("Blocked navigation to: $uri");
          }
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onEnterFullscreen: (controller) {
        if (kDebugMode) {
          print("WebView entered fullscreen mode");
        }
        controller.evaluateJavascript(source: "resizePlayer();");
      },
      onExitFullscreen: (controller) {
        if (kDebugMode) {
          print("WebView exited fullscreen mode");
        }
        controller.evaluateJavascript(source: "resizePlayer();");
      },
    );
  }

  @override
  void dispose() {
    // Clean up the controllers and focus nodes when the widget is disposed
    _nameFocusNode.dispose();
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Canlı Yayın (WebView)')),
      body:
          _isLoading
              ? const Center(
                child: CircularProgressIndicator(),
              ) // Show a loading indicator while channels are being loaded
              : LayoutBuilder(
                builder: (context, constraints) {
                  // Use LayoutBuilder to adapt the UI based on screen width
                  final isWide =
                      constraints.maxWidth >
                      600; // Determine if the screen is wide enough for a two-column layout
                  return isWide
                      ? Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: _buildPlayer(),
                          ), // Player takes 3/4 of the width on wide screens
                          Expanded(
                            flex: 1,
                            child: _buildSidebar(),
                          ), // Sidebar takes 1/4 of the width on wide screens
                        ],
                      )
                      : Column(
                        children: [
                          AspectRatio(
                            aspectRatio:
                                16 /
                                9, // Maintain a 16:9 aspect ratio for the player
                            child: _buildPlayer(),
                          ),
                          Expanded(
                            child: _buildSidebar(),
                          ), // Sidebar takes the remaining vertical space on narrow screens
                        ],
                      );
                },
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          FocusScope.of(context).unfocus();
          _showAddDialog(context);
        },
        tooltip: 'Yeni Kanal Ekle',
        child: const Icon(Icons.add), // Plus icon for the add button
      ),
    );
  }

  // Builds the video player widget
  Widget _buildPlayer() {
    return Opacity(
      opacity:
          _isDialogVisible
              ? 0.001
              : 1.0, // Reduce opacity when a dialog is visible to visually indicate it
      child: Container(
        color: Colors.black,
        child:
            selectedChannel == null || _webViewKey == null
                ? const Center(child: Text('Oynatılacak kanal seçilmedi.'))
                : _buildWebViewPlayer(selectedChannel!.url),
      ),
    );
  }

  // Builds the sidebar containing the list of channels
  Widget _buildSidebar() {
    if (channels.isEmpty) {
      return const Center(child: Text('Henüz kanal eklenmedi.'));
    }

    return ListView.builder(
      itemCount: channels.length,
      padding: const EdgeInsets.all(12),
      itemBuilder: (context, index) {
        final channel = channels[index];
        return Card(
          color:
              channel == selectedChannel
                  ? Colors.blueGrey[700]
                  : Colors.grey[850],
          elevation: 2.0,
          margin: const EdgeInsets.symmetric(vertical: 4.0),
          child: ListTile(
            title: Text(
              channel.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.amber),
                  tooltip: 'Kanalı Düzenle',
                  onPressed: () => _editChannel(channel),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  tooltip: 'Kanalı Sil',
                  onPressed: () => _removeChannel(channel),
                ),
              ],
            ),
            onTap: () {
              if (selectedChannel != channel) {
                setState(() {
                  selectedChannel = channel;
                  _updateWebViewKey();
                  if (kDebugMode) {
                    print("Seçilen Kanal (Android): ${selectedChannel?.name}");
                  }
                });
              }
            },
          ),
        );
      },
    );
  }

  // Shows the dialog to add a new TV channel
  void _showAddDialog(BuildContext context) {
    setState(() {
      _isDialogVisible = true;
    });
    _nameController.clear();
    _urlController.clear();

    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Yeni Kanal Ekle'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  focusNode:
                      _nameFocusNode, // Set focus on the name field when the dialog is shown
                  decoration: const InputDecoration(
                    labelText: 'Kanal Adı',
                    hintText: 'Örn: TRT 1',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'M3U8 Linki',
                    hintText: 'https://.../stream.m3u8',
                  ),
                  keyboardType:
                      TextInputType.url, // Set keyboard type for URL input
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('İptal'),
              ),
              ElevatedButton(
                onPressed: () {
                  _addChannel();
                },
                child: const Text('Ekle'),
              ),
            ],
          ),
    ).then((_) {
      setState(() {
        _isDialogVisible = false;
      });
      // Request focus on the name field after the dialog is shown
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).requestFocus(_nameFocusNode);
      });
    });
  }
}
