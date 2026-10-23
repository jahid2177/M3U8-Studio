class Channel {
  const Channel({
    required this.name,
    required this.url,
    this.group = '',
    this.logo = '',
    this.epgId = '',
    this.source = '',
  });

  final String name;
  final String url;
  final String group;
  final String logo;
  final String epgId;
  final String source;

  Channel copyWith({String? name}) => Channel(
        name: name ?? this.name,
        url: url,
        group: group,
        logo: logo,
        epgId: epgId,
        source: source,
      );

  String toM3u() {
    String safe(String value) => value.replaceAll('"', '').replaceAll('\n', ' ');
    return '#EXTINF:-1 tvg-id="${safe(epgId)}" '
        'tvg-logo="${safe(logo)}" group-title="${safe(group)}",'
        '${name.replaceAll('\n', ' ')}\n$url';
  }
}
