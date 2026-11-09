
alter table public.shops
 add column opening_consignment boolean not null default false,
 add column opening_delivery_count integer not null default 0 check(opening_delivery_count between 0 and 2),
 add column opening_bonus_received_at timestamptz,
 add column opening_bonus_received_by uuid references public.profiles(id);
update public.shops set opening_consignment=true,opening_delivery_count=1 where supply_terms='consignment';
create function private.guard_shop_opening_bonus() returns trigger language plpgsql security invoker set search_path='' as $$
declare management boolean;
begin
 management:=private.is_management();
 if TG_OP='INSERT' then
   new.opening_consignment:=coalesce(new.supply_terms='consignment',false);
   new.opening_delivery_count:=case when new.supply_terms in ('consignment','supplied','deferred') then 1 else 0 end;
 else
   if old.opening_bonus_received_at is not null and
      (new.opening_bonus_received_at is distinct from old.opening_bonus_received_at or new.opening_bonus_received_by is distinct from old.opening_bonus_received_by)
      and not management then raise exception 'Снять отметку о премии может только руководитель'; end if;
   if new.opening_consignment is distinct from old.opening_consignment then raise exception 'Тип первой передачи не изменяется'; end if;
   if new.opening_delivery_count < old.opening_delivery_count then raise exception 'Счётчик передач нельзя уменьшить'; end if;
   if new.opening_delivery_count > old.opening_delivery_count+1 then raise exception 'Отмечайте передачи по очереди'; end if;
   if old.opening_delivery_count=0 and new.supply_terms in ('consignment','supplied','deferred') then
     new.opening_delivery_count:=1;
     new.opening_consignment:=new.supply_terms='consignment';
   end if;
 end if;
 if new.opening_bonus_received_at is not null and
    (TG_OP='INSERT' or old.opening_bonus_received_at is null) then
   if auth.uid() is null then raise exception 'Требуется вход'; end if;
   if new.opening_delivery_count < (case when new.opening_consignment then 2 else 1 end) then
     raise exception 'Премия доступна после повторной передачи при реализации';
   end if;
   if not management and new.created_by is distinct from auth.uid() then raise exception 'Подтвердить премию может только открывший магазин агент'; end if;
   new.opening_bonus_received_at:=now();
   new.opening_bonus_received_by:=auth.uid();
 elsif new.opening_bonus_received_at is null then new.opening_bonus_received_by:=null;
 end if;
 return new;
end $$;
create trigger guard_shop_opening_bonus before insert or update on public.shops for each row execute function private.guard_shop_opening_bonus();
