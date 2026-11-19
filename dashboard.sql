-- все запросы построены на основе главной витрины aggregate_last_paid_click
-- по данным витрины создавались чарты и формировался дашборд
-- ! перестроены под модель last_paid_click !

-- 1 создаем представление aggregate_last_paid_click
create view aggregate_last_paid_click as

-- находим последнюю сессию каждого посетителя и привязываем к ней лид, если он был создан после этой сессии
with last_paid_click as (
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
        -- нумеруем сессии
        row_number() over (
            partition by s.visitor_id
            order by s.visit_date desc
        ) as rn
    from sessions as s
    left join leads as l
        on s.visitor_id = l.visitor_id
       and s.visit_date <= l.created_at
    where s.medium != 'organic'
),

-- оставляем только последнюю сессию каждого посетителя и группируем
lpc as (
    select
        visit_date::date as visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        count(visitor_id) as visitors_count,
        count(lead_id) as leads_count,
        count(case when status_id = 142 then 1 end) as purchases_count,
        sum(amount) as revenue
    from last_paid_click
    where rn = 1
    group by 1, 2, 3, 4
),

-- собираем расходы по рекламным кампаниям и группируем
ads as (
    select
        campaign_date::date as visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        sum(daily_spent) as daily_spent
    from ya_ads group by 1, 2, 3, 4
    union all
    select
        campaign_date::date as visit_date,
        utm_source,
        utm_medium,
        utm_campaign,
        sum(daily_spent) as daily_spent
    from vk_ads group by 1, 2, 3, 4
)

-- джойним метрики last click с расходами по дате и меткам и оставляем только те строки, где utm_source is not null
select
    lpc.visit_date,
    lpc.visitors_count,
    lpc.utm_source,
    lpc.utm_medium,
    lpc.utm_campaign,
    ads.daily_spent as total_cost,
    lpc.leads_count,
    lpc.purchases_count,
    lpc.revenue
from lpc
left join ads
    on ads.visit_date = lpc.visit_date
   and ads.utm_source = lpc.utm_source
   and ads.utm_medium = lpc.utm_medium
   and ads.utm_campaign = lpc.utm_campaign
where ads.utm_source is not null
order by
    revenue desc nulls last,
    visit_date asc,
    visitors_count desc,
    utm_source asc,
    utm_medium asc,
    utm_campaign asc;



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