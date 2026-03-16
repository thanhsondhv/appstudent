import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_html/flutter_html.dart';
import 'package:url_launcher/url_launcher.dart';


// ═══════════════════════════════════════════════════════
//  CONFIG
// ═══════════════════════════════════════════════════════
const String kNewsUrl       = 'https://mobi.vinhuni.edu.vn/api/news';
const String kNewsSearchUrl = 'https://mobi.vinhuni.edu.vn/api/news_search';
const String kImgBase       = 'https://vinhuni.edu.vn';

// ─── Design tokens ───────────────────────────────────
const Color kBlue1   = Color(0xFF003A8C);
const Color kBlue2   = Color(0xFF0057CF);
const Color kBlue3   = Color(0xFF1A73E8);
const Color kSurface = Color(0xFFF5F7FB);
const Color kCard    = Colors.white;
const Color kText1   = Color(0xFF0D1B2A);
const Color kText2   = Color(0xFF4A5568);
const Color kText3   = Color(0xFF94A3B8);

// ═══════════════════════════════════════════════════════
//  MODEL
// ═══════════════════════════════════════════════════════
class NewsItem {
  final String tieuDe, trichDan, hinhAnh, tacGia, nguoiDang, ngayDang;
  final String noiDung;
  final String tag;

  const NewsItem({
    required this.tieuDe, required this.trichDan, required this.hinhAnh,
    required this.tacGia, required this.nguoiDang, required this.ngayDang,
    this.noiDung = '', this.tag = '',
  });

  factory NewsItem.fromJson(Map<String, dynamic> j) {
    final title = (j['TieuDe'] ?? '').toString();
    return NewsItem(
      tieuDe:    title,
      trichDan:  (j['TrichDan']  ?? '').toString(),
      hinhAnh:   _fixUrl((j['HinhAnh']  ?? '').toString()),
      tacGia:    (j['TacGia']    ?? 'Trường ĐH Vinh').toString(),
      nguoiDang: (j['NguoiDang'] ?? '').toString(),
      ngayDang:  _fmtDate((j['NgayDang'] ?? '').toString()),
      noiDung:   (j['NoiDung']   ?? '').toString(),
      tag:       (j['Tag']       ?? _inferTag(title)).toString(),
    );
  }

  static String _fixUrl(String raw) {
    if (raw.isEmpty)                                  return '';
    if (raw.startsWith('http'))                       return raw;
    if (raw.startsWith('//'))                         return 'https:$raw';
    return '$kImgBase${raw.startsWith('/') ? '' : '/'}$raw';
  }

  static String _fmtDate(String s) {
    try {
      final d = DateTime.parse(s);
      return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
    } catch (_) { return s; }
  }

  static String _inferTag(String t) {
    final l = t.toLowerCase();
    if (l.contains('thông báo') || l.contains('lịch'))                          return 'Thông báo';
    if (l.contains('tuyển sinh'))                                                return 'Tuyển sinh';
    if (l.contains('bóng đá') || l.contains('thể thao'))                        return 'Thể thao';
    if (l.contains('lễ') || l.contains('tốt nghiệp') || l.contains('khai mạc')) return 'Sự kiện';
    if (l.contains('học bổng'))                                                  return 'Học bổng';
    if (l.contains('nghiên cứu') || l.contains('khoa học'))                     return 'Nghiên cứu';
    return 'Tin tức';
  }
}

// ═══════════════════════════════════════════════════════
//  TAG CONFIG
// ═══════════════════════════════════════════════════════
class TagStyle {
  final Color bg, text;
  final IconData icon;
  const TagStyle(this.bg, this.text, this.icon);
}

TagStyle _tagStyle(String tag) => switch (tag) {
  'Thông báo'  => const TagStyle(Color(0xFFEFF6FF), Color(0xFF1D4ED8), Icons.campaign_rounded),
  'Sự kiện'    => const TagStyle(Color(0xFFF5F3FF), Color(0xFF6D28D9), Icons.event_rounded),
  'Thể thao'   => const TagStyle(Color(0xFFECFDF5), Color(0xFF047857), Icons.sports_soccer_rounded),
  'Tuyển sinh' => const TagStyle(Color(0xFFFEF2F2), Color(0xFFB91C1C), Icons.school_rounded),
  'Học bổng'   => const TagStyle(Color(0xFFFFFBEB), Color(0xFFB45309), Icons.workspace_premium_rounded),
  'Nghiên cứu' => const TagStyle(Color(0xFFECFEFF), Color(0xFF0E7490), Icons.biotech_rounded),
  _            => const TagStyle(Color(0xFFEFF6FF), Color(0xFF1D4ED8), Icons.article_rounded),
};

