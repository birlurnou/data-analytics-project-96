-- считаем все затраты на маркетинг
-- агрегируем сумму затрат и группируем по дате, источнику, типу и названию
-- рекламной компании
with spent as (
    select
        date_trunc('day', campaign_date) as campaign_date,
        utm_source,
        utm_medium,
        utm_campaign,
        sum(daily_spent) as total_cost
    from vk_ads
    group by 1, 2, 3, 4
    union all
    select
        date_trunc('day', campaign_date) as campaign_date,
        utm_source,
        utm_medium,
        utm_campaign,
        sum(daily_spent) as total_cost
    from ya_ads
    group by 1, 2, 3, 4
),

-- привязываем клики к лидам, 
-- которые были созданы после клика (только платные клики)
leads_clicks as (
    select
        s.visitor_id,
        s.visit_date,
        s.source as utm_source,
        s.medium as utm_medium,
        s.campaign as utm_campaign,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id,
        row_number() over (
            partition by s.visitor_id
            order by s.visit_date desc
        ) as rn,
        dense_rank() over (
            order by s.visitor_id
        ) as visitor_rank
    from sessions as s
    left join leads as l
        on
            s.visitor_id = l.visitor_id
            and s.visit_date <= l.created_at
    where s.medium in ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),

-- считаем агрегации (количество посещений и лидов, количество и сумма покупок)
-- группируем также по дате, источнику, типу и названию рекламной компании
last_paid_click as (
    select
        visit_date::date,
        utm_source,
        utm_medium,
        utm_campaign,
        count(visitor_id) as visitors_count,
        count(lead_id) as leads_count,
        sum(
            case
                when status_id = 142 then 1
            end
        ) as purchases_count,
        sum(
            case
                when status_id = 142 then amount
            end
        ) as revenue
    from leads_clicks
    where rn = 1
    group by 1, 2, 3, 4
)

-- формируем итоговую витрину, объединяя визиты и лидов с затратами на рекламу
select
    l.visit_date,
    l.visitors_count,
    l.utm_source,
    l.utm_medium,
    l.utm_campaign,
    s.total_cost,
    l.leads_count,
    l.purchases_count,
    l.revenue
from last_paid_click as l
left join spent as s
    on
        l.visit_date = s.campaign_date::date
        and l.utm_source = s.utm_source
        and l.utm_medium = s.utm_medium
        and l.utm_campaign = s.utm_campaign
order by
    l.revenue desc nulls last,
    l.visit_date asc,
    l.visitors_count desc,
    l.utm_source asc,
    l.utm_medium asc,
    l.utm_campaign asc
limit 15;
