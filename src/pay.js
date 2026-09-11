/* الدفع عبر PayPal: إنشاء طلب دفع، ثم تحصيله عند عودة صاحبه، ثم تفعيل
   الاشتراك تلقائيا. لا مفتاح في الشيفرة: PAYPAL_CLIENT_ID وPAYPAL_SECRET
   من أسرار Cloudflare، وPAYPAL_ENV = "live" أو "sandbox". */
import { rpc } from "./notify.js";

/* الريال مربوط بالدولار عند 3.75، وPayPal يحصل بالدولار. */
const SAR_PER_USD = 3.75;

function base(env) {
  return String(env.PAYPAL_ENV || "sandbox") === "live"
    ? "https://api-m.paypal.com"
    : "https://api-m.sandbox.paypal.com";
}

export function payConfigured(env) {
  return !!(env.PAYPAL_CLIENT_ID && env.PAYPAL_SECRET);
}

async function token(env) {
  const auth = btoa(`${env.PAYPAL_CLIENT_ID}:${env.PAYPAL_SECRET}`);
  const res = await fetch(`${base(env)}/v1/oauth2/token`, {
    method: "POST",
    headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: "grant_type=client_credentials",
  });
  if (!res.ok) throw new Error("paypal token " + res.status);
  const j = await res.json();
  return j.access_token;
}

function usd(amountSar) {
  return (Math.round((Number(amountSar) / SAR_PER_USD) * 100) / 100).toFixed(2);
}

/* يبدأ الدفع: المبلغ يحسب في القاعدة من جدول الباقات (الاساس + 15% ضريبة حين
   الباقة بلا ضريبة)، لا يرسله المتصفح. */
export async function payCreate(env, user, body, origin) {
  const org = String(body.org || "").trim();
  const plan = String(body.plan || "").trim();
  const period = body.period === "yearly" ? "yearly" : "monthly";
  if (!org || !plan) return { error: "org and plan required", status: 400 };

  const started = await rpc(env, "pay_start", {
    p_secret: env.WORKER_SECRET, p_user: user.id, p_org: org, p_plan: plan, p_period: period,
  });
  const amountSar = Number(started && started.amount_sar);
  const baseSar = Number(started && started.base_sar);
  const vatSar = Number(started && started.vat_sar) || 0;
  const paymentId = started && started.payment_id;
  if (!paymentId || !isFinite(amountSar)) return { error: "could not start payment", status: 400 };

  /* المبلغ المرسل الى PayPal هو الكامل (الاساس + الضريبة). تفصيل الضريبة يرسل
     ايضا كي يظهر في ايصال PayPal، وبقية القسمة بالدولار تقع في الضريبة لا في
     الاساس حتى يطابق المجموع القيمة بالسنت. */
  const totalUsd = usd(amountSar);
  const amount = { currency_code: "USD", value: totalUsd };
  if (vatSar > 0 && isFinite(baseSar)) {
    const baseUsd = usd(baseSar);
    const taxUsd = (Math.round((Number(totalUsd) - Number(baseUsd)) * 100) / 100).toFixed(2);
    amount.breakdown = {
      item_total: { currency_code: "USD", value: baseUsd },
      tax_total: { currency_code: "USD", value: taxUsd },
    };
  }

  const t = await token(env);
  const res = await fetch(`${base(env)}/v2/checkout/orders`, {
    method: "POST",
    headers: { Authorization: `Bearer ${t}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      intent: "CAPTURE",
      purchase_units: [{
        custom_id: paymentId,
        description: `MrZahi ${plan} ${period}` + (vatSar > 0 ? " (incl. 15% VAT)" : ""),
        amount,
      }],
      application_context: {
        brand_name: "MrZahi",
        user_action: "PAY_NOW",
        return_url: `${origin}/api/pay/paypal/return`,
        cancel_url: `${origin}/app/settings.html#subscriptionCard`,
      },
    }),
  });
  if (!res.ok) return { error: "paypal order " + res.status, status: 502 };
  const order = await res.json();
  const approve = (order.links || []).filter((l) => l.rel === "approve")[0];
  if (!order.id || !approve) return { error: "no approval link", status: 502 };

  await rpc(env, "pay_mark_order", { p_secret: env.WORKER_SECRET, p_payment: paymentId, p_order: order.id });
  return { url: approve.href, order: order.id, amount_sar: amountSar, base_sar: baseSar, vat_sar: vatSar, amount_usd: totalUsd };
}

/* عودة الدافع: نحصل الطلب، ثم تفعل القاعدة الاشتراك في المعاملة نفسها. */
export async function payReturn(env, url, origin) {
  const order = url.searchParams.get("token") || "";
  const back = (q) => Response.redirect(`${origin}/app/settings.html?pay=${q}#subscriptionCard`, 302);
  if (!order) return back("missing");
  try {
    const t = await token(env);
    const res = await fetch(`${base(env)}/v2/checkout/orders/${encodeURIComponent(order)}/capture`, {
      method: "POST",
      headers: { Authorization: `Bearer ${t}`, "Content-Type": "application/json" },
    });
    const j = await res.json().catch(() => ({}));
    const ok = res.ok && String(j.status || "").toUpperCase() === "COMPLETED";
    if (!ok) return back("failed");
    const cap = (((j.purchase_units || [])[0] || {}).payments || {}).captures || [];
    const amt = cap[0] && cap[0].amount ? Number(cap[0].amount.value) : null;
    const cur = cap[0] && cap[0].amount ? cap[0].amount.currency_code : "USD";
    await rpc(env, "pay_complete", { p_secret: env.WORKER_SECRET, p_order: order, p_charged: amt, p_currency: cur });
    return back("done");
  } catch (e) {
    return back("failed");
  }
}
