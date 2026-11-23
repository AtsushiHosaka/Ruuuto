-- RCNO-34 グループを作った利用者もアカウントを削除できるようにする
-- A: グループ1を作った人（写真・装飾・招待・端末あり） / B: グループ1に2番目に参加 / C: 3番目に参加
-- S: 1人だけのグループ2を作った人 / O: グループ3の owner 役だが作成者ではない
begin;
select plan(24);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000034a1', 'del-a@example.com'),
  ('00000000-0000-0000-0000-0000000034b1', 'del-b@example.com'),
  ('00000000-0000-0000-0000-0000000034c1', 'del-c@example.com'),
  ('00000000-0000-0000-0000-0000000034d1', 'del-s@example.com'),
  ('00000000-0000-0000-0000-0000000034e1', 'del-o@example.com');

insert into public.groups (id, name, created_by, create_request_id) values
  ('34000000-0000-0000-0000-000000000001', 'グループ1', '00000000-0000-0000-0000-0000000034a1', gen_random_uuid()),
  ('34000000-0000-0000-0000-000000000002', 'ひとりグループ', '00000000-0000-0000-0000-0000000034d1', gen_random_uuid()),
  ('34000000-0000-0000-0000-000000000003', 'グループ3', '00000000-0000-0000-0000-0000000034c1', gen_random_uuid());
-- C は B より後に参加。user_id の並びでは C が先になるようにして、参加順で選ぶことを確かめる
insert into public.group_members (group_id, user_id, role, joined_at) values
  ('34000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000034a1', 'owner',  now() - interval '3 days'),
  ('34000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000034c1', 'member', now() - interval '1 day'),
  ('34000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000034b1', 'member', now() - interval '2 days'),
  ('34000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000034d1', 'owner',  now() - interval '1 day'),
  ('34000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000034c1', 'owner',  now() - interval '3 days'),
  ('34000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000034e1', 'owner',  now() - interval '2 days'),
  ('34000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-0000000034b1', 'member', now() - interval '1 day');

insert into public.boards (id, group_id, topic, opens_at, closes_at) values
  ('34100000-0000-0000-0000-000000000001', '34000000-0000-0000-0000-000000000001', 'お題1', now() - interval '1 day', now() + interval '6 days'),
  ('34100000-0000-0000-0000-000000000002', '34000000-0000-0000-0000-000000000002', 'お題2', now() - interval '1 day', now() + interval '6 days');

insert into public.photos (id, board_id, posted_by, storage_path, status, updated_by) values
  ('34200000-0000-0000-0000-000000000001', '34100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000034a1', 'del/a-posted.jpg', 'posted', '00000000-0000-0000-0000-0000000034a1'),
  ('34200000-0000-0000-0000-000000000002', '34100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000034b1', 'del/b-posted.jpg', 'posted', '00000000-0000-0000-0000-0000000034a1'),
  ('34200000-0000-0000-0000-000000000003', '34100000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000034d1', 'del/s-posted.jpg', 'posted', null);
insert into storage.objects (bucket_id, name) values
  ('photos', 'del/a-posted.jpg'), ('photos', 'del/b-posted.jpg'), ('photos', 'del/s-posted.jpg');

insert into public.decorations (id, board_id, created_by, kind, content, updated_by) values
  ('34300000-0000-0000-0000-000000000001', '34100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000034a1', 'stamp', '{"stamp": "snow"}', null),
  ('34300000-0000-0000-0000-000000000002', '34100000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000034b1', 'stamp', '{"stamp": "sun"}', '00000000-0000-0000-0000-0000000034a1');
update public.photos set locked_by = '00000000-0000-0000-0000-0000000034a1', lock_expires_at = now() + interval '1 minute'
 where id = '34200000-0000-0000-0000-000000000002';

insert into public.invitations (group_id, token_hash, created_by, expires_at) values
  ('34000000-0000-0000-0000-000000000001', extensions.digest('del-token-a', 'sha256'),
   '00000000-0000-0000-0000-0000000034a1', now() + interval '7 days');
insert into public.devices (installation_id, user_id, apns_token) values
  (gen_random_uuid(), '00000000-0000-0000-0000-0000000034a1', repeat('3a', 32));
insert into public.notification_events (kind, group_id, board_id, topic, actor_id) values
  ('topic_changed', '34000000-0000-0000-0000-000000000001', '34100000-0000-0000-0000-000000000001', 'お題1',
   '00000000-0000-0000-0000-0000000034a1');

-- 1. 作成者 A を消す（ほかのメンバーが残る）
select lives_ok(
  $$ delete from auth.users where id = '00000000-0000-0000-0000-0000000034a1' $$,
  'グループを作った人も auth.users から削除できる');
