import Stripe from "stripe";

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const plans = [
  {
    name: "Novice",
    description: "Even if you play 3 hours every day for a month, you'll never hit a limit.",
    amount: 100,
    runs: 5000,
  },
  {
    name: "Scout",
    description: "Even if you play 6 hours every day for a month, you'll never hit a limit.",
    amount: 200,
    runs: 10000,
  },
  {
    name: "Adventurer",
    description: "Even if you play 12 hours every day for a month, you'll never hit a limit.",
    amount: 400,
    runs: 20000,
  },
];

async function setup() {
  console.log("Creating LeatherArmor Stripe products...\n");

  for (const plan of plans) {
    const product = await stripe.products.create({
      name: plan.name,
      description: plan.description,
      metadata: {
        monthly_runs: String(plan.runs),
      },
    });

    const price = await stripe.prices.create({
      product: product.id,
      unit_amount: plan.amount,
      currency: "usd",
      recurring: { interval: "month" },
      metadata: {
        monthly_runs: String(plan.runs),
      },
    });

    console.log(`✓ ${plan.name}`);
    console.log(`  Product ID : ${product.id}`);
    console.log(`  Price ID   : ${price.id}`);
    console.log(`  Amount     : $${(plan.amount / 100).toFixed(2)}/mo`);
    console.log(`  Runs       : ${plan.runs.toLocaleString()}\n`);
  }

  console.log("Done. Save the Price IDs above — you will need them in your backend to identify which plan a subscriber is on.");
}

setup().catch((err) => {
  console.error("Stripe error:", err.message);
  process.exit(1);
});