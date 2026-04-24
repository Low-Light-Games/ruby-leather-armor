// Idempotent Stripe product/price setup for LeatherArmor.
// Reads config/stripe_plans.yml as sole source of truth.
// Rewrites the YAML with up-to-date IDs after each run.
// Run with: node --env-file=.env scripts/stripe/setup-products.mjs

import Stripe from "stripe";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PLANS_PATH = path.resolve(__dirname, "../../config/stripe_plans.yml");

function parseYml(content) {
  const result = {};
  let currentKey = null;
  for (const line of content.split("\n")) {
    const topLevel = line.match(/^(\w+):$/);
    if (topLevel) { currentKey = topLevel[1]; result[currentKey] = {}; continue; }
    const field = line.match(/^\s+(\w+)\s*:\s*(.+)$/);
    if (field && currentKey) result[currentKey][field[1].trim()] = field[2].trim().replace(/^"|"$/g, "");
  }
  return result;
}

function buildYml(config) {
  const lines = [];
  for (const [tier, values] of Object.entries(config)) {
    lines.push(`${tier}:`);
    for (const [k, v] of Object.entries(values)) {
      const val = String(v).includes(" ") ? `"${v}"` : v;
      lines.push(`  ${k.padEnd(20)}: ${val}`);
    }
    lines.push("");
  }
  return lines.join("\n");
}

async function archiveOldPrices(productId, keepPriceId) {
  const prices = await stripe.prices.list({ product: productId, active: true, limit: 100 });
  for (const price of prices.data) {
    if (price.id !== keepPriceId) {
      await stripe.prices.update(price.id, { active: false });
      console.log(`  Archived old price ${price.id}`);
    }
  }
}

async function setup() {
  console.log("Reading stripe_plans.yml...\n");
  const yml = parseYml(fs.readFileSync(PLANS_PATH, "utf8"));

  for (const [tier, plan] of Object.entries(yml)) {
    // Skip free tier — no Stripe product needed
    if (!plan.amount) continue;

    const existingProductId = plan.stripe_product_id !== "null" ? plan.stripe_product_id : null;
    const existingPriceId = plan.stripe_price_id !== "null" ? plan.stripe_price_id : null;
    const amount = parseInt(plan.amount, 10);
    const name = tier.charAt(0).toUpperCase() + tier.slice(1);

    // Sync product
    let product;
    if (existingProductId) {
      product = await stripe.products.update(existingProductId, {
        name,
        description: plan.description,
      });
      console.log(`↻ ${name} (updated)`);
    } else {
      product = await stripe.products.create({
        name,
        description: plan.description,
      });
      console.log(`✓ ${name} (created)`);
    }

    // Sync price
    let price;
    if (existingPriceId) {
      const existing = await stripe.prices.retrieve(existingPriceId);
      if (existing.unit_amount === amount && existing.active) {
        price = existing;
        console.log(`  Price unchanged — $${(amount / 100).toFixed(2)}/mo`);
      } else {
        price = await stripe.prices.create({
          product: product.id,
          unit_amount: amount,
          currency: "usd",
          recurring: { interval: "month" },
        });
        await archiveOldPrices(product.id, price.id);
        console.log(`  New price created — $${(amount / 100).toFixed(2)}/mo`);
      }
    } else {
      price = await stripe.prices.create({
        product: product.id,
        unit_amount: amount,
        currency: "usd",
        recurring: { interval: "month" },
      });
      console.log(`  Price created — $${(amount / 100).toFixed(2)}/mo`);
    }

    yml[tier].stripe_product_id = product.id;
    yml[tier].stripe_price_id = price.id;

    console.log(`  Product ID : ${product.id}`);
    console.log(`  Price ID   : ${price.id}\n`);
  }

  fs.writeFileSync(PLANS_PATH, buildYml(yml));
  console.log("stripe_plans.yml updated.");
}

setup().catch((err) => {
  console.error("Stripe error:", err.message);
  process.exit(1);
});
