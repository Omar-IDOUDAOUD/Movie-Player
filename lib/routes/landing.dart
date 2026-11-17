import 'dart:io';
import 'dart:typed_data';

import 'package:dir_picker/dir_picker.dart';
import 'package:fc_native_video_thumbnail/fc_native_video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:movie_player/routes/local_videos_repo.dart';
import 'package:movie_player/routes/player.dart';
import 'package:movie_player/routes/selected_folder_videos.dart';
import 'package:movie_player/routes/watch_history.dart';
import 'package:movie_player/routes/web_video_extractor_1.dart';
import 'package:movie_player/routes/web_video_extractor_2.dart' as webview;

class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    required this.onToggleTheme,
    this.findVideos,
    this.sharedPage,
  });

  final VoidCallback onToggleTheme;

  /// Scans a web page for videos with both extraction mechanisms (html
  /// scraping and invisible WebView). Defaults to the combined scan of
  /// both extractors; tests inject a stub so no network is used.
  final Future<List<Uri>> Function(Uri page)? findVideos;

  /// A web page shared into the app: its extractor starts as soon as the
  /// link arrives (a fresh token also makes a repeated share rescan).
  final ({String url, int token})? sharedPage;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  /// The tabs of the bottom navigation bar.
  static const _folderTab = 0;
  static const _networkTab = 1;
  static const _webTab = 2;
  static const _historyTab = 3;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _pageUrlController = TextEditingController();

  /// Which tab is showing.
  var _tabIndex = _folderTab;

  bool _inputError = false;
  bool _pageInputError = false;

  /// True while a web page is being scanned for videos.
  bool _scanning = false;

  /// True while the folder picker is open, so the button can't be tapped
  /// twice (`DirPicker` rejects a second pick).
  bool _picking = false;

  /// True while a saved folder is being restored and listed.
  bool _restoring = false;

  /// The folders picked in earlier sessions, shown as buttons.
  List<SavedFolder> _savedFolders = const [];

  @override
  void initState() {
    super.initState();
    _loadSavedFolders();
    final shared = widget.sharedPage;
    if (shared != null) {
      // A link can be handed over before the first frame: scan once built.
      WidgetsBinding.instance.addPostFrameCallback((_) => _scanSharedPage(shared));
    }
  }

  @override
  void didUpdateWidget(LandingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shared = widget.sharedPage;
    if (shared != null && shared.token != oldWidget.sharedPage?.token) {
      _scanSharedPage(shared);
    }
  }

  /// Fills the web page field with a shared link and scans it at once.
  void _scanSharedPage(({String url, int token}) shared) {
    if (!mounted) return;
    _pageUrlController.text = shared.url;
    // Show the web page tab so the scan and its results are visible.
    setState(() => _tabIndex = _webTab);
    _scanWebPage();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _pageUrlController.dispose();
    super.dispose();
  }

  /// Shows the folders saved in earlier sessions under "Picked folders".
  Future<void> _loadSavedFolders() async {
    final folders = await loadSavedFolders();
    if (!mounted) return;
    setState(() => _savedFolders = folders);
  }

  void _submit() {
    final uri = _parseVideoUri(_urlController.text);
    if (uri == null) {
      setState(() => _inputError = true);
      return;
    }

    setState(() => _inputError = false);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          videoUri: uri,
          videoTitle: _titleController.text,
        ),
      ),
    );

    _titleController.clear();
    _urlController.clear();
  }

  /// Parses [raw] into a playable uri, or returns `null` when unsupported.
  ///
  /// A missing scheme defaults to `https://`, so `example.com/video.mp4`
  /// is accepted as well as a full `https://example.com/video.mp4`.
  Uri? _parseVideoUri(String raw) {
    var text = raw.trim();
    // Uri.parse percent-encodes invalid characters instead of failing, so
    // garbage like "not a url" must be rejected before parsing.
    if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;
    if (!text.contains('://')) text = 'https://$text';

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    // A percent sign in the host means the input was mangled while parsing.
    if (uri.host.contains('%')) return null;
    return uri;
  }

  /// Scans the web page the user entered for playable video urls:
  /// one result plays directly, many results open a choice list.
  Future<void> _scanWebPage() {
    // One scan at a time: a share arriving while scanning keeps the
    // running scan instead of racing it.
    if (_scanning) return Future.value();

    final page = _parsePageUri(_pageUrlController.text);
    if (page == null) {
      setState(() => _pageInputError = true);
      return Future.value();
    }

    setState(() {
      _pageInputError = false;
      _scanning = true;
    });
    return _findVideos(page);
  }

  /// Runs both extraction mechanisms on [page] and merges their results.
  ///
  /// v1 downloads and follows the player iframes, v2 runs the page in an
  /// invisible WebView and intercepts its requests; a video found by either
  /// is offered to the user. The page itself failing still throws, so the
  /// user learns it could not be read.
  Future<List<Uri>> findAllVideosOnPage(Uri page) async {
    final fromWebView = webview.findVideosWithWebView(page);
    final fromHtml = await findVideosOnPage(page);
    final fromRequests = await fromWebView;

    final all = <String, Uri>{};
    for (final video in [...fromHtml, ...fromRequests]) {
      all.putIfAbsent(video.toString(), () => video);
    }
    return all.values.toList();
  }

  Future<void> _findVideos(Uri page) async {
    try {
      final scan = widget.findVideos ?? findAllVideosOnPage;
      final videos = await scan(page);
      if (!mounted) return;
      setState(() => _scanning = false);

      if (videos.isEmpty) {
        _showMessage('No video found on this page');
      } else if (videos.length == 1) {
        _openVideo(videos.first);
      } else {
        await _chooseVideo(videos);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _scanning = false);
      _showMessage('Could not read this web page');
    }
  }

  /// Parses [raw] as the web page to scan. Only http(s) pages can be read.
  Uri? _parsePageUri(String raw) {
    var text = raw.trim();
    if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;
    if (!text.contains('://')) text = 'https://$text';

    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (uri.host.contains('%')) return null;
    return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
  }

  /// Lets the user pick one of the videos found on the page.
  Future<void> _chooseVideo(List<Uri> videos) async {
    final selected = await showDialog<Uri>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select a video'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final video in videos)
                TextButton(
                  onPressed: () => Navigator.pop(context, video),
                  child: Text(
                    video.toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.left,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    _openVideo(selected);
  }

  void _openVideo(Uri video) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerPage(videoUri: video, videoTitle: ''),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MPlayer'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
            tooltip: 'Toggle theme',
          ),
        ],
      ),
      body: switch (_tabIndex) {
        _networkTab => _scrollable(_networkTabChildren()),
        _webTab => _scrollable(_webTabChildren()),
        _historyTab => const _HistoryView(),
        _ => _scrollable(_folderTabChildren()),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_open_outlined),
            selectedIcon: Icon(Icons.folder_open),
            label: 'Folder',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            selectedIcon: Icon(Icons.play_circle_fill),
            label: 'Network',
          ),
          NavigationDestination(
            icon: Icon(Icons.language),
            label: 'Web page',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }

  /// A tab's content: scrollable, vertically centered and stretched.
  Widget _scrollable(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        );
      },
    );
  }

  /// The "Folder" tab: pick a folder and list the saved ones.
  List<Widget> _folderTabChildren() {
    return [
      const Text('Play videos from folder'),
      const SizedBox(
        height: 5,
      ),
      FilledButton.icon(
        label: const Text('Select a Folder'),
        icon: const Icon(Icons.folder_open_rounded),
        onPressed: _picking ? null : _pickFolder,
      ),
      if (_savedFolders.isNotEmpty) ...[
        const SizedBox(height: 20),
        const Text('Picked folders'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final folder in _savedFolders)
              OutlinedButton.icon(
                onPressed: _restoring
                    ? null
                    : () => _openSavedFolder(folder),
                icon: const Icon(Icons.folder_rounded),
                label: Text(folder.name),
              ),
          ],
        ),
      ],
    ];
  }

  /// The "Network" tab: play a video url directly.
  List<Widget> _networkTabChildren() {
    return [
      const Text('Play Network Video'),
      const SizedBox(
        height: 5,
      ),
      TextField(
        controller: _titleController,
        keyboardType: TextInputType.name,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          hintText: 'Video Title (Optional)',
          border: const OutlineInputBorder(),
          focusedBorder: const OutlineInputBorder(),
        ),
      ),
      SizedBox(
        height: 6,
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onChanged: (_) {
                if (_inputError) {
                  setState(() => _inputError = false);
                }
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Url',
                errorText:
                    _inputError ? 'Enter a valid video url' : null,
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            onPressed: _submit,
            icon: const Icon(Icons.play_arrow_rounded),
            tooltip: 'Play',
          ),
        ],
      ),
    ];
  }

  /// The "Web page" tab: scan a page for its videos.
  List<Widget> _webTabChildren() {
    return [
      const Text('Play Video from a web page url'),
      const SizedBox(
        height: 5,
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: _pageUrlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onChanged: (_) {
                if (_pageInputError) {
                  setState(() => _pageInputError = false);
                }
              },
              onSubmitted: (_) => _scanWebPage(),
              decoration: InputDecoration(
                hintText: 'Web page url',
                errorText: _pageInputError
                    ? 'Enter a valid web page url'
                    : null,
                border: const OutlineInputBorder(),
                focusedBorder: const OutlineInputBorder(),
              ),
            ),
          ),
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _scanWebPage,
              icon: const Icon(Icons.search),
              tooltip: 'Scan page for videos',
            ),
        ],
      ),
    ];
  }

  /// Picks a folder and opens the page listing its video files.
  Future<void> _pickFolder() async {
    setState(() => _picking = true);
    try {
      final folder = await selectVideosFolder();
      // The user cancelled the picker: stay on the landing page.
      if (folder == null || !mounted) return;

      await _savePickedFolder(folder);
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SelectedFolderVideosPage(
            entries: folder.entries,
            title: folder.name,
          ),
        ),
      );
    } on DirPickerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_folderErrorMessage(error))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the folder picker')),
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Remembers the picked folder so it shows under "Picked folders".
  ///
  /// Folders without a persist token can't be restored later and are not
  /// saved.
  Future<void> _savePickedFolder(PickedFolder folder) async {
    final token = folder.token;
    if (token == null) return;

    final saved = SavedFolder(token: token, name: folder.name);
    await rememberFolder(saved);
    if (!mounted) return;
    setState(() {
      _savedFolders = [
        ..._savedFolders.where((savedFolder) => savedFolder.token != token),
        saved,
      ];
    });
  }

  /// Restores a saved folder and opens the page listing its videos.
  Future<void> _openSavedFolder(SavedFolder folder) async {
    setState(() => _restoring = true);
    try {
      final location = await DirPicker.restore(folder.token);
      if (location == null) {
        // Access to the folder was lost: drop it from the list.
        await forgetFolder(folder.token);
        if (!mounted) return;
        setState(() {
          _savedFolders = [
            ..._savedFolders.where((saved) => saved.token != folder.token),
          ];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This folder is no longer accessible')),
        );
        return;
      }

      final entries = await DirPicker.listEntries(
        location,
        recursive: true,
      );
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SelectedFolderVideosPage(
            entries: filterVideoEntries(entries),
            title: folder.name,
          ),
        ),
      );
    } on DirPickerException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_folderErrorMessage(error))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this folder')),
      );
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  String _folderErrorMessage(DirPickerException error) {
    switch (error.code) {
      case DirPickerException.alreadyActive:
        return 'A folder picker is already open';
      case DirPickerException.listError:
        return 'The selected folder could not be read';
      default:
        return error.message ?? 'Could not open the folder picker';
    }
  }
}