Color _tagColor(String tag) => _tagStyle(tag).text;

// ═══════════════════════════════════════════════════════
//  API SERVICE
// ═══════════════════════════════════════════════════════
// ── API result with total ───────────────────────────
class NewsResult {
  final List<NewsItem> items;
  final int total;
  const NewsResult({required this.items, required this.total});
  int get totalPages => (total / NewsService.pageSize).ceil();
}

class NewsService {
  static const int pageSize = 6;

  static Future<NewsResult> fetch(int page) async {
    final res = await http.post(Uri.parse(kNewsUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'page': page}),
    ).timeout(const Duration(seconds: 10));
    return _parse(res);
  }

  static Future<NewsResult> search(String keyword, int page) async {
    final res = await http.post(Uri.parse(kNewsSearchUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'keyword': keyword, 'page': page}),
    ).timeout(const Duration(seconds: 10));
    return _parse(res);
  }

  static NewsResult _parse(http.Response res) {
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode == 200 && body['status'] == 'success') {
      final List data = (body['data'] ?? []) as List;
      final items = data.map((e) => NewsItem.fromJson(e as Map<String, dynamic>)).toList();
      final total = (body['total'] ?? 0) as int;
      return NewsResult(items: items, total: total);
    }
    throw Exception(body['message'] ?? 'HTTP ${res.statusCode}');
  }
}

