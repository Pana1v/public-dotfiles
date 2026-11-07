#!/usr/bin/env bash
# Claude Code status line. Also writes ~/.claude/rate-cache.json for the conky
# Claude panel (session 5h and weekly 7d limit percentages).
in=$(cat)
dir="$HOME/.claude"
printf '%s' "$in" > "$dir/statusline-last.json"

r5=$(jq -r '.rate_limits.five_hour.used_percentage // empty' <<<"$in" | cut -d. -f1)
r7=$(jq -r '.rate_limits.seven_day.used_percentage // empty' <<<"$in" | cut -d. -f1)
r5r=$(jq -r '.rate_limits.five_hour.resets_at // empty' <<<"$in")
r7r=$(jq -r '.rate_limits.seven_day.resets_at // empty' <<<"$in")

if [ -n "$r5" ] && [ -n "$r7" ]; then
  printf '{"r5":%s,"r7":%s,"r5_resets_at":%s,"r7_resets_at":%s,"ts":%s}\n' \
    "$r5" "$r7" "${r5r:-null}" "${r7r:-null}" "$(date +%s)" > "$dir/rate-cache.json.tmp" \
    && mv "$dir/rate-cache.json.tmp" "$dir/rate-cache.json"
fi

model=$(jq -r '.model.display_name // "claude"' <<<"$in")
cwd=$(jq -r '.workspace.current_dir // .cwd // ""' <<<"$in")

# Context window: tokens in the last request (input + cache) against the
# window size. used_percentage is null until the first reply of a session.
ctx=$(jq -r '
  .context_window as $c
  | ($c.context_window_size // 0) as $size
  | ($c.current_usage // {}) as $u
  | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) as $used
  | def k: if . >= 1000000 then "\(. / 1000000 | . * 10 | floor / 10)M"
           elif . >= 1000 then "\(. / 1000 | floor)k" else "\(.)" end;
  if $c.used_percentage == null then "ctx -"
  else "ctx \($c.used_percentage | floor)% (\($used | k)/\($size | k))" end
' <<<"$in")

echo "${model} · ${cwd##*/} · ${ctx} · 5h ${r5:--}% · 7d ${r7:--}%"
