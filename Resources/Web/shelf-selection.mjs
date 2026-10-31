export function selectShelfItem(ids, selected, anchor, id, { toggle = false, range = false } = {}) {
  const index = ids.indexOf(id);
  if (index < 0) return { selected: new Set(selected), anchor };
  if (range && ids.includes(anchor)) {
    const from = ids.indexOf(anchor);
    const rangeIds = ids.slice(Math.min(from, index), Math.max(from, index) + 1);
    return { selected: new Set(toggle ? [...selected, ...rangeIds] : rangeIds), anchor };
  }
  if (toggle) {
    const result = new Set(selected);
    if (result.has(id)) result.delete(id); else result.add(id);
    return { selected: result, anchor: id };
  }
  return { selected: new Set([id]), anchor: id };
}