// ═══════════════════════════════════════════════════════
//  NEWS LIST SCREEN
// ═══════════════════════════════════════════════════════
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});
  @override State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final _items  = <NewsItem>[];
  final _scroll = ScrollController();
  final _searchCtrl  = TextEditingController();
  final _searchFocus = FocusNode();
  Timer?  _debounce;

  int     _page       = 1;
  int     _totalPages = 1;
  int     _total      = 0;
  bool    _loading    = false;
  String? _error;
  String  _keyword    = '';
  bool    _isSearch   = false;

  @override
  void initState() {
    super.initState();
    _loadFirst();
    _searchCtrl.addListener(() => setState(() {})); // rebuild suffix icon
  }

  @override
  void dispose() {
    _scroll.dispose(); _searchCtrl.dispose();
    _searchFocus.dispose(); _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadFirst() async {
    setState(() { _loading = true; _error = null; _isSearch = false; _keyword = ''; });
    try {
      final result = await NewsService.fetch(1);
      if (!mounted) return;
      setState(() {
        _items..clear()..addAll(result.items);
        _page = 1; _total = result.total;
        _totalPages = result.totalPages.clamp(1, 9999);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _goToPage(int page) async {
    if (page < 1 || page > _totalPages || page == _page) return;
    setState(() => _loading = true);
    _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    try {
      final result = _isSearch
          ? await NewsService.search(_keyword, page)
          : await NewsService.fetch(page);
      if (!mounted) return;
      setState(() {
        _items..clear()..addAll(result.items);
        _page = page; _total = result.total;
        _totalPages = result.totalPages.clamp(1, 9999);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) { setState(() { _keyword = ''; _isSearch = false; }); _loadFirst(); return; }
    _debounce = Timer(const Duration(milliseconds: 450), () => _doSearch(v.trim()));
  }

  Future<void> _doSearch(String kw) async {
    setState(() { _loading = true; _error = null; _isSearch = true; _keyword = kw; });
    try {
      final result = await NewsService.search(kw, 1);
      if (!mounted) return;
      setState(() {
        _items..clear()..addAll(result.items);
        _page = 1; _total = result.total;
        _totalPages = result.totalPages.clamp(1, 9999);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _clearSearch() {
    _searchCtrl.clear(); _searchFocus.unfocus(); _onSearchChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      body: RefreshIndicator(
        color: kBlue2,
        onRefresh: () async { _searchCtrl.clear(); await _loadFirst(); },
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(),
            _buildSearchBar(),
            if (_isSearch && _keyword.isNotEmpty) _buildSearchBadge(),
            if (_loading)
              const SliverFillRemaining(child: Center(child: _Loader()))
            else if (_error != null)
              SliverFillRemaining(child: _ErrorView(onRetry: _isSearch ? () => _doSearch(_keyword) : _loadFirst))
            else if (_items.isEmpty)
                SliverFillRemaining(child: _isSearch ? _EmptySearch(keyword: _keyword) : const _EmptyView())
              else ...[
                  _buildList(),
                  SliverToBoxAdapter(child: _buildPagination()),
                ],
          ],
        ),
      ),
    );
  }

  // ── App bar ─────────────────────────────────────────
  Widget _buildAppBar() => SliverAppBar(
    expandedHeight: 72, pinned: true, centerTitle: true,
    backgroundColor: kBlue1,
    elevation: 0,
    leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
        onPressed: () => Navigator.of(context).maybePop()),
    title: const Text('Tin tức & Thông báo',
        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
    actions: [
      IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
          onPressed: () { _searchCtrl.clear(); _loadFirst(); }),
    ],
    flexibleSpace: Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF002B6B), kBlue2])),
      child: Stack(children: [
        Positioned(right: -24, top: -24,
            child: Container(width: 120, height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.07)))),
        Positioned(left: -10, bottom: -30,
            child: Container(width: 90, height: 90,
                decoration: BoxDecoration(shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.04)))),
      ]),
    ),
  );

  // ── Search bar ──────────────────────────────────────
  Widget _buildSearchBar() => SliverPersistentHeader(
    pinned: true,
    delegate: _SearchDelegate(
      Container(
        color: kBlue1,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.13),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.22)),
          ),
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 0.1),
            cursorColor: Colors.white70,
            decoration: InputDecoration(
              hintText: 'Tìm kiếm tin tức, thông báo...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 13.5),
              prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 12, right: 8),
                  child: Icon(Icons.search_rounded, color: Colors.white60, size: 19)),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? GestureDetector(onTap: _clearSearch,
                  child: const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.cancel_rounded, color: Colors.white60, size: 18)))
                  : null,
              suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ),
    ),
  );

  // ── Search badge ────────────────────────────────────
  Widget _buildSearchBadge() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
              color: kBlue2.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kBlue2.withOpacity(0.18))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search_rounded, size: 13, color: kBlue2),
            const SizedBox(width: 5),
            Text('"$_keyword"', style: const TextStyle(
                color: kBlue2, fontSize: 12, fontWeight: FontWeight.w700)),
            if (!_loading) ...[
              const SizedBox(width: 4),
              Text('· ${_items.length}${_page < _totalPages ? '+' : ''} bài',
                  style: TextStyle(color: kText3, fontSize: 11)),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
            onTap: _clearSearch,
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0))),
                child: const Text('Xoá bộ lọc',
                    style: TextStyle(color: kText2, fontSize: 12, fontWeight: FontWeight.w500)))),
      ]),
    ),
  );

  // ── List ────────────────────────────────────────────
  Widget _buildList() => SliverPadding(
    padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
    sliver: SliverList(delegate: SliverChildBuilderDelegate(
          (_, i) {
        // First item gets featured card style
        if (i == 0 && !_isSearch) {
          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            builder: (_, v, child) => Opacity(opacity: v,
                child: Transform.translate(offset: Offset(0, 20*(1-v)), child: child)),
            child: _FeaturedCard(news: _items[0]),
          );
        }
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 300 + (i % 6) * 50),
          curve: Curves.easeOutCubic,
          builder: (_, v, child) => Opacity(opacity: v,
              child: Transform.translate(offset: Offset(0, 14*(1-v)), child: child)),
          child: _NewsCard(news: _items[i]),
        );
      },
      childCount: _items.length,
    )),
  );

  // ── Pagination bar ─────────────────────────────────
  Widget _buildPagination() {
    if (_totalPages <= 1) return const SizedBox(height: 28);

    final Set<int> shown = {1, _totalPages, _page};
    for (int d = 1; d <= 2; d++) {
      if (_page - d >= 1) shown.add(_page - d);
      if (_page + d <= _totalPages) shown.add(_page + d);
    }
    final pages = shown.toList()..sort();

    final List<Widget> chips = [];
    int? prev;
    for (final p in pages) {
      if (prev != null && p - prev > 1) chips.add(const _PageEllipsis());
      chips.add(_PageChip(number: p, isActive: p == _page, onTap: () => _goToPage(p)));
      prev = p;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 36),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Trang $_page / $_totalPages',
              style: const TextStyle(color: kText3, fontSize: 11, fontWeight: FontWeight.w500)),
          if (_total > 0) ...[
            const Text('  ·  ', style: TextStyle(color: kText3, fontSize: 11)),
            Text('$_total bài', style: const TextStyle(color: kText3, fontSize: 11)),
          ],
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _NavBtn(icon: Icons.chevron_left_rounded,  enabled: _page > 1,             onTap: () => _goToPage(_page - 1)),
          const SizedBox(width: 6),
          Flexible(child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min,
                children: chips.map((c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: c)).toList()),
          )),
          const SizedBox(width: 6),
          _NavBtn(icon: Icons.chevron_right_rounded, enabled: _page < _totalPages, onTap: () => _goToPage(_page + 1)),
        ]),
      ]),
    );
  }
}

