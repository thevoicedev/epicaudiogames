-- Reports on the apps' usage data: views over the events table server.js keeps (analytics/store.js has its columns,
-- analytics/events.json the events and their props). Run this file in the Postgres service's Data tab on Railway
-- (Query), or let tools/analytics_report.py run it and print the reports; then `select * from report_funnel` and so
-- on. It drops the views and makes them again, so it can be run as often as needed: they hold no data.
--
-- Times are the phone's own (ts) where it sent one, else when the server got the event; days are UTC days. The
-- install the smoke tests use (00000000-0000-4000-8000-000000000001) is left out of every report.

drop view if exists report_events, report_funnel, report_games, report_chapter_ends, report_drop_off, report_shop,
  report_retention, report_devices, usage_events cascade;

-- Every event but the smoke tests', with one time to go by.
create view usage_events as
select e.*, coalesce(e.ts, e.received_at) as happened_at
from events e
where e.install_id <> '00000000-0000-4000-8000-000000000001';

-- What's arriving: each event's count, installs, and first and last time.
create view report_events as
select name, count(*) as events, count(distinct install_id) as installs,
  min(happened_at) as first_at, max(happened_at) as last_at
from usage_events
group by name
order by events desc;

-- How far players get: how many installs did each step at least once, and what share that is of the installs that
-- opened the app. (The intro only plays with its sound on, so fewer finish it.)
create view report_funnel as
with steps (n, step, event_name, kind, result) as (values
  (1, 'Opened the app', 'app_open', null, null),
  (2, 'Finished the intro', 'intro_finished', null, null),
  (3, 'Finished or skipped the welcome', 'onboarding_finished', null, null),
  (4, 'Opened a game', 'game_open', null, null),
  (5, 'Finished a chapter', 'game_end', 'chapter', null),
  (6, 'Opened the shop', 'shop_view', null, null),
  (7, 'Bought a pack', 'purchase_result', null, 'purchased')),
reached as (
  select s.n, s.step, count(distinct u.install_id) as installs
  from steps s
  left join usage_events u
    on u.name = s.event_name
    and (s.kind is null or u.props->>'kind' = s.kind)
    and (s.result is null or u.props->>'result' = s.result)
  group by s.n, s.step)
select n, step, installs,
  round(100.0 * installs / nullif(max(installs) filter (where n = 1) over (), 0), 1) as pct_of_opened
from reached
order by n;

-- Each game: how many installs opened it, finished a chapter, reached the end or a game over, or hit the end of
-- the free part; restarts and errors; and how the answers were given (counts from game_leave, never the answers).
create view report_games as
select props->>'game' as game,
  count(distinct install_id) filter (where name = 'game_open') as players,
  count(*) filter (where name = 'game_open') as opens,
  count(distinct install_id) filter (where name = 'game_end' and props->>'kind' = 'chapter') as finished_a_chapter,
  count(*) filter (where name = 'chapter_next') as next_chapters,
  count(distinct install_id) filter (where name = 'game_end' and props->>'kind' = 'end') as reached_the_end,
  count(distinct install_id) filter (where name = 'game_end' and props->>'kind' = 'gameover') as had_a_game_over,
  count(distinct install_id) filter (where name = 'locked_end') as reached_a_locked_end,
  count(*) filter (where name = 'game_restart') as restarts,
  count(*) filter (where name = 'game_error') as errors,
  coalesce(sum((props->>'answers_voice')::bigint) filter (where name = 'game_leave'), 0) as answers_spoken,
  coalesce(sum((props->>'answers_typed')::bigint) filter (where name = 'game_leave'), 0) as answers_typed,
  coalesce(sum((props->>'answers_tapped')::bigint) filter (where name = 'game_leave'), 0) as answers_tapped
from usage_events
where props ? 'game'
group by 1
order by players desc, game;

-- Which ends players reach in each game: a chapter's end, a game over or the end, by the story's node id.
create view report_chapter_ends as
select props->>'game' as game, props->>'kind' as kind, props->>'node' as node,
  count(*) as times, count(distinct install_id) as installs
from usage_events
where name = 'game_end'
group by 1, 2, 3
order by game, installs desc, node;

-- Where players leave each game: the node they were at, how often, and how long they'd played.
create view report_drop_off as
select props->>'game' as game, props->>'node' as node,
  count(*) as leaves, count(distinct install_id) as installs,
  round(avg((props->>'seconds')::numeric)) as avg_seconds,
  round(avg((props->>'turns')::numeric), 1) as avg_turns,
  coalesce(sum((props->>'silences')::bigint), 0) as silences
from usage_events
where name = 'game_leave'
group by 1, 2
order by leaves desc, game, node;

-- The shop, by where it was opened from: views, and the purchases started and made after a view from there in the
-- same session (a purchase counts for the last shop view before it).
create view report_shop as
with views as (
  select props->>'source' as source, count(*) as views, count(distinct install_id) as installs
  from usage_events
  where name = 'shop_view'
  group by 1),
buys as (
  select p.name, p.props->>'result' as result,
    (select v.props->>'source'
     from usage_events v
     where v.install_id = p.install_id and v.session_id = p.session_id and v.name = 'shop_view' and v.seq < p.seq
     order by v.seq desc
     limit 1) as source
  from usage_events p
  where p.name in ('purchase_start', 'purchase_result'))
select v.source, v.views, v.installs,
  count(b.name) filter (where b.name = 'purchase_start') as purchases_started,
  count(b.name) filter (where b.name = 'purchase_result' and b.result = 'purchased') as purchased,
  round(100.0 * count(b.name) filter (where b.name = 'purchase_result' and b.result = 'purchased')
    / nullif(v.views, 0), 1) as pct_purchased_per_view
from views v
left join buys b on b.source = v.source
group by v.source, v.views, v.installs
order by v.views desc;

-- Day 1 and day 7 retention by the day an install was first seen: the share that used the app again exactly 1 and 7
-- days later (empty until that day is over).
create view report_retention as
with days as (
  select distinct install_id, (happened_at at time zone 'UTC')::date as day
  from usage_events),
firsts as (
  select install_id, min(day) as first_day
  from days
  group by install_id),
cohorts as (
  select f.first_day,
    exists (select 1 from days d where d.install_id = f.install_id and d.day = f.first_day + 1) as d1,
    exists (select 1 from days d where d.install_id = f.install_id and d.day = f.first_day + 7) as d7
  from firsts f)
select first_day, count(*) as installs,
  case when first_day + 1 < (now() at time zone 'UTC')::date
    then round(100.0 * count(*) filter (where d1) / count(*), 1) end as d1_pct,
  case when first_day + 7 < (now() at time zone 'UTC')::date
    then round(100.0 * count(*) filter (where d7) / count(*), 1) end as d7_pct
from cohorts
group by first_day
order by first_day desc;

-- What the apps run on: installs and events by app (ios or android) and kind of device (phone, tablet, desktop or
-- watch; "unknown" from an app version that didn't send it). An install counts once for each kind it was used as: a
-- foldable can be a phone folded and a tablet open.
create view report_devices as
select coalesce(platform, 'unknown') as platform, coalesce(form_factor, 'unknown') as form_factor,
  count(distinct install_id) as installs, count(*) as events
from usage_events
group by 1, 2
order by installs desc, platform, form_factor;
