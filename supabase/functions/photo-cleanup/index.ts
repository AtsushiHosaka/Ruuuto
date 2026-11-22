// RCNO-35 消し残した画像を Storage API で消す。
// Cron（private.ruuuto_request_photo_cleanup）から1時間ごとに呼ばれる。
// 呼び出しには合言葉ヘッダー x-ruuuto-cleanup-secret が必要（環境変数 PHOTO_CLEANUP_SECRET と一致すること）。
import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const BUCKET = "photos";
const BATCH = 100;

function timingSafeEqual(a: string, b: string): boolean {
  const ea = new TextEncoder().encode(a);
  const eb = new TextEncoder().encode(b);
  if (ea.length !== eb.length) return false;
  let diff = 0;
  for (let i = 0; i < ea.length; i++) diff |= ea[i] ^ eb[i];
  return diff === 0;
}

Deno.serve(async (req) => {
  const expected = Deno.env.get("PHOTO_CLEANUP_SECRET") ?? "";
  const given = req.headers.get("x-ruuuto-cleanup-secret") ?? "";
  if (req.method !== "POST" || expected.length < 16 || !timingSafeEqual(given, expected)) {
    return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: targets, error: targetsError } = await supabase.rpc("ruuuto_admin_photo_cleanup_targets");
  if (targetsError) {
    console.error("cleanup targets failed", targetsError);
    return new Response(JSON.stringify({ error: "targets_failed" }), { status: 500 });
  }

  const paths: string[] = targets.paths ?? [];
  const removed: string[] = [];
  const failed: string[] = [];

  for (let i = 0; i < paths.length; i += BATCH) {
    const batch = paths.slice(i, i + BATCH);
    const { data, error } = await supabase.storage.from(BUCKET).remove(batch);
    if (error) {
      console.error("storage remove failed", error);
      failed.push(...batch);
      continue;
    }
    const names = new Set((data ?? []).map((o: { name: string }) => o.name));
    for (const p of batch) (names.has(p) ? removed : failed).push(p);
  }

  const { data: finished, error: finishError } = await supabase.rpc("ruuuto_admin_photo_cleanup_finish", {
    p_paths: removed,
  });
  if (finishError) console.error("cleanup finish failed", finishError);

  const result = {
    removed_rows_without_image: targets.removed_rows ?? 0,
    removed_images: removed.length,
    failed_images: failed.length,
    removed_pending_rows: finished?.removed_rows ?? 0,
  };
  console.log("photo-cleanup", JSON.stringify(result));
  return new Response(JSON.stringify(result), {
    status: failed.length > 0 || finishError ? 207 : 200,
    headers: { "Content-Type": "application/json" },
  });
});