// ── Delegate ────────────────────────────────────────────
class _SearchDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  const _SearchDelegate(this.child);
  @override double get minExtent => 56;
  @override double get maxExtent => 56;
  @override bool shouldRebuild(_) => true;
  @override Widget build(_, __, ___) => child;
}

// ═══════════════════════════════════════════════════════
//  FEATURED CARD (bài đầu tiên — to hơn)
// ═══════════════════════════════════════════════════════
class _FeaturedCard extends StatelessWidget {
  final NewsItem news;
  const _FeaturedCard({required this.news});

  @override
  Widget build(BuildContext context) {
    final ts = _tagStyle(news.tag);
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => NewsDetailScreen(news: news))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
            color: kCard, borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: kBlue1.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 6)),
              BoxShadow(color: kBlue1.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
            ]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Image 200px
            Stack(children: [
              Image.network(news.hinhAnh, height: 200, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _ImgFallback(height: 200, tag: news.tag)),
              // Gradient
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.55)])))),
              // Tag chip top-left
              Positioned(top: 14, left: 14,
                  child: _TagChip(tag: news.tag, style: ts)),
              // "Nổi bật" badge top-right
              Positioned(top: 14, right: 14,
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.35))),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.star_rounded, color: Colors.amber, size: 11),
                        SizedBox(width: 3),
                        Text('Nổi bật', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                      ]))),
              // Date bottom-right
              Positioned(bottom: 12, right: 14,
                  child: _DateBadge(date: news.ngayDang)),
            ]),
            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(news.tieuDe, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800,
                        height: 1.35, color: kText1, letterSpacing: -0.3)),
                const SizedBox(height: 8),
                Text(news.trichDan, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kText2, fontSize: 13.5, height: 1.55)),
                const SizedBox(height: 14),
                Row(children: [
                  _AuthorChip(name: news.tacGia, color: ts.text),
                  const Spacer(),
                  _ReadBtn(color: ts.text),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  STANDARD NEWS CARD
// ═══════════════════════════════════════════════════════
class _NewsCard extends StatelessWidget {
  final NewsItem news;
  const _NewsCard({required this.news});

  @override
  Widget build(BuildContext context) {
    final ts = _tagStyle(news.tag);
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => NewsDetailScreen(news: news))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: kCard, borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: kBlue1.withOpacity(0.06), blurRadius: 16, offset: const Offset(0, 4)),
            ]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // Left accent bar with color
              Container(width: 4,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [ts.text, ts.text.withOpacity(0.4)]))),
              // Thumbnail
              ClipRRect(
                borderRadius: const BorderRadius.only(
                    topRight: Radius.zero, bottomRight: Radius.zero),
                child: SizedBox(
                  width: 110,
                  child: Stack(fit: StackFit.expand, children: [
                    Image.network(news.hinhAnh, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _ImgFallback(height: 0, tag: news.tag)),
                    // Subtle overlay
                    DecoratedBox(decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
                            colors: [Colors.transparent, Colors.black.withOpacity(0.08)]))),
                  ]),
                ),
              ),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Tag + date row
                        Row(children: [
                          _TagPill(tag: news.tag, style: ts),
                          const Spacer(),
                          _DateBadge(date: news.ngayDang, small: true),
                        ]),
                        const SizedBox(height: 7),
                        // Title
                        Text(news.tieuDe, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700,
                                height: 1.38, color: kText1, letterSpacing: -0.2)),
                        const SizedBox(height: 6),
                        // Author
                        Row(children: [
                          CircleAvatar(radius: 10,
                              backgroundColor: ts.bg,
                              child: Text(news.tacGia.isNotEmpty ? news.tacGia[0] : 'V',
                                  style: TextStyle(color: ts.text, fontSize: 9.5, fontWeight: FontWeight.w800))),
                          const SizedBox(width: 5),
                          Expanded(child: Text(news.tacGia, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kText3, fontSize: 11, fontWeight: FontWeight.w500))),
                          // Arrow
                          Container(width: 22, height: 22,
                              decoration: BoxDecoration(
                                  color: ts.bg, borderRadius: BorderRadius.circular(6)),
                              child: Icon(Icons.arrow_forward_ios_rounded,
                                  color: ts.text, size: 10)),
                        ]),
                      ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── Small reusable widgets ──────────────────────────

