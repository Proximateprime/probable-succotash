// Supabase Edge Function: stripe-webhook
// Receives Stripe webhook events and updates profiles.tier on successful payment.
//
// Required environment variables (set in Supabase Dashboard > Settings > Secrets):
//   STRIPE_SECRET_KEY        — your Stripe sk_live_... or sk_test_... key
//   STRIPE_WEBHOOK_SECRET    — whsec_... from stripe.com/webhooks (your endpoint signing secret)
//   SUPABASE_URL             — auto-injected by Supabase
//   SUPABASE_SERVICE_ROLE_KEY — auto-injected by Supabase
//
// In Stripe Dashboard > Webhooks, add your endpoint:
//   https://spucayasxeedutdpcrqg.supabase.co/functions/v1/stripe-webhook
// Listen for: checkout.session.completed, customer.subscription.deleted
//
// Deploy with:
//   supabase functions deploy stripe-webhook

import Stripe from 'https://esm.sh/stripe@14?target=deno';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2?target=deno';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') ?? '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
});

const supabase = createClient(
  Deno.env.get('SUPABASE_URL') ?? '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
);

Deno.serve(async (req: Request) => {
  const sig = req.headers.get('stripe-signature');
  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') ?? '';

  if (!sig || !webhookSecret) {
    return new Response('Missing signature or webhook secret', { status: 400 });
  }

  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, sig, webhookSecret);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return new Response(`Webhook signature verification failed: ${message}`, { status: 400 });
  }

  if (event.type === 'checkout.session.completed') {
    const session = event.data.object as Stripe.Checkout.Session;
    const userId = session.metadata?.user_id;
    const tier = session.metadata?.tier;

    if (!userId || !tier) {
      console.error('Missing metadata on checkout session:', session.id);
      return new Response('Missing metadata', { status: 400 });
    }

    const role = tier === 'corporate' ? 'corporate_admin' : 'hobbyist';

    const { error } = await supabase
      .from('profiles')
      .update({ tier, role })
      .eq('id', userId);

    if (error) {
      console.error('Failed to update profile tier:', error.message);
      return new Response('DB update failed', { status: 500 });
    }

    console.log(`Updated user ${userId} to tier ${tier}`);
  }

  if (event.type === 'customer.subscription.deleted') {
    const subscription = event.data.object as Stripe.Subscription;
    const userId = subscription.metadata?.user_id;

    if (userId) {
      await supabase
        .from('profiles')
        .update({ tier: 'hobbyist', role: 'hobbyist' })
        .eq('id', userId);
      console.log(`Subscription cancelled — reset user ${userId} to hobbyist`);
    }
  }

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
});
