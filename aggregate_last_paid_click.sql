-- считаем все затраты на маркетинг
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

-- находим все платные клики
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

-- находим и нумеруем все платные клики до лида
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

-- находим последние клики перед конвертацией в лида
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

-- строим финальную витрину
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
        and coalesce(v.utm_campaign, l.utm_campaign) = s.utm_campaign
order by
    revenue desc nulls last,
    visit_date asc,
    visitors_count desc,
    utm_source asc,
    utm_medium asc,
    utm_campaign asc;