class _TagChip extends StatelessWidget {
  final String tag; final TagStyle style;
  const _TagChip({required this.tag, required this.style});
  @override Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: style.bg.withOpacity(0.92),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: style.text.withOpacity(0.2))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(style.icon, color: style.text, size: 11),
        const SizedBox(width: 4),
        Text(tag, style: TextStyle(color: style.text, fontSize: 11, fontWeight: FontWeight.w700)),
      ]));
}

class _TagPill extends StatelessWidget {
  final String tag; final TagStyle style;
  const _TagPill({required this.tag, required this.style});
  @override Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: style.bg, borderRadius: BorderRadius.circular(14)),
      child: Text(tag, style: TextStyle(color: style.text, fontSize: 10, fontWeight: FontWeight.w700)));
}

class _DateBadge extends StatelessWidget {
  final String date; final bool small;
  const _DateBadge({required this.date, this.small = false});
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.calendar_month_rounded,
        size: small ? 10 : 11,
        color: small ? kText3 : Colors.white70),
    const SizedBox(width: 3),
    Text(date, style: TextStyle(
        color: small ? kText3 : Colors.white,
        fontSize: small ? 10 : 11,
        fontWeight: FontWeight.w500)),
  ]);
}

class _AuthorChip extends StatelessWidget {
  final String name; final Color color;
  const _AuthorChip({required this.name, required this.color});
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    CircleAvatar(radius: 12, backgroundColor: color.withOpacity(0.1),
        child: Text(name.isNotEmpty ? name[0] : 'V',
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800))),
    const SizedBox(width: 6),
    Text(name, style: const TextStyle(color: kText2, fontSize: 12, fontWeight: FontWeight.w500)),
  ]);
}

class _ReadBtn extends StatelessWidget {
  final Color color;
  const _ReadBtn({required this.color});
  @override Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20)),
      child: const Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Đọc tiếp', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        SizedBox(width: 4),
        Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 13),
      ]));
}

class _ImgFallback extends StatelessWidget {
  final double height; final String tag;
  const _ImgFallback({required this.height, required this.tag});
  @override Widget build(BuildContext context) {
    final ts = _tagStyle(tag);
    return Container(
        height: height > 0 ? height : null,
        color: ts.bg,
        child: Center(child: Icon(ts.icon, color: ts.text.withOpacity(0.35), size: 40)));
  }
}


// ═══════════════════════════════════════════════════════
//  NEWS DETAIL SCREEN
// ═══════════════════════════════════════════════════════
class NewsDetailScreen extends StatelessWidget {
  final NewsItem news;
  const NewsDetailScreen({super.key, required this.news});

