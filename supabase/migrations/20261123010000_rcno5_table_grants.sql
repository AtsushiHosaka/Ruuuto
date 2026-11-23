-- RCNO-5 所属メンバーが読むテーブルにSELECT権限を付ける
--
-- RLSのポリシーは「どの行を返すか」を決めるだけで、テーブル自体のSELECT権限は別に要る。
-- 新規テーブルをData APIへ自動で公開しない設定のSupabaseでは、権限がないと
-- 所属メンバーでも 42501 になるため、権限をテーブルごとに明示する。
--
-- * anon: どのテーブルにも権限を持たせない。
-- * authenticated: 読み取りのRLSポリシーがあるテーブルだけ SELECT を付ける。
--   書き込みはこれまでどおり security definer のRPCだけで行う。
-- * invitations、notification_events、notification_deliveries は読み取りの
--   ポリシーがなく、RPCとサーバー処理からだけ使うため、権限を付けない。
--
-- 以前は public スキーマの既定の権限に頼っていたが、それをやめたため、
-- notification_events のように既定の権限を引き継いだテーブルもここで取り消す。

revoke all on
  public.profiles,
  public.groups,
  public.group_members,
  public.invitations,
  public.topic_prompts,
  public.boards,
  public.photos,
  public.decorations,
  public.devices,
  public.notification_events,
  public.notification_deliveries
from anon, authenticated;

grant select on
  public.profiles,
  public.groups,
  public.group_members,
  public.topic_prompts,
  public.boards,
  public.photos,
  public.decorations,
  public.devices
to authenticated;
