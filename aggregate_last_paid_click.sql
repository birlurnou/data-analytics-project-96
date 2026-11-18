with spent as (
    select
        date_trunc('day', campaign_date)::date as visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        sum(daily_spent) as total_cost
    from (
        select campaign_date, utm_source, utm_medium, utm_campaign, daily_spent from vk_ads
        union all
        select campaign_date, utm_source, utm_medium, utm_campaign, daily_spent from ya_ads
    ) ads
    group by 1, 2, 3, 4
),

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

visitor_last_click as (
    select visitor_id, visit_date, utm_source, utm_medium, utm_campaign
    from (
        select *,
            row_number() over (partition by visitor_id order by visit_date desc) as rn
        from paid_clicks
    ) t
    where rn = 1
),

leads_agg as (
    select
        v.visit_date::date as visit_date,
        v.utm_source,
        v.utm_medium,
        v.utm_campaign,
        count(l.lead_id) as leads_count,
        count(case when l.status_id = 142 then l.lead_id end) as purchases_count,
        sum(case when l.status_id = 142 then l.amount end) as revenue
    from visitor_last_click v
    join leads l
        on l.visitor_id = v.visitor_id
       and v.visit_date <= l.created_at
    group by 1, 2, 3, 4
),

visitors_agg as (
    select
        visit_date::date as visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        count(*) as visitors_count
    from visitor_last_click
    group by 1, 2, 3, 4
)

select
    coalesce(v.visit_date, l.visit_date, s.visit_date) as visit_date,
    coalesce(v.visitors_count, 0) as visitors_count,
    coalesce(v.utm_source, l.utm_source, s.utm_source) as utm_source,
    coalesce(v.utm_medium, l.utm_medium, s.utm_medium) as utm_medium,
    coalesce(v.utm_campaign, l.utm_campaign, s.utm_campaign) as utm_campaign,
    s.total_cost,
    coalesce(l.leads_count, 0) as leads_count,
    coalesce(l.purchases_count, 0) as purchases_count,
    coalesce(l.revenue, 0) as revenue
from visitors_agg v
full join leads_agg l
    on v.visit_date = l.visit_date
   and v.utm_source = l.utm_source
   and v.utm_medium = l.utm_medium
   and v.utm_campaign = l.utm_campaign
full join spent s
    on coalesce(v.visit_date, l.visit_date) = s.visit_date
   and coalesce(v.utm_source, l.utm_source) = s.utm_source
   and coalesce(v.utm_medium, l.utm_medium) = s.utm_medium
   and coalesce(v.utm_campaign, l.utm_campaign) = s.utm_campaign
order by
    revenue desc nulls last,
    visit_date asc,
    visitors_count desc,
    utm_source asc,
    utm_medium asc,
    utm_campaign asc