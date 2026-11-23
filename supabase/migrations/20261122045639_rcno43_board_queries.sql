-- RCNO-43 開催中・履歴・都市別のボード参照
--
--   ruuuto_current_board(p_group_id)            -> {id, group_id, topic, opens_at, closes_at, status}
--   ruuuto_board_history(p_group_id, p_year, p_month)
--                                               -> [{id, topic, opens_at, closes_at, status, photo_count, preview_paths}]
--   ruuuto_board_cities(p_board_id)             -> [{city, photo_count}]
--   ruuuto_city_photos(p_board_id, p_city)      -> [{id, storage_path, city, posted_by, display_name, posted_at, width, height}]
--
-- 日時はすべてUTCの秒単位で "2026-11-16T00:00:00Z" の形にする。
-- iOSは小数秒あり・なしのISO 8601を読むが、桁数のぶれを避けるため秒にそろえる。

create function private.ruuuto_ts(p_at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char(p_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
$$;

-- グループに所属していなければ 42501
create function private.ruuuto_require_member(p_group_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_user_id uuid := private.ruuuto_require_user();
begin
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = v_user_id
  ) then
    raise exception 'このグループを見る権限がありません' using errcode = '42501';
  end if;
  return v_user_id;
end;
$$;

-- ボードのグループに所属していなければ 42501（ボードがないときも同じ扱いにして存在を漏らさない）
create function private.ruuuto_require_board_member(p_board_id uuid)
returns uuid
language plpgsql
stable
set search_path = ''
as $$
declare
  v_group_id uuid;
begin
  select b.group_id into v_group_id from public.boards b where b.id = p_board_id;
  if v_group_id is null then
    perform private.ruuuto_require_user();
    raise exception 'このボードを見る権限がありません' using errcode = '42501';
  end if;
  return private.ruuuto_require_member(v_group_id);
end;
$$;

-- 開催中のボード。iOS #7 の CurrentBoardAPI が読む形。
-- 開催中がない（週次切替の失敗など）ときは P0002。
create function public.ruuuto_current_board(p_group_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result json;
begin
  perform private.ruuuto_require_member(p_group_id);

  select json_build_object(
           'id', b.id,
           'group_id', b.group_id,
           'topic', b.topic,
           'opens_at', private.ruuuto_ts(b.opens_at),
           'closes_at', private.ruuuto_ts(b.closes_at),
           'status', b.status)
    into v_result
  from public.boards b
  where b.group_id = p_group_id and b.status = 'open';

  if v_result is null then
    raise exception '開催中のボードがありません' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

-- 月別のボード一覧（カレンダー用）。
-- ボードは「開始日時の月（日本時間）」に属する。開催中のボードも status 付きで含む。
-- preview_paths は投稿済みの写真の保存先を、古い順に最大3件。
create function public.ruuuto_board_history(p_group_id uuid, p_year int, p_month int)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_from timestamptz;
begin
  perform private.ruuuto_require_member(p_group_id);
  if p_year not between 2000 and 2100 or p_month not between 1 and 12 then
    raise exception '年月の指定が正しくありません' using errcode = '22023';
  end if;

  v_from := make_timestamptz(p_year, p_month, 1, 0, 0, 0, 'Asia/Tokyo');

  return coalesce((
    select json_agg(json_build_object(
             'id', b.id,
             'topic', b.topic,
             'opens_at', private.ruuuto_ts(b.opens_at),
             'closes_at', private.ruuuto_ts(b.closes_at),
             'status', b.status,
             'photo_count', coalesce(s.photo_count, 0),
             'preview_paths', coalesce(s.preview_paths, '[]'::json))
           order by b.opens_at)
    from public.boards b
    left join lateral (
      select count(*)::int as photo_count,
             (select json_agg(x.storage_path order by x.created_at, x.id)
              from (select p2.storage_path, p2.created_at, p2.id
                    from public.photos p2
                    where p2.board_id = b.id and p2.status = 'posted'
                    order by p2.created_at, p2.id
                    limit 3) x) as preview_paths
      from public.photos p
      where p.board_id = b.id and p.status = 'posted'
    ) s on true
    where b.group_id = p_group_id
      and b.opens_at >= v_from
      and b.opens_at < v_from + interval '1 month'
  ), '[]'::json);
end;
$$;

-- 選んだボードの都市別の写真数（マップ用）。都市が未設定の写真は含めない。多い順。
create function public.ruuuto_board_cities(p_board_id uuid)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.ruuuto_require_board_member(p_board_id);

  return coalesce((
    select json_agg(json_build_object('city', c.city, 'photo_count', c.photo_count)
                    order by c.photo_count desc, c.city)
    from (
      select p.city, count(*)::int as photo_count
      from public.photos p
      where p.board_id = p_board_id and p.status = 'posted' and p.city is not null
      group by p.city
    ) c
  ), '[]'::json);
end;
$$;

-- 選んだボード・都市の写真一覧（マップのシート用）。投稿の古い順。
create function public.ruuuto_city_photos(p_board_id uuid, p_city text)
returns json
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform private.ruuuto_require_board_member(p_board_id);

  return coalesce((
    select json_agg(json_build_object(
             'id', p.id,
             'storage_path', p.storage_path,
             'city', p.city,
             'posted_by', p.posted_by,
             'display_name', pr.display_name,
             'posted_at', private.ruuuto_ts(coalesce(p.posted_at, p.created_at)),
             'width', p.width,
             'height', p.height)
           order by coalesce(p.posted_at, p.created_at), p.id)
    from public.photos p
    join public.profiles pr on pr.id = p.posted_by
    where p.board_id = p_board_id
      and p.status = 'posted'
      and p.city = btrim(p_city)
  ), '[]'::json);
end;
$$;

revoke execute on function private.ruuuto_ts(timestamptz) from public, anon, authenticated;
revoke execute on function private.ruuuto_require_member(uuid) from public, anon, authenticated;
revoke execute on function private.ruuuto_require_board_member(uuid) from public, anon, authenticated;
revoke execute on function public.ruuuto_current_board(uuid) from public, anon;
revoke execute on function public.ruuuto_board_history(uuid, int, int) from public, anon;
revoke execute on function public.ruuuto_board_cities(uuid) from public, anon;
revoke execute on function public.ruuuto_city_photos(uuid, text) from public, anon;
grant execute on function public.ruuuto_current_board(uuid) to authenticated;
grant execute on function public.ruuuto_board_history(uuid, int, int) to authenticated;
grant execute on function public.ruuuto_board_cities(uuid) to authenticated;
grant execute on function public.ruuuto_city_photos(uuid, text) to authenticated;
