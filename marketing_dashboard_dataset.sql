/* ===========================================================
   Marketing Performance Dashboard: dataset preparation
   Sources: Facebook Ads + Google Ads (PostgreSQL)
   Output:  a single analytical table for Tableau Public

   Tables
   - Facts:       facebook_ads_basic_daily, google_ads_basic_daily
   - Lookups:     facebook_campaign, facebook_adset
   =========================================================== */


-- 1. URL decoding function (for utm_campaign)
CREATE OR REPLACE FUNCTION pg_temp.decode_url_part(p VARCHAR)
RETURNS VARCHAR AS $$
    SELECT convert_from(
        CAST(
            E'\\x' || string_agg(
                CASE
                    WHEN length(r.m[1]) = 1
                        THEN encode(convert_to(r.m[1], 'SQL_ASCII'), 'hex')
                    ELSE substring(r.m[1] FROM 2 FOR 2)
                END,
                ''
            ) AS BYTEA
        ),
        'UTF8'
    )
    FROM regexp_matches($1, '%[0-9a-f][0-9a-f]|.', 'gi') AS r(m);
$$ LANGUAGE SQL IMMUTABLE STRICT;


-- 2. Unified dataset
WITH

-- Facebook: replace IDs with names (missing names -> 'Unknown')
facebook AS (
    SELECT
        fabd.ad_date,
        'Facebook'                       AS source,
        COALESCE(fc.campaign_name, 'Unknown campaign')  AS campaign_name,
        COALESCE(fa.adset_name,    'Unknown ad set')    AS adset_name,
        COALESCE(fabd.spend,       0)    AS spend,
        COALESCE(fabd.impressions, 0)    AS impressions,
        COALESCE(fabd.reach,       0)    AS reach,
        COALESCE(fabd.clicks,      0)    AS clicks,
        COALESCE(fabd.leads,       0)    AS leads,
        COALESCE(fabd.value,       0)    AS value,
        fabd.url_parameters
    FROM facebook_ads_basic_daily AS fabd
    LEFT JOIN facebook_campaign   AS fc ON fabd.campaign_id = fc.campaign_id
    LEFT JOIN facebook_adset      AS fa ON fabd.adset_id    = fa.adset_id
),

-- Google: names are already text, no lookups needed
google AS (
    SELECT
        gabd.ad_date,
        'Google'                         AS source,
        gabd.campaign_name,
        gabd.adset_name,
        COALESCE(gabd.spend,       0)    AS spend,
        COALESCE(gabd.impressions, 0)    AS impressions,
        COALESCE(gabd.reach,       0)    AS reach,
        COALESCE(gabd.clicks,      0)    AS clicks,
        COALESCE(gabd.leads,       0)    AS leads,
        COALESCE(gabd.value,       0)    AS value,
        gabd.url_parameters
    FROM google_ads_basic_daily AS gabd
),

-- Combine platforms and decode utm_campaign
combined AS (
    SELECT
        u.ad_date,
        u.source,
        u.campaign_name,
        u.adset_name,
        NULLIF(
            lower(
                pg_temp.decode_url_part(
                    substring(u.url_parameters FROM 'utm_campaign=([^&#$]+)')
                )
            ),
            'nan'
        )                                AS utm_campaign,
        u.spend,
        u.impressions,
        u.reach,
        u.clicks,
        u.leads,
        u.value
    FROM (
        SELECT * FROM facebook
        UNION ALL
        SELECT * FROM google
    ) AS u
)

-- Total metrics by date, platform, campaign and ad set
SELECT
    ad_date,
    source,
    campaign_name,
    adset_name,
    utm_campaign,
    SUM(spend)         AS total_spend,
    SUM(clicks)        AS total_clicks,
    SUM(impressions)   AS total_impressions,
    SUM(reach)         AS total_reach,
    SUM(leads)         AS total_leads,
    SUM(value)         AS total_value
FROM combined
GROUP BY
    ad_date,
    source,
    campaign_name,
    adset_name,
    utm_campaign
ORDER BY
    ad_date,
    source,
    campaign_name;