chrome.runtime.onMessage.addListener((request, sender, reply) => {
  const origin = new URL(sender.url).origin;
  chrome.runtime.sendNativeMessage('com.diapatches.passkeys', { ...request, origin }, (response) =>
    reply(response ?? { error: { name: 'NotAllowedError', message: chrome.runtime.lastError?.message ?? 'No reply from diapatch' } }),
  );
  return true;
});
