alter table public.agent_stock_movements
  drop constraint agent_stock_movements_quantity_check,
  add constraint agent_stock_movements_quantity_check
    check (quantity > 0 or (movement_type = 'adjustment' and quantity < 0));

create or replace function public.issue_real_stock_to_agent(
  p_agent_id uuid, p_crm_product_id uuid, p_qty integer, p_comment text default ''
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.profiles
    where id = auth.uid() and active and coalesce(status,'active') = 'active' and role = 'manager') then
    raise exception 'Only manager can issue stock to agents';
  end if;
  if p_qty is null or p_qty <= 0 then
    raise exception 'Quantity must be greater than zero';
  end if;
  if not exists (select 1 from public.profiles
    where id = p_agent_id and active and coalesce(status,'active') = 'active') then
    raise exception 'Agent is not active';
  end if;

  insert into public.agent_stock_balances(agent_id,product_id,quantity,updated_at)
  values (p_agent_id,p_crm_product_id,p_qty,now())
  on conflict (agent_id,product_id) do update set
    quantity = public.agent_stock_balances.quantity + excluded.quantity, updated_at = now();
  insert into public.agent_stock_movements(agent_id,product_id,movement_type,quantity,comment,created_by)
  values (p_agent_id,p_crm_product_id,'warehouse_issue',p_qty,coalesce(p_comment,''),auth.uid());
end;
$$;

create or replace function public.set_agent_stock_quantity(
  p_agent_id uuid, p_crm_product_id uuid, p_new_qty integer, p_comment text default ''
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_current integer;
begin
  if not exists (select 1 from public.profiles
    where id = auth.uid() and active and coalesce(status,'active') = 'active' and role = 'manager') then
    raise exception 'Only manager can adjust agent stock';
  end if;
  if p_new_qty is null or p_new_qty < 0 then
    raise exception 'New quantity must be zero or greater';
  end if;
  if not exists (select 1 from public.profiles
    where id = p_agent_id and active and coalesce(status,'active') = 'active') then
    raise exception 'Agent is not active';
  end if;

  insert into public.agent_stock_balances(agent_id,product_id,quantity,updated_at)
  values (p_agent_id,p_crm_product_id,0,now())
  on conflict (agent_id,product_id) do nothing;

  select quantity into strict v_current from public.agent_stock_balances
  where agent_id = p_agent_id and product_id = p_crm_product_id for update;
  if p_new_qty = v_current then return; end if;

  update public.agent_stock_balances set quantity = p_new_qty, updated_at = now()
  where agent_id = p_agent_id and product_id = p_crm_product_id;
  insert into public.agent_stock_movements(agent_id,product_id,movement_type,quantity,comment,created_by)
  values (p_agent_id,p_crm_product_id,'adjustment',p_new_qty-v_current,coalesce(p_comment,''),auth.uid());
end;
$$;