  @override
  Widget build(BuildContext context) {
    final ts = _tagStyle(news.tag);
    return Scaffold(
      backgroundColor: kSurface,
      body: CustomScrollView(slivers: [
        // ── Hero AppBar
        SliverAppBar(
          expandedHeight: 270, pinned: true,
          backgroundColor: kBlue1,
          elevation: 0,
          leading: Padding(padding: const EdgeInsets.all(9),
              child: GestureDetector(onTap: () => Navigator.pop(context),
                  child: Container(
                      decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 16)))),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(fit: StackFit.expand, children: [
              Image.network(news.hinhAnh, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [ts.text, ts.text.withOpacity(0.6)])),
                      child: Center(child: Icon(ts.icon, color: Colors.white.withOpacity(0.3), size: 64)))),
              // Multi-stop gradient for title readability
              DecoratedBox(decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      stops: const [0.0, 0.4, 1.0],
                      colors: [
                        Colors.black.withOpacity(0.05),
                        Colors.black.withOpacity(0.2),
                        Colors.black.withOpacity(0.78),
                      ]))),
              // Tag + title overlay
              Positioned(bottom: 20, left: 16, right: 16,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _TagChip(tag: news.tag, style: ts),
                    const SizedBox(height: 10),
                    Text(news.tieuDe, maxLines: 3, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 19,
                            fontWeight: FontWeight.w800, height: 1.3, letterSpacing: -0.4,
                            shadows: [Shadow(blurRadius: 12, color: Colors.black45)])),
                  ])),
            ]),
          ),
        ),

        // ── Content
        SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

          // ── Meta card
          Container(
              margin: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: kCard, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: kBlue1.withOpacity(0.05), blurRadius: 12, offset: const Offset(0,3))]),
              child: Row(children: [
                // Author avatar
                Container(width: 42, height: 42,
                    decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [ts.text, ts.text.withOpacity(0.7)]),
                        borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text(
                        news.tacGia.isNotEmpty ? news.tacGia[0] : 'V',
                        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(news.tacGia, style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: kText1)),
                  if (news.nguoiDang.isNotEmpty)
                    Text(news.nguoiDang, style: const TextStyle(fontSize: 11.5, color: kText3)),
                ])),
                // Date pill
                Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: ts.bg, borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.calendar_today_rounded, size: 11, color: ts.text),
                      const SizedBox(width: 4),
                      Text(news.ngayDang, style: TextStyle(
                          fontSize: 11.5, color: ts.text, fontWeight: FontWeight.w600)),
                    ])),
              ])),

          // ── Trích dẫn
          Container(
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: ts.bg.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: ts.text.withOpacity(0.15))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.format_quote_rounded, color: ts.text.withOpacity(0.5), size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(news.trichDan,
                    style: const TextStyle(color: kText2, fontSize: 13.5,
                        height: 1.6, fontStyle: FontStyle.italic))),
              ])),

          // ── Nội dung
          Container(
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: kCard, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: kBlue1.withOpacity(0.04), blurRadius: 10, offset: const Offset(0,3))]),
              child: news.noiDung.isNotEmpty
                  ? _buildContent(context, news.noiDung, ts)
                  : _buildPlaceholder(ts)),

          const SizedBox(height: 40),
        ])),
      ]),
    );
  }

  // ─── Content dispatcher ────────────────────────────
  Widget _buildContent(BuildContext ctx, String content, TagStyle ts) {
    final isHtml = content.trimLeft().startsWith('<')
        || content.contains('<p') || content.contains('<div') || content.contains('<img');
    if (isHtml) return _buildHtml(ctx, content, ts);
    return _buildPlainText(content, ts);
  }

  // ─── HTML renderer ─────────────────────────────────
  Widget _buildHtml(BuildContext ctx, String html, TagStyle ts) {
    final sw = MediaQuery.of(ctx).size.width - 28 - 32;

    // ── Pre-process HTML ─────────────────────────────
    // Fix all relative src/href - match both quote styles using \x27 for single quote
    String fixed = html
        .replaceAllMapped(
      RegExp(r'src=[\x22\x27](?!https?://)(/[^\x22\x27]*)[\x22\x27]'),
          (m) => 'src="$kImgBase${m[1]}"',
    )
        .replaceAllMapped(
      RegExp(r'href=[\x22\x27](?!https?://)(/[^\x22\x27]*)[\x22\x27]'),
          (m) => 'href="$kImgBase${m[1]}"',
    )
    // Strip Word namespaces
        .replaceAll(RegExp(r'</?o:[^>]*>'), '')
        .replaceAll(RegExp(r'</?w:[^>]*>'), '')
    // Remove empty spacer rows from Word
        .replaceAll(RegExp(
        r'<tr\b[^>]*>(?:\s*<td\b[^>]*>(?:\s*<p\b[^>]*>\s*(?:&nbsp;|\u00a0|\s)*</p>\s*|\s*(?:&nbsp;|\u00a0)\s*)*</td>\s*)+</tr>',
        caseSensitive: false), '')
    // Strip style attr from img (width:100% etc.) — TagExtension controls size
        .replaceAllMapped(
      RegExp(r'(<img\b[^>]*?)\s+style=[\x22\x27][^\x22\x27]*[\x22\x27]'),
          (m) => m[1]!,
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 3, height: 16,
            decoration: BoxDecoration(color: ts.text, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text('NỘI DUNG CHI TIẾT', style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w800,
            color: ts.text, letterSpacing: 1.3)),
      ]),
      const SizedBox(height: 14),
      Html(
        data: fixed,
        style: {
          'body': Style(
              fontSize: FontSize(14.5), lineHeight: LineHeight(1.72),
              color: kText1, margin: Margins.zero, padding: HtmlPaddings.zero),
          'p': Style(margin: Margins.only(bottom: 6), textAlign: TextAlign.justify),
          'b': Style(fontWeight: FontWeight.w700, color: kText1),
          'strong': Style(fontWeight: FontWeight.w700, color: kText1),
          'i': Style(fontStyle: FontStyle.italic, color: kText2),
          'em': Style(fontStyle: FontStyle.italic, color: kText2),
          'a': Style(color: ts.text, textDecoration: TextDecoration.none, fontWeight: FontWeight.w600),
          'h1': Style(fontSize: FontSize(20), fontWeight: FontWeight.w800,
              color: ts.text, margin: Margins.only(top: 18, bottom: 8), letterSpacing: -0.4),
          'h2': Style(fontSize: FontSize(17), fontWeight: FontWeight.w800,
              color: ts.text, margin: Margins.only(top: 14, bottom: 7), letterSpacing: -0.3),
          'h3': Style(fontSize: FontSize(15), fontWeight: FontWeight.w700,
              color: ts.text, margin: Margins.only(top: 12, bottom: 6)),
          'ul': Style(margin: Margins.only(left: 4, bottom: 10)),
          'ol': Style(margin: Margins.only(left: 4, bottom: 10)),
          'li': Style(margin: Margins.only(bottom: 5), fontSize: FontSize(14.5)),
          'table': Style(
              width: Width(sw), margin: Margins.symmetric(vertical: 8),
              border: Border.all(color: Colors.transparent)),
          'thead': Style(backgroundColor: ts.bg),
          'th': Style(
              padding: HtmlPaddings.symmetric(vertical: 8, horizontal: 6),
              fontWeight: FontWeight.w700, fontSize: FontSize(13),
              color: ts.text, border: Border.all(color: ts.text.withOpacity(0.15))),
          'td': Style(
              padding: HtmlPaddings.symmetric(vertical: 4, horizontal: 4),
              verticalAlign: VerticalAlign.top,
              border: Border.all(color: Colors.transparent)),
          'tr': Style(border: Border.all(color: Colors.transparent)),
          'div': Style(margin: Margins.zero, padding: HtmlPaddings.zero),
          'img': Style(display: Display.block, margin: Margins.only(bottom: 4), padding: HtmlPaddings.zero),
        },
        extensions: [
          TagExtension(
            tagsToExtend: {'img'},
            builder: (extCtx) {
              String src = extCtx.attributes['src'] ?? '';
              if (src.isEmpty) return const SizedBox.shrink();
              // Final safety: fix any remaining relative src
              if (!src.startsWith('http')) {
                src = '$kImgBase${src.startsWith('/') ? '' : '/'}$src';
              }
              // Walk up element tree to detect if inside <td>
              bool inCell = false;
              var el = extCtx.element?.parent;
              for (int i = 0; i < 6 && el != null; i++) {
                if (el.localName == 'td') { inCell = true; break; }
                el = el.parent;
              }
              final imgW = inCell ? (sw / 2 - 12) : sw;

              return Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.network(
                    src,
                    width: imgW,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, prog) {
                      if (prog == null) return child;
                      return Container(
                          height: 120, width: imgW,
                          color: ts.bg.withOpacity(0.4),
                          child: Center(child: CircularProgressIndicator(
                              strokeWidth: 2, color: ts.text,
                              value: prog.expectedTotalBytes != null
                                  ? prog.cumulativeBytesLoaded / prog.expectedTotalBytes!
                                  : null)));
                    },
                    errorBuilder: (_, __, ___) => Container(
                        height: 80, width: imgW,
                        color: ts.bg,
                        child: Center(child: Icon(Icons.broken_image_outlined,
                            color: ts.text.withOpacity(0.4), size: 28))),
                  ),
                ),
              );
            },
          ),
        ],
        onLinkTap: (url, _, __) async {
          if (url == null) return;
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      ),
    ]);
  }


  // ─── Plain text fallback ───────────────────────────
  Widget _buildPlainText(String content, TagStyle ts) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 3, height: 16,
            decoration: BoxDecoration(color: ts.text, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text('NỘI DUNG CHI TIẾT', style: TextStyle(
            fontSize: 10.5, fontWeight: FontWeight.w800,
            color: ts.text, letterSpacing: 1.3)),
      ]),
      const SizedBox(height: 14),
      ...content.split('\n\n').map((p) {
        final lines = p.trim().split('\n');
        final isHeader = lines.first.endsWith(':') && !lines.first.startsWith('•');
        if (isHeader) {
          return Padding(padding: const EdgeInsets.only(bottom: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: ts.bg, borderRadius: BorderRadius.circular(8)),
                    child: Text(lines.first, style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w800, color: ts.text))),
                ...lines.skip(1).map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 4),
                    child: Text(l.trim(), style: const TextStyle(
                        fontSize: 14.5, color: kText1, height: 1.65)))),
              ]));
        }
        return Padding(padding: const EdgeInsets.only(bottom: 12),
            child: Text(p.trim(),
                style: const TextStyle(fontSize: 14.5, color: kText1, height: 1.72)));
      }),
    ]);
  }

  // ─── No content placeholder ────────────────────────
  Widget _buildPlaceholder(TagStyle ts) => Column(children: [
    const SizedBox(height: 8),
    Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
            color: ts.bg.withOpacity(0.5), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Icon(ts.icon, color: ts.text.withOpacity(0.35), size: 48),
          const SizedBox(height: 12),
          Text('Nội dung đầy đủ\nsẽ được cập nhật sớm.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: kText3, fontSize: 13.5, height: 1.6)),
        ])),
  ]);
}


