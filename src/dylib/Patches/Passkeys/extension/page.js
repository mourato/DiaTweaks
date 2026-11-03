(() => {
  const credentials = navigator.credentials;
  const create = credentials.create.bind(credentials);
  const get = credentials.get.bind(credentials);
  let nextId = 0;
  let pending = false;

  const b64 = (buffer) => {
    const bytes = new Uint8Array(ArrayBuffer.isView(buffer) ? buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength) : buffer);
    return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  };
  const bytes = (text) => Uint8Array.from(atob(text.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0)).buffer;

  const toJSON = (value) => {
    if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) return b64(value);
    if (Array.isArray(value)) return value.map(toJSON);
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, toJSON(v)]));
    return value;
  };

  const own = (proto, fields) => Object.defineProperties(Object.create(proto), Object.fromEntries(Object.entries(fields).map(([k, value]) => [k, { value, enumerable: true }])));

  const toCredential = (json) => {
    const r = json.response;
    const response = r.attestationObject
      ? own(AuthenticatorAttestationResponse.prototype, {
          clientDataJSON: bytes(r.clientDataJSON),
          attestationObject: bytes(r.attestationObject),
          getAuthenticatorData: () => bytes(r.authenticatorData),
          getPublicKey: () => (r.publicKey ? bytes(r.publicKey) : null),
          getPublicKeyAlgorithm: () => r.publicKeyAlgorithm,
          getTransports: () => r.transports ?? [],
        })
      : own(AuthenticatorAssertionResponse.prototype, {
          clientDataJSON: bytes(r.clientDataJSON),
          authenticatorData: bytes(r.authenticatorData),
          signature: bytes(r.signature),
          userHandle: r.userHandle ? bytes(r.userHandle) : null,
        });
    return own(PublicKeyCredential.prototype, {
      id: json.id,
      rawId: bytes(json.rawId),
      type: json.type,
      authenticatorAttachment: json.authenticatorAttachment ?? null,
      response,
      getClientExtensionResults: () => json.clientExtensionResults ?? {},
      toJSON: () => json,
    });
  };

  const ask = (kind, options) =>
    new Promise((resolve, reject) => {
      if (pending) return reject(new DOMException('A request is already pending.', 'OperationError'));
      pending = true;
      const id = ++nextId;
      const listen = (event) => {
        if (event.source !== window || event.data?.diaTweaksPasskey !== 'response' || event.data.id !== id) return;
        window.removeEventListener('message', listen);
        pending = false;
        const { credential, error } = event.data.response ?? {};
        if (credential) resolve(toCredential(credential));
        else reject(new DOMException(error?.message ?? 'The passkey request failed.', error?.name ?? 'NotAllowedError'));
      };
      window.addEventListener('message', listen);
      window.postMessage({ diaTweaksPasskey: 'request', id, kind, options: toJSON(options) }, '*');
    });

  // Autofill would start the other Dia on every page load.
  credentials.create = (options) => (options?.publicKey ? ask('create', options.publicKey) : create(options));
  credentials.get = (options) => (options?.publicKey && options.mediation !== 'conditional' ? ask('get', options.publicKey) : get(options));
  PublicKeyCredential.isConditionalMediationAvailable = () => Promise.resolve(false);
  PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable = () => Promise.resolve(true);
})();
