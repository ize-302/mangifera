# Sourced by focus-window and move-window, with left or right as $1. Sets:
#   dir        left or right
#   monitor    the focused monitor
#   tag        its tag, read from it rather than the focused window, as an
#              empty tag has none
#   focused    the focused window as mmsg prints it, if it's on this tag
#   neighbour  how many tiled windows are on that side of it
#   target     the tag on that side, or empty past the first or last

dir=$1
case "$dir" in
left | right) ;;
*)
	echo "Usage: ${0##*/} left|right" >&2
	exit 1
	;;
esac

read -r monitor tag last < <(mmsg get all-monitors | jq -r '
	[.monitors[] | select(.active)][0] |
	"\(.name) \([.tags[] | select(.is_active)][0].index) \(.tag_num)"')

focused=$(mmsg get focusing-client | jq -c --arg m "$monitor" 'select(.monitor == $m and .is_visible)' 2>/dev/null)

# Another visible window on the same monitor whose middle is further left or
# right than the focused one's
neighbour=0
[ -n "$focused" ] && neighbour=$(mmsg get all-clients | jq --argjson f "$focused" --arg dir "$dir" '
	($f.x + $f.width / 2) as $mid |
	[.clients[] | (.x + .width / 2) as $m | select(
		.id != $f.id and .monitor == $f.monitor and .is_visible and
		(.is_floating or .is_minimized or .is_scratchpad | not) and
		(if $dir == "right" then $m > $mid else $m < $mid end))] | length')

[ "$dir" = right ] && target=$((tag + 1)) || target=$((tag - 1))
[ "$target" -ge 1 ] && [ "$target" -le "$last" ] || target=