// ═══════════════════════════════════════════════════════
//  PAGINATION WIDGETS
// ═══════════════════════════════════════════════════════
class _PageChip extends StatelessWidget {
  final int number;
  final bool isActive;
  final VoidCallback onTap;
  const _PageChip({required this.number, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: isActive ? kBlue2 : kCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isActive ? kBlue2 : const Color(0xFFE2E8F0),
              width: isActive ? 0 : 1),
          boxShadow: isActive ? [BoxShadow(color: kBlue2.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3))] : [],
        ),
        child: Center(child: Text('$number',
            style: TextStyle(
                color: isActive ? Colors.white : kText2,
                fontSize: 13, fontWeight: isActive ? FontWeight.w800 : FontWeight.w500))),
      ),
    );
  }
}

class _PageEllipsis extends StatelessWidget {
  const _PageEllipsis();
  @override Widget build(BuildContext context) => const SizedBox(
      width: 28, height: 36,
      child: Center(child: Text('…', style: TextStyle(color: kText3, fontSize: 14))));
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  const _NavBtn({required this.icon, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: enabled ? kCard : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: enabled ? const Color(0xFFE2E8F0) : Colors.transparent),
        boxShadow: enabled ? [BoxShadow(color: kBlue1.withOpacity(0.06), blurRadius: 6, offset: const Offset(0,2))] : [],
      ),
      child: Center(child: Icon(icon,
          color: enabled ? kText1 : kText3, size: 20)),
    ),
  );
}

