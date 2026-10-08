const String faDocumentOuterHtmlScript =
    'document.documentElement.outerHTML;';

const String faDocumentBodyScrollHeightScript =
    'document.body.scrollHeight.toString()';

String faRetryFailedImagesScript(int revision) => '''
(() => {
  const revision = $revision;
  if ((window.__faMediaSessionRevision ?? -1) > revision) return;
  window.__faMediaSessionRevision = revision;
  document.querySelectorAll('img').forEach((image) => {
    if (image.dataset.faGifPaused === '1') return;
    const source = image.getAttribute('src');
    if (!source) return;
    let uri;
    try { uri = new URL(source, document.baseURI); } catch (_) { return; }
    if (uri.protocol !== 'https:' ||
        !(uri.hostname === 'furaffinity.net' ||
          uri.hostname.endsWith('.furaffinity.net'))) return;
    const retry = () => {
      if (window.__faMediaSessionRevision !== revision ||
          image.dataset.faMediaRetryRevision === String(revision) ||
          image.dataset.faGifPaused === '1' ||
          image.getAttribute('src') !== source) return;
      image.dataset.faMediaRetryRevision = String(revision);
      image.src = source;
    };
    if (image.complete) {
      if (image.naturalWidth === 0) retry();
    } else if (image.dataset.faMediaWaitingRevision !== String(revision)) {
      image.dataset.faMediaWaitingRevision = String(revision);
      image.addEventListener('error', retry, { once: true });
    }
  });
})();
''';
