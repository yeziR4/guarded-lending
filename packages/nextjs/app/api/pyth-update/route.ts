import { NextResponse } from "next/server";

/**
 * Server-side proxy for Pyth Hermes price updates. Since the Pyth Core upgrade (2026-08-26) Hermes
 * requires an API key, which must never be shipped to the browser, so the dashboard asks this route
 * for signed update data and submits it on-chain itself.
 */
const HERMES_URL = process.env.PYTH_HERMES_URL ?? "https://pyth.dourolabs.app/hermes";
const PRICE_ID_RE = /^0x[0-9a-fA-F]{64}$/;

export async function GET(req: Request) {
  const apiKey = process.env.PYTH_API_KEY;
  if (!apiKey) {
    return NextResponse.json(
      { error: "PYTH_API_KEY is not set. Pyth stays stale and the guard runs on Chainlink + Supra (2 of 3)." },
      { status: 501 },
    );
  }

  const id = new URL(req.url).searchParams.get("id");
  if (!id || !PRICE_ID_RE.test(id)) {
    return NextResponse.json({ error: "Missing or invalid Pyth price id" }, { status: 400 });
  }

  try {
    const res = await fetch(`${HERMES_URL}/v2/updates/price/latest?ids[]=${id}&encoding=hex`, {
      headers: { Authorization: `Bearer ${apiKey}` },
      cache: "no-store",
    });
    if (!res.ok) {
      return NextResponse.json({ error: `Hermes responded ${res.status}` }, { status: 502 });
    }
    const body = (await res.json()) as { binary: { data: string[] } };
    return NextResponse.json({ updateData: body.binary.data.map(hex => `0x${hex}`) });
  } catch (e) {
    console.error("[api/pyth-update]", e);
    return NextResponse.json({ error: "Hermes request failed" }, { status: 502 });
  }
}
