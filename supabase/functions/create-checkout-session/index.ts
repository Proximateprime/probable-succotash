// Supabase Edge Function: create-checkout-session
// Creates a Stripe Checkout Session and returns the URL for redirect.
//
// Required environment variables (set in Supabase Dashboard > Settings > Secrets):
//   STRIPE_SECRET_KEY   — your Stripe sk_live_... or sk_test_... key
//   APP_URL             — your app deep-link base, e.g. covertrack://
//
// Deploy with:
//   supabase functions deploy create-checkout-session

import Stripe from 'https://esm.sh/stripe@14?target=deno';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

// Map plan+period to your real Stripe Price IDs from the dashboard.
// Fill these in after creating Products/Prices in stripe.com/products
const PRICE_IDS: Record<string, string> = {
  'hobbyist|lifetime':             'price_REPLACE_hobbyist_lifetime',
  'solo_professional|monthly':     'price_REPLACE_solo_monthly',
  'solo_professional|lifetime':    'price_REPLACE_solo_lifetime',
  'premium_solo|monthly':          'price_REPLACE_premium_monthly',
  'premium_solo|lifetime':         'price_REPLACE_premium_lifetime',
  'individual_large_land|monthly': 'price_REPLACE_large_monthly',
  'individual_large_land|lifetime':'price_REPLACE_large_lifetime',
  'corporate|monthly':             'price_REPLACE_corp_monthly',
  'corporate|lifetime':            'price_REPLACE_corp_lifetime',
};

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'Missing Authorization header' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  let body: { tier: string; billing_period: string; user_email: string; user_id: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON body' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const { tier, billing_period, user_email, user_id } = body;
  if (!tier || !billing_period || !user_email || !user_id) {
    return new Response(JSON.stringify({ error: 'Missing required fields' }), {
      status: 400,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  const priceKey = `${tier}|${billing_period}`;
  const priceId = PRICE_IDS[priceKey];
  if (!priceId || priceId.startsWith('price_REPLACE')) {
    return new Response(
      JSON.stringify({ error: `Stripe price not configured for: ${priceKey}` }),
      { status: 400, headers: { 'Content-Type': 'application/json' } },
    );
  }

  const appUrl = Deno.env.get('APP_URL') ?? 'covertrack://';
  const mode = billing_period === 'monthly' ? 'subscription' : 'payment';

  try {
    const session = await stripe.checkout.sessions.create({
      mode,
      line_items: [{ price: priceId, quantity: 1 }],
      customer_email: user_email,
      metadata: { user_id, tier, billing_period },
      success_url: `${appUrl}payment-success?session_id={CHECKOUT_SESSION_ID}`,
      cancel_url: `${appUrl}payment-cancelled`,
    });

    return new Response(JSON.stringify({ url: session.url }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
