-- находим платные клики
WITH paid_clicks AS (
    SELECT 
        visitor_id,
        visit_date,
        source AS utm_source,
        medium AS utm_medium,
        campaign AS utm_campaign,
        ROW_NUMBER() OVER (
            PARTITION BY visitor_id 
            ORDER BY visit_date DESC
        ) AS rn
    FROM sessions
    WHERE medium IN ('cpc', 'cpm', 'cpa', 'youtube', 'cpp', 'tg', 'social')
),
-- находим последний платный клик
last_paid_click AS (
    SELECT 
        visitor_id,
        visit_date,
        utm_source,
        utm_medium,
        utm_campaign
    FROM paid_clicks
    WHERE rn = 1
)
-- формируем витрину
SELECT 
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
FROM last_paid_click lpc
LEFT JOIN leads l ON lpc.visitor_id = l.visitor_id
-- проверка, что лид создан во время или после визита, иначе null
AND (l.created_at >= lpc.visit_date OR l.created_at IS NULL)
ORDER BY 
    l.amount DESC NULLS LAST,
    lpc.visit_date ASC,
    lpc.utm_source ASC,
    lpc.utm_medium ASC,
    lpc.utm_campaign ASC;