/// The watch history list, shown in the landing page's "History" tab.
///
/// Every entry shows a thumbnail, the title (file name or url), the
/// duration and how far the user got. Tapping one resumes it in the
/// [PlayerPage].
class _HistoryView extends StatefulWidget {
  const _HistoryView();

  @override
  State<_HistoryView> createState() => _HistoryViewState();
}

class _HistoryViewState extends State<_HistoryView> {
  static final _fcThumbnail = FcNativeVideoThumbnail();

  late Future<List<WatchHistoryEntry>> _history;

  /// One future per video, so a thumbnail is generated at most once.
  final Map<String, Future<Uint8List?>> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    _history = WatchHistory.load();
  }

  /// Opens [entry] in the player and refreshes the list when coming back,
  /// so the newest watch position is shown.
  Future<void> _open(WatchHistoryEntry entry) async {
    final uri = Uri.tryParse(entry.uri);
    if (uri == null) return;

    final Widget player;
    if (uri.scheme == 'file') {
      player = PlayerPage(videoFile: File.fromUri(uri));
    } else {
      player = PlayerPage(videoUri: uri);
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => player),
    );
    if (!mounted) return;
    setState(() {
      _history = WatchHistory.load();
    });
  }

  /// Generates a thumbnail, or returns null when the platform can't.
  Future<Uint8List?> _loadThumbnail(WatchHistoryEntry entry) async {
    final uri = Uri.tryParse(entry.uri);
    if (uri == null) return null;

    final isFile = uri.scheme == 'file';
    try {
      return await _fcThumbnail.saveThumbnailToBytes(
        srcFile: isFile ? uri.toFilePath() : entry.uri,
        width: 168,
        height: 120,
        quality: 70,
        srcFileUri: !isFile &&
            uri.scheme != 'http' &&
            uri.scheme != 'https',
      );
    } catch (_) {
      // No thumbnail: the tile falls back to an icon.
      return null;
    }
  }

  Widget _thumbnail(WatchHistoryEntry entry) {
    final future = _thumbnailCache.putIfAbsent(
      entry.uri,
      () => _loadThumbnail(entry),
    );

    return SizedBox(
      width: 56,
      height: 40,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: FutureBuilder<Uint8List?>(
          future: future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data != null) {
              return Image.memory(data, fit: BoxFit.cover);
            }
            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.video_file_outlined, size: 20),
            );
          },
        ),
      ),
    );
  }

  /// `H:MM:SS`, the same format the player uses.
  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 48, color: Colors.black38),
          SizedBox(height: 12),
          Text('No watch history yet'),
        ],
      ),
    );
  }

  Widget _buildEntry(BuildContext context, WatchHistoryEntry entry) {
    final subtitle =
        '${_formatDuration(entry.duration)} • last at '
        '${_formatDuration(entry.position)}';

    return ListTile(
      leading: _thumbnail(entry),
      title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: entry.progress,
              minHeight: 3,
            ),
          ),
        ],
      ),
      onTap: () => _open(entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WatchHistoryEntry>>(
      future: _history,
      builder: (context, snapshot) {
        final entries = snapshot.data ?? const <WatchHistoryEntry>[];

        if (entries.isEmpty) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: SizedBox.square(
                dimension: 35,
                child: CircularProgressIndicator(),
              ),
            );
          }
          return _buildEmpty();
        }

        return ListView.builder(
          itemCount: entries.length,
          itemBuilder: (context, index) => _buildEntry(
            context,
            entries[index],
          ),
        );
      },
    );
  }
}