// ═══════════════════════════════════════════════════════
//  HELPER WIDGETS
// ═══════════════════════════════════════════════════════
class _Loader extends StatelessWidget {
  const _Loader();
  @override Widget build(BuildContext context) => Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(width: 52, height: 52,
        decoration: BoxDecoration(
            color: kCard, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: kBlue1.withOpacity(0.1), blurRadius: 16, offset: const Offset(0,4))]),
        child: const Center(child: SizedBox(width: 26, height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: kBlue2)))),
    const SizedBox(height: 14),
    const Text('Đang tải tin tức...', style: TextStyle(color: kText3, fontSize: 13)),
  ]);
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});
  @override Widget build(BuildContext context) => Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.wifi_off_rounded, color: Color(0xFFB91C1C), size: 44)),
        const SizedBox(height: 18),
        const Text('Không thể tải tin tức',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText1)),
        const SizedBox(height: 6),
        const Text('Kiểm tra kết nối mạng và thử lại',
            style: TextStyle(color: kText3, fontSize: 13)),
        const SizedBox(height: 24),
        GestureDetector(
            onTap: onRetry,
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kBlue1, kBlue2]),
                    borderRadius: BorderRadius.circular(14)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Thử lại', style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ]))),
      ])));
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override Widget build(BuildContext context) => Center(child: Column(
      mainAxisAlignment: MainAxisAlignment.center, children: [
    Container(padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.newspaper_rounded, color: kBlue2, size: 44)),
    const SizedBox(height: 16),
    const Text('Chưa có tin tức nào',
        style: TextStyle(color: kText2, fontSize: 15, fontWeight: FontWeight.w600)),
  ]));
}

class _EmptySearch extends StatelessWidget {
  final String keyword;
  const _EmptySearch({required this.keyword});
  @override Widget build(BuildContext context) => Center(child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.search_off_rounded, color: kBlue3, size: 44)),
        const SizedBox(height: 16),
        const Text('Không tìm thấy kết quả',
            style: TextStyle(color: kText1, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('cho "$keyword"',
            style: const TextStyle(color: kText3, fontSize: 13)),
      ])));
}