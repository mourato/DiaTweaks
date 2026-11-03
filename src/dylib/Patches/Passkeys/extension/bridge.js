window.addEventListener('message', (event) => {
  if (event.source !== window || event.data?.diaTweaksPasskey !== 'request') return;
  const { id, kind, options } = event.data;
  chrome.runtime.sendMessage({ kind, options }, (response) => window.postMessage({ diaTweaksPasskey: 'response', id, response }, '*'));
});
