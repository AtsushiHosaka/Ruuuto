-- RCNO-35 消し残した画像の片付け
--
-- 片付ける対象
--   * 取り下げた写真で、画像がまだ残っているもの
--   * 1時間以上「投稿途中」のままの写真（アップロードや確定に失敗して放置されたもの）
-- 流れ（1時間ごと）
--   Cron → Edge Function photo-cleanup
--     1. ruuuto_admin_photo_cleanup_targets() で消す画像のパスを受け取る
--        （画像がない投稿途中の行は、この時点でDBから消す）
--     2. Storage API で画像を消す
--     3. ruuuto_admin_photo_cleanup_finish(paths) で、画像が消えた投稿途中の行を消す
--   取り下げた写真の行は、記録として残す（アプリからは見えない）。

-- service_role（Edge Function）だけが呼べる
create function public.ruuuto_admin_photo_cleanup_targets(p_pending_older_than interval default interval '1 hour')
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_removed_rows int;
begin
  -- 画像がない投稿途中の行は、そのまま消す
  delete from public.photos p
   where p.status = 'pending'
     and p.created_at < now() - p_pending_older_than
     and not exists (select 1 from storage.objects o where o.bucket_id = 'photos' and o.name = p.storage_path);
  get diagnostics v_removed_rows = row_count;

  return json_build_object(
    'removed_rows', v_removed_rows,
    'paths', coalesce((
      select json_agg(p.storage_path order by p.storage_path)
      from public.photos p
      where (p.status = 'withdrawn'
             or (p.status = 'pending' and p.created_at < now() - p_pending_older_than))
        and exists (select 1 from storage.objects o where o.bucket_id = 'photos' and o.name = p.storage_path)
    ), '[]'::json));
end;
$$;

create function public.ruuuto_admin_photo_cleanup_finish(p_paths text[])
returns json
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_removed_rows int;
begin
  delete from public.photos p
   where p.status = 'pending'
     and p.storage_path = any (p_paths)
     and not exists (select 1 from storage.objects o where o.bucket_id = 'photos' and o.name = p.storage_path);
  get diagnostics v_removed_rows = row_count;
  return json_build_object('removed_rows', v_removed_rows);
end;
$$;

revoke execute on function public.ruuuto_admin_photo_cleanup_targets(interval) from public, anon, authenticated;
revoke execute on function public.ruuuto_admin_photo_cleanup_finish(text[]) from public, anon, authenticated;
grant execute on function public.ruuuto_admin_photo_cleanup_targets(interval) to service_role;
grant execute on function public.ruuuto_admin_photo_cleanup_finish(text[]) to service_role;

-- Cron から Edge Function を呼ぶ
-- 接続先と合言葉は Vault に置く（リポジトリには書かない）。未設定なら何もしない。
--   select vault.create_secret('https://<project-ref>.supabase.co', 'ruuuto_project_url');
--   select vault.create_secret('<ランダムな文字列>', 'ruuuto_cleanup_secret');
-- 同じ合言葉を Edge Function の環境変数 PHOTO_CLEANUP_SECRET に設定する。
create extension if not exists pg_net with schema extensions;

create function private.ruuuto_request_photo_cleanup()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'ruuuto_project_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'ruuuto_cleanup_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  return net.http_post(
    url := rtrim(v_url, '/') || '/functions/v1/photo-cleanup',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-ruuuto-cleanup-secret', v_secret),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000);
end;
$$;

revoke execute on function private.ruuuto_request_photo_cleanup() from public, anon, authenticated;

select cron.schedule(
  'ruuuto-photo-cleanup',
  '17 * * * *',
  $$select private.ruuuto_request_photo_cleanup()$$
);
