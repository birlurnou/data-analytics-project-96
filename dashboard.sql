-- все запросы построены на основе главной витрины aggregate_last_paid_click
-- по данным витрины создавались чарты и формировался дашборд


-- 1 создаем представление aggregate_last_paid_click
create view aggregate_last_paid_click as

-- расходы по каналам из vk_ads и ya_ads
with spent as (
    select
        date_trunc('day', campaign_date)::date as visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        sum(daily_spent) as total_cost
    from (
        select campaign_date, utm_source, utm_medium, utm_campaign, daily_spent
        from vk_ads
        union all
        select campaign_date, utm_source, utm_medium, utm_campaign, daily_spent
        from ya_ads
    ) ads
    group by 1, 2, 3, 4
),

-- только платные визиты
paid_clicks as (
    select
        visitor_id,
        visit_date,
        source as utm_source,
        medium as utm_medium,
        campaign as utm_campaign
    from sessions
    where medium in ('cpc','cpm','cpa','youtube','cpp','tg','social')
),

-- все платные клики до каждого из лидов
lead_clicks as (
    select
        l.lead_id,
        l.visitor_id,
        l.created_at,
        l.amount,
        l.status_id,
        pc.visit_date,
        pc.utm_source,
        pc.utm_medium,
        pc.utm_campaign,
        row_number() over (
            partition by l.lead_id
            order by pc.visit_date desc
        ) as rn
    from leads l
    join paid_clicks pc
        on pc.visitor_id = l.visitor_id
       and pc.visit_date <= l.created_at
),

-- последние клики перед конвертацией в лида
last_paid_click as (
    select
        lead_id,
        visitor_id,
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        amount,
        status_id
    from lead_clicks
    where rn = 1
),

-- агрегаты по лидам для leads_count, purchases_count, revenue
leads_agg as (
    select
        visit_date::date,
        utm_source,
        utm_medium,
        utm_campaign,
        count(lead_id) as leads_count,
        count(case when status_id = 142 then lead_id end) as purchases_count,
        sum(case when status_id = 142 then amount end) as revenue
    from last_paid_click
    group by 1, 2, 3, 4
),

-- агрегаты по визитам для visitors_count перед джойном с лидами
visitors_agg as (
    select
        visit_date::date,
        utm_source,
        utm_medium,
        utm_campaign,
        count(distinct visitor_id) as visitors_count
    from paid_clicks
    group by 1, 2, 3, 4
)

-- строим финальную витрину по полям visit_date, utm_source, utm_medium, utm_campaign
select
    s.total_cost,
    coalesce(v.visit_date, l.visit_date, s.visit_date) as visit_date,
    coalesce(v.visitors_count, 0) as visitors_count,
    coalesce(v.utm_source, l.utm_source, s.utm_source) as utm_source,
    coalesce(v.utm_medium, l.utm_medium, s.utm_medium) as utm_medium,
    coalesce(v.utm_campaign, l.utm_campaign, s.utm_campaign) as utm_campaign,
    coalesce(l.leads_count, 0) as leads_count,
    coalesce(l.purchases_count, 0) as purchases_count,
    coalesce(l.revenue, 0) as revenue
from visitors_agg as v
full join leads_agg as l
    on
        v.visit_date = l.visit_date
        and v.utm_source = l.utm_source
        and v.utm_medium = l.utm_medium
        and v.utm_campaign = l.utm_campaign
full join spent as s
    on
        coalesce(v.visit_date, l.visit_date) = s.visit_date
        and coalesce(v.utm_source, l.utm_source) = s.utm_source
        and coalesce(v.utm_medium, l.utm_medium) = s.utm_medium
        and coalesce(v.utm_campaign, l.utm_campaign) = s.utm_campaign;
-- order by
--     revenue desc nulls last,
--     visit_date asc,
--     visitors_count desc,
--     utm_source asc,
--     utm_medium asc,
--     utm_campaign asc;



-- сумма всех визитов
select sum(visitors_count) as total_visits
from aggregate_last_paid_click;


-- сумма всех лидов
select sum(leads_count) as total_leads
from aggregate_last_paid_click;


-- успешные покупки
select sum(purchases_count) as total_purchases
from aggregate_last_paid_click;


-- сумма общей выручки
select sum(revenue) as total_revenue
from aggregate_last_paid_click;


