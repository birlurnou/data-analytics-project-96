-- находим платные клики
with paid_clicks as (
    select
        visitor_id,
        visit_date,
        source as utm_source,
        medium as utm_medium,
        campaign as utm_campaign,
        row_number() over (
            partition by visitor_id
            order by visit_date desc
        ) as rn
    from sessions
    where medium in ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),

-- находим последний платный клик
last_paid_click as (
    select
        visitor_id,
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign
    from paid_clicks
    where rn = 1
)

-- формируем витрину
select
    lpc.visitor_id,
    lpc.visit_date,
    lpc.utm_source,
    lpc.utm_medium,
    lpc.utm_campaign,
    l.lead_id,
    l.created_at,
    l.amount,
    l.closing_reason,
    l.status_id
from last_paid_click as lpc
left join leads as l
    on lpc.visitor_id = l.visitor_id
    -- проверка, что лид создан во время или после визита, иначе null
    and (lpc.visit_date <= l.created_at)
order by
    l.amount desc nulls last,
    lpc.visit_date asc,
    lpc.utm_source asc,
    lpc.utm_medium asc,
    lpc.utm_campaign asc
limit 10;
