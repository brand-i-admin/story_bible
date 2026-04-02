class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.pageIndex,
    required this.pageSize,
    required this.hasNextPage,
  });

  final List<T> items;
  final int pageIndex;
  final int pageSize;
  final bool hasNextPage;
}