select is((select count(*)::int from public.profiles where id = '00000000-0000-0000-0000-0000000034a1'), 0,
  'A のプロフィールが消える');
select is((select created_by from public.groups where id = '34000000-0000-0000-0000-000000000001'),
  '00000000-0000-0000-0000-0000000034b1'::uuid, 'グループ1の作成者は、最も早く参加した B に移る');
select is(
  (select array_agg(user_id::text || ':' || role order by joined_at) from public.group_members
   where group_id = '34000000-0000-0000-0000-000000000001'),
  array['00000000-0000-0000-0000-0000000034b1:owner', '00000000-0000-0000-0000-0000000034c1:member'],
  'B が owner になり、C は member のまま');
select is((select count(*)::int from public.photos where posted_by = '00000000-0000-0000-0000-0000000034a1'), 0,
  'A の写真の行は消える');
select is((select count(*)::int from public.photos where id = '34200000-0000-0000-0000-000000000002'), 1,
  'B の写真は残る');
select is(
  (select row(updated_by, locked_by)::text from public.photos where id = '34200000-0000-0000-0000-000000000002'),
  '(,)', 'B の写真の updated_by と locked_by は null になる');
select is((select count(*)::int from public.decorations where created_by = '00000000-0000-0000-0000-0000000034a1'), 0,
  'A の装飾は消える');
select is((select updated_by from public.decorations where id = '34300000-0000-0000-0000-000000000002'), null::uuid,
  'B の装飾は残り、updated_by は null になる');
select is((select count(*)::int from public.invitations where created_by = '00000000-0000-0000-0000-0000000034a1'), 0,
  'A が発行した招待は消える');
select is((select count(*)::int from public.devices where user_id = '00000000-0000-0000-0000-0000000034a1'), 0,
  'A の端末登録は消える');
select is((select actor_id from public.notification_events where group_id = '34000000-0000-0000-0000-000000000001'), null::uuid,
  '通知イベントは残り、actor_id は null になる');
select is((select count(*)::int from public.boards where group_id = '34000000-0000-0000-0000-000000000001'), 1,
  'グループ1のボードは残る');

-- 2. 1人だけのグループを作った S を消す
select lives_ok(
  $$ delete from auth.users where id = '00000000-0000-0000-0000-0000000034d1' $$,
  '1人だけのグループを作った人も削除できる');
select is((select count(*)::int from public.groups where id = '34000000-0000-0000-0000-000000000002'), 0,
  'ほかにメンバーがいないグループは消える');
select is((select count(*)::int from public.boards where group_id = '34000000-0000-0000-0000-000000000002'), 0,
  'そのグループのボードも消える');

-- 3. owner 役が2人いるグループ3: 作成者 C を消すと、残る owner の O が作成者になる
select lives_ok(
  $$ delete from auth.users where id = '00000000-0000-0000-0000-0000000034c1' $$,
  '2つのグループに所属する C も削除できる');
select is((select created_by from public.groups where id = '34000000-0000-0000-0000-000000000003'),
  '00000000-0000-0000-0000-0000000034e1'::uuid, 'ほかに owner がいれば、その人が作成者になる');
select is(
  (select array_agg(user_id::text || ':' || role order by joined_at) from public.group_members
   where group_id = '34000000-0000-0000-0000-000000000003'),
  array['00000000-0000-0000-0000-0000000034e1:owner', '00000000-0000-0000-0000-0000000034b1:member'],
  'B は member のまま');
select is(
  (select array_agg(user_id::text order by joined_at) from public.group_members
   where group_id = '34000000-0000-0000-0000-000000000001'),
  array['00000000-0000-0000-0000-0000000034b1'], 'グループ1は B だけが残る');

-- 4. 消えた写真の画像は片付けの対象になる
update storage.objects set created_at = now() - interval '2 hours'
 where bucket_id = 'photos' and name like 'del/%';
set local role service_role;
create temp table targets as select public.ruuuto_admin_photo_cleanup_targets()::jsonb as t;
reset role;
select ok((select t -> 'paths' ? 'del/a-posted.jpg' from targets),
  'A の写真の画像（行が消えたもの）は片付けの対象');
select ok((select t -> 'paths' ? 'del/s-posted.jpg' from targets),
  '消えたグループの写真の画像も片付けの対象');
select ok((select not (t -> 'paths' ? 'del/b-posted.jpg') from targets),
  '残っている B の投稿済みの写真の画像は対象にしない');

-- 作成から間もない、行のない画像はまだ消さない
insert into storage.objects (bucket_id, name) values ('photos', 'del/just-now.jpg');
set local role service_role;
select ok((select not (public.ruuuto_admin_photo_cleanup_targets()::jsonb -> 'paths' ? 'del/just-now.jpg')),
  '作成から1時間たっていない画像は対象にしない');
reset role;

select * from finish();
rollback;
