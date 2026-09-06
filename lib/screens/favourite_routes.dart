import 'package:flutter/material.dart';

import '../services/personal_travel_service.dart';

class FavouriteRoutesScreen extends StatefulWidget {
  const FavouriteRoutesScreen({
    super.key,
    this.repository,
    this.sheetMode = false,
    this.onAddRoute,
  });

  final SavedRoutesRepository? repository;
  final bool sheetMode;
  final VoidCallback? onAddRoute;

  @override
  State<FavouriteRoutesScreen> createState() => _FavouriteRoutesScreenState();
}

class _FavouriteRoutesScreenState extends State<FavouriteRoutesScreen> {
  late final SavedRoutesRepository _repository;
  List<SavedRoute> _routes = [];
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SupabaseSavedRoutesRepository();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final routes = await _repository.load();
      if (mounted) setState(() => _routes = routes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _rename(SavedRoute route) async {
    final name = await showRouteNameDialog(context, initialName: route.name);
    if (name == null || !mounted) return;
    await _mutate(() => _repository.rename(route.id!, name));
  }

  Future<void> _delete(SavedRoute route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove favourite?'),
        content: Text(route.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _mutate(() => _repository.delete(route.id!));
  }

  Future<void> _mutate(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      if (mounted) await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to update favourites. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sheetMode) return _buildSheet();
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7FC),
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Favourite Routes',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Unable to load favourites. Please try again.',
                      textAlign: TextAlign.center,
                    ),
                    TextButton(onPressed: _load, child: Text('Retry')),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bookmarks_outlined,
                          color: Colors.white,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your everyday journeys',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_routes.length} ${'saved routes'}',
                                style: const TextStyle(
                                  color: Color(0xFFDBEAFE),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_saving) const LinearProgressIndicator(),
                  if (_routes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 64,
                        horizontal: 16,
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.favorite_border,
                            size: 48,
                            color: Color(0xFF2563EB),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No favourite routes yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Find a route in Journey and tap Save route.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: const Text(
                        'Plan again to refresh departure times and available routes.',
                      ),
                    ),
                    for (final route in _routes) _buildRouteCard(route),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSheet() {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFD8DEE8),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Favourite Routes',
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: widget.onAddRoute,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2862E9),
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text(
                    'Add Route',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF1F4F8),
                    foregroundColor: const Color(0xFF94A0B2),
                    minimumSize: const Size(34, 34),
                    maximumSize: const Size(34, 34),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8EDF4)),
          Expanded(child: _buildSheetBody()),
        ],
      ),
    );
  }

  Widget _buildSheetBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Unable to load favourites. Please try again.',
              textAlign: TextAlign.center,
            ),
            TextButton(onPressed: _load, child: Text('Retry')),
          ],
        ),
      );
    }
    if (_routes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFECEE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_border_rounded,
                  color: Color(0xFFEF4E5B),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No favourite routes yet',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Find a route in Journey and tap Save route.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF7B879A), fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _routes.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) => _buildCompactRouteCard(_routes[index]),
      ),
    );
  }

  Widget _buildCompactRouteCard(SavedRoute route) {
    final line = _lineDetails(route.lineName);
    return Material(
      color: const Color(0xFFF7F9FC),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: _saving ? null : () => Navigator.pop(context, route),
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _compactEndpoint(
                      route.origin.name,
                      const Color(0xFF9AA8BC),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 3.5),
                      child: Container(
                        width: 1,
                        height: 10,
                        color: const Color(0xFFD3DAE5),
                      ),
                    ),
                    _compactEndpoint(
                      route.destination.name,
                      const Color(0xFFEF4E5B),
                    ),
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: line.$2,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        line.$1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Rename',
                onPressed: _saving ? null : () => _rename(route),
                icon: const Icon(
                  Icons.edit_outlined,
                  color: Color(0xFF2862E9),
                  size: 18,
                ),
              ),
              IconButton.filled(
                tooltip: 'Delete',
                onPressed: _saving ? null : () => _delete(route),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFFECEE),
                  foregroundColor: const Color(0xFFEF4E5B),
                  minimumSize: const Size(34, 34),
                  maximumSize: const Size(34, 34),
                  padding: EdgeInsets.zero,
                ),
                icon: const Icon(Icons.delete_outline_rounded, size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactEndpoint(String name, Color color) {
    return Row(
      children: [
        Icon(Icons.circle, color: color, size: 8),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF435168),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  (String, Color) _lineDetails(String lineName) {
    final upper = lineName.toUpperCase();
    if (upper.contains('KELANA') || upper.contains('KJL')) {
      return ('KJ', const Color(0xFFEF4E5B));
    }
    if (upper.contains('PUTRAJAYA') || upper.contains('PYL')) {
      return ('PY', const Color(0xFF16A394));
    }
    if (upper.contains('KAJANG') || upper.contains('KGL')) {
      return ('KG', const Color(0xFF3C9B5F));
    }
    if (upper.contains('MONORAIL') || upper.contains('MRL')) {
      return ('MR', const Color(0xFFE08A13));
    }
    if (upper.contains('AMPANG') || upper.contains('AGL')) {
      return ('AG', const Color(0xFFE77928));
    }
    if (RegExp(r'\bT\d+\b').hasMatch(upper) || upper.contains('BUS')) {
      return ('BUS', const Color(0xFF2862E9));
    }
    return ('PT', const Color(0xFF64748B));
  }

  Widget _buildRouteCard(SavedRoute route) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.favorite,
                  color: Color(0xFF2563EB),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  route.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_saving,
                tooltip: 'Route options',
                onSelected: (action) =>
                    action == 'rename' ? _rename(route) : _delete(route),
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Color(0xFFF1F5F9)),
          ),
          _endpoint(
            'From',
            route.origin.name,
            const Color(0xFF2563EB),
            Icons.radio_button_checked,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
            child: Container(
              width: 2,
              height: 18,
              color: const Color(0xFFCBD5E1),
            ),
          ),
          _endpoint(
            'To',
            route.destination.name,
            const Color(0xFFEF4444),
            Icons.location_on_outlined,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.directions_transit,
                  size: 16,
                  color: Color(0xFF475569),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    route.lineName,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _saving ? null : () => Navigator.pop(context, route),
              icon: const Icon(Icons.route, size: 20),
              label: Text(
                'Plan again',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _endpoint(String label, String name, Color color, IconData icon) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  name,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

Future<String?> showRouteNameDialog(
  BuildContext context, {
  required String initialName,
}) => showDialog<String>(
  context: context,
  builder: (_) => _RouteNameDialog(initialName: initialName),
);

class _RouteNameDialog extends StatefulWidget {
  const _RouteNameDialog({required this.initialName});
  final String initialName;

  @override
  State<_RouteNameDialog> createState() => _RouteNameDialogState();
}

class _RouteNameDialogState extends State<_RouteNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Route name'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textInputAction: TextInputAction.done,
        onFieldSubmitted: (_) => _submit(),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Enter a route name.'
            : null,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: Text('Save')),
    ],
  );
}
