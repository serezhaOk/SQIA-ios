// Stands in for the web app's auth module while generating fixtures: the
// pure functions we sample from projects.ts never touch the database, and
// building a real client would need browser globals and the network.
const reject = () => {
  throw new Error('fixture generation must not reach the network');
};

export const supabase = new Proxy({}, { get: reject });
