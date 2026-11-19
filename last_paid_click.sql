-- сначала находим все платные клики
with paid_clicks as (
    select
        visitor_id,
        visit_date,
        source as utm_source,
        medium as utm_medium,
        campaign as utm_campaign
    from sessions
    where medium in ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),

-- для каждого лида находим последний платный клик перед конвертацией в лида
lead_last_click as (
    select
        l.lead_id,
        l.visitor_id,
        l.created_at,
        pc.visit_date as click_date,
        row_number() over (
-- изменил партицию
            partition by pc.visitor_id
            order by pc.visit_date desc
        ) as rn
    from leads as l
    inner join paid_clicks as pc
        on
            l.visitor_id = pc.visitor_id
            and l.created_at >= pc.visit_date
),

-- оставляем только последний клик для каждого лида
last_paid_click as (
    select
        lead_id,
        visitor_id,
        click_date
    from lead_last_click
    where rn = 1
),

-- формируем витрину со всеми платными кликами
-- и если платный клик привел лида - джоиним этого лида к клику
visits_with_leads as (
    select
        pc.visitor_id,
        pc.visit_date,
        pc.utm_source,
        pc.utm_medium,
        pc.utm_campaign,
        l.lead_id,
        l.created_at,
        l.amount,
        l.closing_reason,
        l.status_id
    from paid_clicks as pc
    left join last_paid_click as lpc
        on
            pc.visitor_id = lpc.visitor_id
            and pc.visit_date = lpc.click_date
    left join leads as l on lpc.lead_id = l.lead_id
)

select
    visitor_id,
    visit_date,
    utm_source,
    utm_medium,
    utm_campaign,
    lead_id,
    created_at,
    amount,
    closing_reason,
    status_id
from visits_with_leads
order by
    amount desc nulls last,
    visit_date asc,
    utm_source asc,
    utm_medium asc,
    utm_campaign asc;
