// delete-account — Guideline 5.1.1(v): an account made in the app has to be
// closable from the app.
//
// Deploy from the project root:
//
//     supabase functions deploy delete-account
//
// It needs the service-role key, which Supabase already puts in the function
// environment as SUPABASE_SERVICE_ROLE_KEY. That key can delete any user, so
// the only thing standing between a caller and someone else's account is the
// check below: the account deleted is the one the caller's own JWT is for,
// never one named in the request. There is no request body, on purpose —
// there is nothing a caller could say that would be listened to.
//
// `profiles` and `projects` both reference `auth.users (id) on delete
// cascade`, so removing the user takes the rows with it.

import { createClient } from 'jsr:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply(405, { message: 'Use POST' });

  const authorization = req.headers.get('Authorization') ?? '';
  const jwt = authorization.replace(/^Bearer\s+/i, '');
  if (!jwt) return reply(401, { message: 'Not signed in' });

  const url = Deno.env.get('SUPABASE_URL')!;
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // Who the caller is, according to the server rather than the request.
  const asCaller = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data: who, error: whoFailed } = await asCaller.auth.getUser();
  if (whoFailed || !who.user) {
    return reply(401, { message: whoFailed?.message ?? 'Not signed in' });
  }

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { error } = await admin.auth.admin.deleteUser(who.user.id);
  if (error) return reply(500, { message: error.message });

  return reply(200, { deleted: who.user.id });
});