-- сумма общих расходов
select sum(total_cost) as total_cost
from aggregate_last_paid_click;


-- конверсия из кликов в лиды
select
    100.0 * sum(leads_count) / nullif(sum(visitors_count), 0) as cr_click_to_lead
from aggregate_last_paid_click;


-- конверсия целевого действия (покупки) из лида
select
    100.0 * sum(purchases_count) / nullif(sum(leads_count), 0) as cr_lead_to_purchase
from aggregate_last_paid_click;


-- количество визитов по каналам по дням
select
    visit_date,
    utm_source,
    sum(visitors_count) as visitors
from aggregate_last_paid_click
group by 1, 2
order by 1, 2;


-- количество лидов по каналам по дням (по дате последнего платного клика)
select
    visit_date,
    utm_source,
    sum(leads_count) as leads
from aggregate_last_paid_click
group by 1, 2
order by 1, 2;


-- сумма расходов по каналам по дням
select
    visit_date,
    utm_source,
    sum(total_cost) as total_cost
from aggregate_last_paid_click
group by 1, 2
order by 1, 2;


-- сумма выручки по каналам по дням
select
    visit_date,
    utm_source,
    sum(revenue) as revenue
from aggregate_last_paid_click
group by 1, 2
order by 1, 2;


-- ROI по каналам
select
    utm_source,
    sum(total_cost) as total_cost,
    sum(revenue) as revenue,
    sum(revenue) - sum(total_cost) as profit,
    round(
        (sum(revenue) - sum(total_cost)) / nullif(sum(total_cost), 0) * 100,
        2
    ) as roi_percent
from aggregate_last_paid_click
where total_cost > 0
group by utm_source
order by roi_percent desc nulls last;


-- сумма выручки по каналам за всё время
select
    utm_source,
    sum(revenue) as revenue
from aggregate_last_paid_click
where revenue > 0
group by utm_source
order by revenue desc;


-- сумма расходов по каналам за всё время
select
    utm_source,
    sum(total_cost) as total_cost
from aggregate_last_paid_click
where total_cost > 0
group by utm_source
order by total_cost desc;


-- сводная таблица по каналам привлечения с группировкой по utm_source
select
    utm_source,
    sum(visitors_count) as visitors,
    sum(leads_count) as leads,
    sum(purchases_count) as purchases,
    sum(total_cost) as total_cost,
    sum(revenue) as revenue,
    round(sum(total_cost) / nullif(sum(visitors_count), 0), 2) as cpu,
    round(sum(total_cost) / nullif(sum(leads_count), 0), 2) as cpl,
    round(sum(total_cost) / nullif(sum(purchases_count), 0), 2) as cppu,
    round(
        (sum(revenue) - sum(total_cost)) / nullif(sum(total_cost), 0) * 100,
        2
    ) as roi_percent
from aggregate_last_paid_click
group by utm_source
order by revenue desc nulls last;


-- сводная таблица по каналам привлечения с группировкой по utm_source, utm_medium и utm_campaign
select
    utm_source,
    utm_medium,
    utm_campaign,
    sum(visitors_count)  as visitors,
    sum(leads_count)  as leads,
    sum(purchases_count) as purchases,
    sum(total_cost) as total_cost,
    sum(revenue) as revenue,
    round(sum(total_cost) / nullif(sum(visitors_count), 0), 2) as cpu,
    round(sum(total_cost) / nullif(sum(leads_count), 0), 2) as cpl,
    round(sum(total_cost) / nullif(sum(purchases_count), 0), 2) as cppu,
    round(
        (sum(revenue) - sum(total_cost)) / nullif(sum(total_cost), 0) * 100,
        2
    ) as roi_percent
from aggregate_last_paid_click
group by utm_source, utm_medium, utm_campaign
order by revenue desc nulls last;


-- динамика всех визитов по дням
select
    visit_date,
    sum(visitors_count) as visitors
from aggregate_last_paid_click
group by visit_date
order by visit_date;


-- динамика последних платных кликов по дням
select
    visit_date,
    sum(leads_count) as leads
from aggregate_last_paid_click
group by visit_date
order by visit_date;


-- + динамика всех лидов по дням
select
    date(created_at) as lead_date,
    count(*) as leads
from leads
group by 1
order by 1;