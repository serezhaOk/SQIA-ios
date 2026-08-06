// Node ESM resolver hook so the web sources can be imported unmodified.
//
// The web app is built by Vite, which resolves extensionless relative imports
// ("./scales"). Node's ESM resolver does not, so it refuses to load grid.ts.
// Appending the extension here means the fixture generator reads the real
// files rather than a copy that could drift away from them.

// `projects.ts` pulls in `auth.ts` only for the Supabase handle, and that
// module builds a real client against browser globals at import time. The
// fixtures need `randomName` from the real file, not the network, so the
// import is swapped for a stub.
const STUBS = new Map([['./auth', './stubs/auth.mjs']]);

export function resolve(specifier, context, next) {
  const stub = STUBS.get(specifier);
  if (stub) return next(new URL(stub, import.meta.url).href, context);
  if (specifier.startsWith('.') && !/\.[a-z]+$/i.test(specifier)) {
    return next(`${specifier}.ts`, context);
  }
  return next(specifier, context);
}
