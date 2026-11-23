-- RCNO-36 ボード単位のリアルタイム配信
-- 定量目標: 同じボードのメンバーだけが受信・送信でき、別グループと未ログインは拒否する。
-- 保存済みのチャネルにはアプリから送れない。保存済みの変更はデータベースだけが配信し、
-- 投稿途中の写真と中身の変わらない更新は配信しない。再接続後は保存済みの状態を取り直せる。
begin;
select plan(40);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000036a1', 'rt-a@example.com'),
  ('00000000-0000-0000-0000-0000000036b1', 'rt-b@example.com'),
  ('00000000-0000-0000-0000-0000000036c1', 'rt-c@example.com');
insert into public.groups (id, name, created_by, create_request_id) values
  ('36000000-0000-0000-0000-000000000001', 'えーえす班', '00000000-0000-0000-0000-0000000036a1', gen_random_uuid()),
  ('36000000-0000-0000-0000-000000000002', 'べつの班', '00000000-0000-0000-0000-0000000036c1', gen_random_uuid());
insert into public.group_members (group_id, user_id, role) values
  ('36000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000036a1', 'owner'),
  ('36000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000036b1', 'member'),
  ('36000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000036c1', 'owner');
insert into public.boards (id, group_id, topic, opens_at, closes_at, status, closed_at) values
  ('36100000-0000-0000-0000-000000000001', '36000000-0000-0000-0000-000000000001', '窓の外',
   now() - interval '1 day', now() + interval '6 days', 'open', null),
  ('36100000-0000-0000-0000-000000000002', '36000000-0000-0000-0000-000000000002', '朝ごはん',
   now() - interval '1 day', now() + interval '6 days', 'open', null);

