export function notificationBanner(value) {
  if (!value || typeof value.id !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value.id)) return null;
  if (!['source', 'title', 'body'].every(key => typeof value[key] === 'string')) return null;
  const clean = (text, limit) => [...text].slice(0, limit).join('').replace(/[\u0000-\u0009\u000b-\u001f\u007f]/g, '');
  return { id: value.id, source: clean(value.source, 80), title: clean(value.title, 160), body: clean(value.body, 360) };
}