create function pg_temp.act_as(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

-- Realtime の権限確認と同じく、realtime.topic を設定してから読む・書く
create function pg_temp.can_read(p_topic text, p_extension text default 'broadcast') returns boolean
language plpgsql as $$
declare
  v_id uuid := gen_random_uuid();
  v_role text := current_user;
  v_found boolean;
begin
  reset role;
  insert into realtime.messages (id, topic, extension) values (v_id, p_topic, p_extension);
  execute format('set local role %I', v_role);
  perform set_config('realtime.topic', p_topic, true);
  select exists (select 1 from realtime.messages m where m.id = v_id) into v_found;
  return v_found;
end;
$$;

create function pg_temp.can_write(p_topic text, p_extension text default 'broadcast') returns boolean
language plpgsql as $$
begin
  perform set_config('realtime.topic', p_topic, true);
  insert into realtime.messages (topic, extension) values (p_topic, p_extension);
  return true;
exception when insufficient_privilege then
  return false;
end;
$$;

-- 配信されたメッセージ（postgres で数える）
create function pg_temp.sent(p_event text) returns setof realtime.messages
language sql security definer as $$
  select * from realtime.messages m
  where m.event = p_event and m.extension = 'broadcast'
  order by m.inserted_at;
$$;

select is(private.ruuuto_board_topic_id('board:36100000-0000-0000-0000-000000000001', false),
  '36100000-0000-0000-0000-000000000001'::uuid, '保存済みのトピックからボードIDを取り出せる');
select is(private.ruuuto_board_topic_id('board:36100000-0000-0000-0000-000000000001:live', true),
  '36100000-0000-0000-0000-000000000001'::uuid, 'live のトピックからボードIDを取り出せる');
select is(private.ruuuto_board_topic_id('board:36100000-0000-0000-0000-000000000001:live', false),
  null, '保存済みとして読むと live のトピックは受け付けない');
select is(private.ruuuto_board_topic_id('board:not-a-uuid', false), null, 'UUIDでないトピックは null（エラーにしない）');

set local role authenticated;

-- 同じボードのメンバー
select pg_temp.act_as('00000000-0000-0000-0000-0000000036b1');
select ok(pg_temp.can_read('board:36100000-0000-0000-0000-000000000001'), 'メンバーは保存済みのチャネルを受信できる');
select ok(pg_temp.can_read('board:36100000-0000-0000-0000-000000000001:live'), 'メンバーは live のチャネルを受信できる');
select ok(pg_temp.can_read('board:36100000-0000-0000-0000-000000000001:live', 'presence'), 'メンバーは live の Presence を受信できる');
select ok(pg_temp.can_write('board:36100000-0000-0000-0000-000000000001:live'), 'メンバーは live にカーソルを送信できる');
select ok(pg_temp.can_write('board:36100000-0000-0000-0000-000000000001:live', 'presence'), 'メンバーは live に Presence を送信できる');
select ok(not pg_temp.can_write('board:36100000-0000-0000-0000-000000000001'), 'メンバーでも保存済みのチャネルには送信できない');
select ok(not pg_temp.can_write('board:36100000-0000-0000-0000-000000000001', 'presence'), 'メンバーでも保存済みのチャネルに Presence は送れない');

-- 別グループの参加者
select pg_temp.act_as('00000000-0000-0000-0000-0000000036c1');
select ok(not pg_temp.can_read('board:36100000-0000-0000-0000-000000000001'), '別グループの参加者は保存済みのチャネルを受信できない');
select ok(not pg_temp.can_read('board:36100000-0000-0000-0000-000000000001:live'), '別グループの参加者は live を受信できない');
select ok(not pg_temp.can_write('board:36100000-0000-0000-0000-000000000001:live'), '別グループの参加者は live に送信できない');
select ok(pg_temp.can_read('board:36100000-0000-0000-0000-000000000002'), '自分のグループのボードは受信できる');

-- 形式の違うトピック
select ok(not pg_temp.can_read('board:not-a-uuid'), '形式の違うトピックは受信できない');
select ok(not pg_temp.can_read('board:36100000-0000-0000-0000-000000000002:other'), '知らない接尾辞のトピックは受信できない');
select ok(not pg_temp.can_write('board:36100000-0000-0000-0000-000000000002:live:x'), '余計な接尾辞のトピックには送信できない');

-- 未ログイン
reset role;
set local role anon;
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
select ok(not pg_temp.can_read('board:36100000-0000-0000-0000-000000000001'), '未ログインは受信できない');
select ok(not pg_temp.can_write('board:36100000-0000-0000-0000-000000000001:live'), '未ログインは送信できない');

reset role;

-- 写真: 投稿途中は配信しない
insert into public.photos (id, board_id, posted_by, storage_path, status, width, height) values
  ('36200000-0000-0000-0000-000000000001', '36100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000036a1', 'g/b/36200000-0000-0000-0000-000000000001', 'pending', 1200, 900);
update public.photos set x = 5 where id = '36200000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.sent('photo_saved')), 0::bigint, '投稿途中の写真は配信しない');

-- 投稿済みになったら配信する
update public.photos set status = 'posted', posted_at = now(), z_index = 1
 where id = '36200000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.sent('photo_saved')), 1::bigint, '投稿済みになった写真を1件配信する');
select is((select topic from pg_temp.sent('photo_saved') limit 1),
  'board:36100000-0000-0000-0000-000000000001', '写真はボードの保存済みのチャネルに配信する');
select is((select private from pg_temp.sent('photo_saved') limit 1), true, '非公開のメッセージとして配信する');
select is((select payload ->> 'status' from pg_temp.sent('photo_saved') limit 1), 'posted', 'payload は写真の形');

-- 位置の変更
update public.photos set x = 120.5, y = -40, revision = revision + 1
 where id = '36200000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.sent('photo_saved')), 2::bigint, '位置の変更を配信する');
select is(
  (select jsonb_build_object('x', payload -> 'x', 'y', payload -> 'y', 'revision', payload -> 'revision')
     from pg_temp.sent('photo_saved') offset 1 limit 1),
  '{"x": 120.5, "y": -40, "revision": 2}'::jsonb, '新しい位置と revision が届く');

-- 中身の変わらない更新
update public.photos set x = x where id = '36200000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.sent('photo_saved')), 2::bigint, '中身の変わらない更新は配信しない');

-- 取り下げ
update public.photos set status = 'withdrawn', withdrawn_at = now()
 where id = '36200000-0000-0000-0000-000000000001';
select is((select payload from pg_temp.sent('photo_withdrawn') limit 1),
  '{"id": "36200000-0000-0000-0000-000000000001", "board_id": "36100000-0000-0000-0000-000000000001"}'::jsonb,
  '取り下げは {id, board_id} だけを配信する');

-- 投稿途中から取り下げても配信しない
insert into public.photos (id, board_id, posted_by, storage_path, status) values
  ('36200000-0000-0000-0000-000000000002', '36100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000036a1', 'g/b/36200000-0000-0000-0000-000000000002', 'pending');
update public.photos set status = 'withdrawn', withdrawn_at = now()
 where id = '36200000-0000-0000-0000-000000000002';
select is((select count(*) from pg_temp.sent('photo_withdrawn')), 1::bigint, '投稿途中から取り下げた写真は配信しない');

-- 装飾
insert into public.decorations (id, board_id, created_by, kind, content) values
  ('36300000-0000-0000-0000-000000000001', '36100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000036b1', 'text', '{"text": "hello"}');
update public.decorations set x = x where id = '36300000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.sent('decoration_saved')), 1::bigint, '装飾の追加を配信し、中身の変わらない更新は配信しない');
update public.decorations set content = '{"text": "hi"}', revision = 2 where id = '36300000-0000-0000-0000-000000000001';
select is((select payload -> 'content' ->> 'text' from pg_temp.sent('decoration_saved') offset 1 limit 1), 'hi', '装飾の変更を配信する');
delete from public.decorations where id = '36300000-0000-0000-0000-000000000001';
select is((select payload from pg_temp.sent('decoration_deleted') limit 1),
  '{"id": "36300000-0000-0000-0000-000000000001", "board_id": "36100000-0000-0000-0000-000000000001"}'::jsonb,
  '装飾の削除は {id, board_id} を配信する');

-- ボード
update public.boards set topic = '夕焼け' where id = '36100000-0000-0000-0000-000000000001';
update public.boards set topic = topic where id = '36100000-0000-0000-0000-000000000001';
select is((select count(*) from pg_temp.sent('board_updated')), 1::bigint, 'お題の変更を1件配信し、中身の変わらない更新は配信しない');
select is(
  (select array(select jsonb_object_keys(payload) order by 1) from pg_temp.sent('board_updated') limit 1),
  array['closes_at', 'group_id', 'id', 'opens_at', 'status', 'topic'], 'board_updated は ruuuto_current_board と同じ項目');

-- 別グループのボードには何も配信していない
select is((select count(*) from realtime.messages
           where topic like 'board:36100000-0000-0000-0000-000000000002%' and event is not null),
  0::bigint, '別グループのボードには配信しない');

-- 再接続後の取り直し
insert into public.photos (id, board_id, posted_by, storage_path, status, x, y, z_index, posted_at) values
  ('36200000-0000-0000-0000-000000000003', '36100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000036a1', 'g/b/36200000-0000-0000-0000-000000000003', 'posted', 10, 20, 2, now()),
  ('36200000-0000-0000-0000-000000000004', '36100000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000036a1', 'g/b/36200000-0000-0000-0000-000000000004', 'pending', 0, 0, 0, null);

set local role authenticated;
select pg_temp.act_as('00000000-0000-0000-0000-0000000036b1');
create temp table snap as select public.ruuuto_board_snapshot('36100000-0000-0000-0000-000000000001')::jsonb as s;
select is((select s -> 'board' ->> 'topic' from snap), '夕焼け', 'スナップショットは最新のボードを返す');
select is(
  (select jsonb_agg(jsonb_build_object('id', e ->> 'id', 'x', e -> 'x', 'y', e -> 'y'))
     from snap, jsonb_array_elements(s -> 'photos') e),
  '[{"id": "36200000-0000-0000-0000-000000000003", "x": 10, "y": 20}]'::jsonb,
  'スナップショットは投稿済みの写真と保存済みの位置だけを返す');
select is((select jsonb_array_length(s -> 'decorations') from snap), 0, '消した装飾は返さない');

select pg_temp.act_as('00000000-0000-0000-0000-0000000036c1');
select throws_ok(
  $$ select public.ruuuto_board_snapshot('36100000-0000-0000-0000-000000000001') $$,
  '42501', null, '別グループの参加者はスナップショットを取れない');

select * from finish();
rollback;
